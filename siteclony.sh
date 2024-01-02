#!/bin/bash

# Download the required files if they don't already exist
if [ ! -d /root/includes.siteclony ]
then
  # Creating the directory
  mkdir /root/includes.siteclony

  # Downloading the files
  # functions
  wget -q https://raw.githubusercontent.com/lwgbeckman/SiteClony/main/includes.siteclony/functions.sh -P /root/includes.siteclony/
  chmod +x /root/includes.siteclony/functions.sh
  # variables
  wget -q https://raw.githubusercontent.com/lwgbeckman/SiteClony/main/includes.siteclony/variables.sh -P /root/includes.siteclony/
  chmod +x /root/includes.siteclony/variables.sh
  # logo
  wget -q https://raw.githubusercontent.com/lwgbeckman/SiteClony/main/includes.siteclony/logo.txt -P /root/includes.siteclony/
fi

# Include the scripts from ./includes
for script in /root/includes.siteclony/*.sh
do
  source $script
done


#############################
# Process the input options #
#############################

while getopts ":hV" option; do
  case $option in
	  h) # Display Help
       Help
       exit;;
	  V) # Print script version
      Version
      exit;;	   
    \?) # Invalid option
      echo -e "${RED}[ERROR] Invalid option${ENDCOLOR}\n"
      Help
      exit;; 
    esac
done


# Catch SIGINT (Ctrl+C) and execute the 'quit' function 
trap quit INT


#####################
# Dir and file prep #
#####################

unlink /home/temp/siteclony
dir_date=$(date +'%m-%d-%Y_%X' | tr -d ' ')
DIR="/home/temp/siteclony_$dir_date"
mkdir $DIR
ln -s $DIR /home/temp/siteclony

OPTIONS_FILE="$DIR/domainlist.txt"
INFO_FILE="$DIR/info.txt"
ERROR_LOG="$DIR/error.log"
LOG="$DIR/siteclony.log"
DOMAIN_SELECTION_LOG="$DIR/domain_selection.log"


########
# Main #
########

# Get the number of domains on the server
max_domains=$(whmapi1 get_domain_info | grep " domain:" | wc -l)

# Select the source domain
echo -e "Selecting the SOURCE domain\n" >> $DOMAIN_SELECTION_LOG
get_domain_options
sourceDomainSelection

# Select the target domain
echo -e "\nSelecting the TARGET domain\n" >> $DOMAIN_SELECTION_LOG
get_domain_options
# Remove the source domain from the list
sed -i "/ $source_domain /d" $OPTIONS_FILE
targetDomainSelection


# Check if the "Add New Domain" option was selected
id=$(cat $DIR/out.tmp)

if [ $id -eq 0 ]
then

  # Ask for the new domain name
  dialog --backtitle "Choose a name for the new domain" --inputbox "Choose a name for the new domain " 8 60 2> $DIR/out.tmp
  
  target_domain=$(cat $DIR/out.tmp)
  
  #Check if the domain name is valid
  pattern="^([a-z0-9])(([a-z0-9-]{1,61})?[a-z0-9]{1})?(\.[a-z0-9](([a-z0-9-]{1,61})?[a-z0-9]{1})?)?(\.[a-zA-Z]{2,4})+$"
  
  if [[ $target_domain =~ $pattern ]]
  then
  
    # The domain name IS valid, continuing
    echo "$target_domain is a valid domain name!" >> $LOG
    
    # Check if the domain already exists on the server
    match=$(whmapi1 get_domain_info | grep " domain:" | awk -F ": " '{print $2}' | egrep "^$target_domain$")
  
    if [ -z $match ]
    then
    
      # The domain DOESN'T exist on the server, continuing
      echo "The domain doesn't yet exist on the server!" >> $LOG
      
      # User selection
      OPTIONS_FILE="$DIR/accountlist.txt"
      account_num=$(whmapi1 listaccts | grep user: | wc -l)
  
      n=1

      # Prepare the list of options with all accounts
      for account in $(whmapi1 listaccts | grep user: | awk -F ": " '{print $2}') 
      do
	      echo "$n $account OFF" >> $OPTIONS_FILE
    	  n=$(($n+1))
      done
  
      # Add the option to create a new account and set it as default
      sed -i "1 i\0 \"Create New Account\" ON" $OPTIONS_FILE

      dialog --backtitle "Select the target account" --radiolist "Select the target account:" 30 40 $account_num --file $OPTIONS_FILE 2> $DIR/out.tmp

  
      # Check if the "Create New Account" option was selected
      id=$(cat $DIR/out.tmp)
  
      if [ $id -eq 0 ]
      then
        
        # Creating the new account
        
        # Asking for the new account info
        random_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-24})
        suggested_username=$(awk -F. '{print $1}' <<< $target_domain)
        
        dialog --backtitle "Provide the information for the new account" --title "Create a new account" --form "New account information" 15 50 3 "Username:" 1 3 "$suggested_username" 1 15 25 25 "Password:" 3 3 "$random_pass" 3 15 25 25 2> $DIR/out.tmp
  
        selected_username=$(head -1 $DIR/out.tmp)
        selected_password=$(tail -1 $DIR/out.tmp)
  
        # Check if an account with the same username already exists
        match=$(whmapi1 listaccts | grep user: | awk -F ": " '{print $2}' | egrep "^$selected_username")
        
        if [ -z $match ]
        then
        
          # The username doesn't exist
          echo "The user $selected_username doesn't exist" >> $LOG
          
          # Checking if it's valid (not one of the reserved usernames)
          match=$(awk -F: '{print $1}' /etc/aliases | tr -d "#" | egrep "^$selected_username$")
          
          if [ -z $match ]
          then
          
            # It's not a reserved username, continuing
            echo "The username $selected_username is not a reserved alias!" >> $LOG
            target_username=$selected_username
            
            # Check if the password meets the requirements
            pw_strength=$(whmapi1 get_password_strength password="$selected_password" | grep strength: | awk -F ": " '{print $2}')
        
            MIN_PW_STRENGTH=$(whmapi1 getminimumpasswordstrengths | grep createacct | awk -F ": " '{print $2}')
        
            if [ $pw_strength -ge $MIN_PW_STRENGTH ]
            then
          
              # Both the password and username are valid, creating the account
              echo "The selected password is valid" >> $LOG
            
              ### Creating the account with the selected username and password
              whmapi1 createacct username="$target_username" domain="$target_domain" password="$selected_password" 2>> $ERROR_LOG 1>> $LOG
          
            else
          
              # The password is too weak, exiting
              clear
              echo "The selected password is too weak" | tee -a $ERROR_LOG
              exit 0
            
            fi
              
          else
          
            # It is a reserved username, exiting
            clear
            echo "The username $selected_username is a reserved alias!" | tee -a $ERROR_LOG
            exit 0
            
          fi
          
        else
        
          # The username is invalid, exiting
          clear
          echo "The user $selected_username already exists!" | tee -a $ERROR_LOG
          exit 0
          
        fi
        
      else
  
        # Creating the subdomain / addon domain
        
        # Prepping variables
        target_account=$(grep -wf $DIR/out.tmp $DIR/accountlist.txt | awk '{print $2}')
        
        main_domain=$(uapi --user=$target_account Variables get_user_information | grep domain: | awk -F ": " '{print $2}')
        
        vhost_domain="$target_domain.$main_domain"
        
        echo -e "\nTarget domain: $target_domain\nTarget account: $target_account\nTarget main domain: $main_domain\nTarget vhost domain: $vhost_domain\n\n" >> $LOG
        
        ### Creating the subdomain
        uapi --user="$target_account" SubDomain addsubdomain domain="$target_domain" rootdomain="$main_domain" 2>> $ERROR_LOG 1>> $LOG
        
        ### Creating the addon domain (if possible)
        whmapi1 create_parked_domain_for_user domain="$target_domain" username="$target_account" web_vhost_domain="$target_domain.$main_domain" 2>> $ERROR_LOG 1>> $LOG
  
      fi
      
    else 
      
      # The domain DOES exist on the server, EXITING
      clear
      echo "The domain already exists on the server!" | tee -a $ERROR_LOG
      exit 0
      
    fi
    
  else
  
    # The domain name is NOT valid, exiting
    clear
    echo "$target_domain is NOT a valid domain name!" | tee -a $ERROR_LOG
    exit 0
    
  fi

  #target_domain=$(grep -wf $DIR/out.tmp $DIR/domainlist.txt | awk '{print $2}')
  #target_account=$(egrep "^$target_domain:" /etc/userdatadomains | awk -F " |==" '{print $2}')
  
fi

# Remove the selected domain from the list 
sed -i "/^$(cat $DIR/out.tmp) /d" $OPTIONS_FILE

clear

get_deets



























