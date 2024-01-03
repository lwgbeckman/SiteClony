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
get_deets() {

  echo -e "${RED}SOURCE${ENDCOLOR}\n\nServer: $source_server\nDomain: $source_domain\nAccount: $source_account\nDocroot: $source_docroot\n\nDB name: $source_DB_name\nDB user: $source_DB_user\nDB pass: $source_DB_pass\n\n\n"
  echo -e "${GREEN}TARGET${ENDCOLOR}\n\nServer: $target_server\nDomain: $target_domain\nAccount: $target_account\nDocroot: $target_docroot\n\nDB name: $target_DB_name\nDB user: $target_DB_user\nDB pass: $target_DB_pass\n\n"

}


# Check if a doamin is valid, if not prompt for a new selection
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
get_domain_options() {

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
  
  getTargetInfo
}


###############
# Domain info #
###############

# Generate source domain info
getSourceInfo() {

  source_server=$(hostname)
  source_domain=$(grep -wf $DIR/out.tmp $OPTIONS_FILE | awk '{print $2}')
  source_account=$(egrep "^$source_domain:" /etc/userdatadomains | awk -F " |==" '{print $2}')
  echo -e "Selected $source_domain ($source_account)" >> $DOMAIN_SELECTION_LOG
  
  # Remove the selected domain from the list 
  #sed -i "/^$(cat $DIR/out.tmp) /d" $OPTIONS_FILE
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
  target_domain=$(grep -wf $DIR/out.tmp $OPTIONS_FILE | awk '{print $2}')
  target_account=$(egrep "^$target_domain:" /etc/userdatadomains | awk -F " |==" '{print $2}')
  echo -e "Selected $target_domain ($target_account)" >> $DOMAIN_SELECTION_LOG
  
  # Remove the selected domain from the list 
  #sed -i "/^$(cat $DIR/out.tmp) /d" $OPTIONS_FILE
  sed -i "/ $target_domain /d" $OPTIONS_FILE
  
  target_docroot=$(awk -F "==|:" '{print $1, $6}' /etc/userdatadomains | egrep "^$target_domain " | cut -d " " -f 2)
  validate "$target_docroot" "Unable to find the document root" "Docroot found:"
  
  # Checking if wp-config already exists
  target_config=$(find $target_docroot -type f -name wp-config.php | head -1)
  if [ -z $target_config ]
  then
    # wp-config already exists, using the DB info from there
    echo -e "No config found. Generating new DB info. Assuming config will be: $target_docroot/wp-config.php" >> $DOMAIN_SELECTION_LOG
    target_config="$target_docroot/wp-config.php"
    target_DB_name="$(awk -F. '{print $1}' <<< $target_domain)_wp$((RANDOM % 999 + 100))"
    target_DB_user=$target_DB_name
    target_DB_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-24})
  else
    # wp-config doesn't exist, generating new DB info
    echo -e "Config found: $target_config" >> $DOMAIN_SELECTION_LOG
    target_DB_name=$(grep DB_NAME $target_config | awk -F "'" '{print $4}')
    target_DB_user=$(grep DB_USER $target_config | awk -F "'" '{print $4}')
    target_DB_pass=$(grep DB_PASS $target_config | awk -F "'" '{print $4}')
  fi
  
}