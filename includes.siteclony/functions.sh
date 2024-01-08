#!/bin/bash

# Exit and cleanup (Executed when we get SIGINT or when any cancel/quit buttons are selected)
quit() {

  clear
  echo -e "\nScript terminated.\nExiting...\n\n"
  exit 0

}

# Version 
Version()
{
  echo -e "\tSiteClony - cPanel WP site clone script"
  echo -e "\tVersion: ${GREEN}$version${ENDCOLOR}\n"
}

# Help 
Help()
{
   # Display Help
   echo -e "\nSiteClony is a simple site clone script for WordPress websites on a cPanel server"
   echo
   echo -e "${YELLOW}Syntax: sh siteclony.sh [-h|V]${ENDCOLOR}\n"
   echo -e "OPTIONS\n"
   echo -e "    -h	   Output a usage message and exit."
   echo -e "    -V	   Output the version number of SiteClony and exit."
   echo
}

# Pre clone info
getDeets() {

  echo -e "${RED}SOURCE${ENDCOLOR}\n\nServer: $source_server\nDomain: $source_domain\nAccount: $source_account\nDocroot: $source_docroot\n\nDB name: $source_DB_name\nDB user: $source_DB_user\nDB pass: $source_DB_pass\n\n\n"
  echo -e "${GREEN}TARGET${ENDCOLOR}\n\nServer: $target_server\nDomain: $target_domain\nAccount: $target_account\nDocroot: $target_docroot\n\nDB name: $target_DB_name\nDB user: $target_DB_user\nDB pass: $target_DB_pass\n\n"

}


# Check if a domain is valid, if not prompt for a new selection
validate() {
  if [[ -z $1 ]]
  then
    # The variable is empty, throw out an error and ask to choose a new domain
    echo $2 >> $DOMAIN_SELECTION_LOG
    clear
    
    if dialog --colors --no-label "Exit" --yes-label "Ok" --yesno "\Z1$2 \Zn\n\nDo you want to choose a new domain?" 10 40
    then
      echo -e "\nSelecting a new domain" >> $DOMAIN_SELECTION_LOG
      sourceDomainSelection
    else
      clear
      exit 0
    fi
  else
    echo -e "$3 $1" >> $DOMAIN_SELECTION_LOG
  fi
}


####################
# Domain Selection #
####################

# Domain options generation logic
getDomainOptions() {

  > $OPTIONS_FILE 
  n=1
  
  # Generate the list of options with all domains
  for domain in $(whmapi1 get_domain_info | grep " domain:" | awk -F ": " '{print $2}') 
  do
  	echo "$n $domain OFF" >> $OPTIONS_FILE
  	n=$(($n+1))
  done

}

# Source domain selection logic
sourceDomainSelection() {
  
  # Set the first option as default
  sed -i "1,/OFF/{s|OFF|ON|}" $OPTIONS_FILE
  
  # Select the source domain
  dialog --backtitle "Select the source domain" --radiolist "Select the source domain:" 30 40 $max_domains --file $OPTIONS_FILE 2> $DIR/out.tmp
   
  if [ ! -s $DIR/out.tmp ]
  then 
    quit
  fi 
 
  getSourceInfo
  
}

# Target domain selection logic
targetDomainSelection() {

  # Add the option to add a new domain and set it as default
  sed -i "1 i\0 \"Add New Domain\" ON" $OPTIONS_FILE
  
  dialog --backtitle "Select the target domain" --radiolist "Select the target domain:" 30 40 $(($max_domains-1)) --file $OPTIONS_FILE 2> $DIR/out.tmp

  if [ ! -s $DIR/out.tmp ]
  then 
    quit
  fi 
  
  id=$(cat $DIR/out.tmp)
  if [ ! $id -eq 0 ]
  then
    domain=$(grep -wf $DIR/out.tmp $OPTIONS_FILE | awk '{print $2}')
    getTargetInfo $domain
  fi
}


###############
# Domain info #
###############

# TODO: Refactor these 2 functions into a single, more generic one
# It should just be 'getDomainInfo' and it takes in the domain as a parameter
# It also needs to know if it's checking a source or target domain
# We can generate wp-config info for target, but need to exit if the source doesn't have it
# The simplest way would be to have the source/target be another parameter, can just be a string ¯\_(ツ)_/¯

# Generate source domain info
getSourceInfo() {

  source_server=$(hostname)
  source_domain=$(grep -wf $DIR/out.tmp $OPTIONS_FILE | awk '{print $2}')
  source_account=$(egrep "^$source_domain:" /etc/userdatadomains | awk -F " |==" '{print $2}')
  echo -e "Selected $source_domain ($source_account)" >> $DOMAIN_SELECTION_LOG
  
  # Remove the selected domain from the list 
  sed -i "/ $source_domain /d" $OPTIONS_FILE
  
  source_docroot=$(awk -F "==|:" '{print $1, $6}' /etc/userdatadomains | egrep "^$source_domain " | cut -d " " -f 2)
  validate "$source_docroot" "Unable to find the document root" "Docroot found:"
  
  source_config=$(find $source_docroot -type f -name wp-config.php | head -1)
  validate "$source_config" "No config found" "Config found:"
  
  source_DB_name=$(grep DB_NAME $source_config | awk -F "'" '{print $4}')
  source_DB_user=$(grep DB_USER $source_config | awk -F "'" '{print $4}')
  source_DB_pass=$(grep DB_PASS $source_config | awk -F "'" '{print $4}')
  
}


# Generate target domain info
getTargetInfo() {
  
  target_server=$(hostname)
  target_domain=$1
  target_account=$(egrep "^$target_domain:" /etc/userdatadomains | awk -F " |==" '{print $2}')
  echo -e "Selected $target_domain ($target_account)" >> $DOMAIN_SELECTION_LOG
  
  # Remove the selected domain from the list 
  sed -i "/ $target_domain /d" $OPTIONS_FILE
  
  target_docroot=$(awk -F "==|:" '{print $1, $6}' /etc/userdatadomains | egrep "^$target_domain " | cut -d " " -f 2)
  # Make sure the docroot exists
  if [[ -z $target_docroot ]]
  then
    # The docroot couldn't be found, throw out an error and return out of the function
    echo $2 >> $ERROR_LOG
    return 1
  fi

  # Checking if wp-config already exists
  target_config=$(find $target_docroot -type f -name wp-config.php | head -1)
  if [ -z $target_config ]
  then
    # wp-config doesn't exist, generating new DB info
    echo -e "No config found. Generating new DB info. Assuming config will be: $target_docroot/wp-config.php" >> $DOMAIN_SELECTION_LOG
    target_config="$target_docroot/wp-config.php"
    target_DB_name="$(awk -F. '{print $1}' <<< $target_domain)_wp$((RANDOM % 999 + 100))"
    target_DB_user=$target_DB_name
    target_DB_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c 24)
  else
    # wp-config already exists, using the DB info from there
    echo -e "Config found: $target_config" >> $DOMAIN_SELECTION_LOG
    target_DB_name=$(grep DB_NAME $target_config | awk -F "'" '{print $4}')
    target_DB_user=$(grep DB_USER $target_config | awk -F "'" '{print $4}')
    target_DB_pass=$(grep DB_PASS $target_config | awk -F "'" '{print $4}')
  fi
  
}

#####################
# New target domain #
#####################

checkDomain(){

  domain=$1

  # Regex that should match only a valid, full domain name
  pattern="^([a-z0-9])(([a-z0-9-]{1,61})?[a-z0-9]{1})?(\.[a-z0-9](([a-z0-9-]{1,61})?[a-z0-9]{1})?)?(\.[a-zA-Z]{2,4})+$"
  
  if [[ $domain =~ $pattern ]]
  then
  
    # The domain name IS valid
    echo "$domain is a valid domain name!" >> $LOG
    
    # Check if the domain already exists on the server
    match=$(whmapi1 get_domain_info | grep " domain:" | awk -F ": " '{print $2}' | egrep "^$domain$")
  
    if [ -z $match ]
    then
      # The domain DOESN'T exist on the server and it is valid
      echo "The domain doesn't yet exist on the server!" >> $LOG
      return 0
    else
      # The domain DOES exist on the server
      echo "${RED}[ERROR]${ENDCOLOR} $domain already exists on the server!" >> $ERROR_LOG
      return 1
    fi

  else
    # The domain name is NOT valid
    echo "${RED}[ERROR]${ENDCOLOR} $domain is NOT a valid domain name!" >> $ERROR_LOG
    return 1
  fi
}

###############
# New Account #
###############

# Check if the username is valid (Doesn't exist yet and is not a reserved alias)
checkUsername(){

  username=$1

  # Check if an account with the same username already exists
  match=$(whmapi1 listaccts | grep user: | awk -F ": " '{print $2}' | egrep "^$username")
  
  if [ -z $match ]
  then
    # The username doesn't exist, continuing
    # Checking if it's valid (not one of the reserved usernames)
    match=$(awk -F: '{print $1}' /etc/aliases | tr -d "#" | egrep "^$username$")
    
    if [ -z $match ]
    then
      # It's not a reserved username, returning
      target_username=$username
      return 0
    else
      # It is a reserved username, exiting
      clear
      echo -e "${RED}[ERROR]${ENDCOLOR} The username $username is a reserved alias!\nExiting..." >> $ERROR_LOG
      return 1
    fi

  else
    # The username is invalid, exiting
    clear
    echo -e "${RED}[ERROR]${ENDCOLOR} The user $username already exists!\nExiting..." >> $ERROR_LOG
    return 1
  fi
}

# Check if the password meets the server requirements
checkPass(){

  pass=$1

  # Get info about required pass strength and selected pass strength
  MIN_PW_STRENGTH=$(whmapi1 getminimumpasswordstrengths | grep createacct | awk -F ": " '{print $2}')
  pw_strength=$(whmapi1 get_password_strength password="$pass" | grep strength: | awk -F ": " '{print $2}')

  if [ $pw_strength -ge $MIN_PW_STRENGTH ]
  then

    # The pass is strong enough
    echo "The selected password is valid" >> $LOG
    return 0

  else

    # The password is too weak
    echo "${RED}[ERROR]${ENDCOLOR}The selected password is too weak!" >> $ERROR_LOG
    return 1

  fi
}

# Create the cPanel account
createAcc(){

  new_user=$1
  new_domain=$2
  new_pass=$3

  ### Creating the account with the selected username and password
  whmapi1 createacct username="$new_user" domain="$new_domain" password="$new_pass" > $DIR/out.tmp
  result=$(grep "result: " $DIR/out.tmp | awk '{print $2}')

  if [[ result -eq 0 ]]
  then
    # Something went wrong, couldn't create the account
    # TODO: implement checking on what went wrong and throw the user back to that selection screen
    cat $DIR/out.tmp > $ERROR_LOG
    reason=$(grep "reason: " $DIR/out.tmp | awk -F": " '{print $2}')
    clear
    echo -e "${RED}[ERROR]${ENDCOLOR} $reason (${RED}cat $ERROR_LOG${ENDCOLOR})"
    return 1
  fi

  return 0
}


