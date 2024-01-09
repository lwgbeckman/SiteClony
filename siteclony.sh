#!/bin/bash
# gbeckman@liquidweb.com
# https://github.com/lwgbeckman/SiteClony

# Version info (Jan 5th 2024)
version="2.3.4"

##########
# Colors #
##########

RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
ENDCOLOR="\e[0m"


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


##################
# Check for root #
##################

if [ ! "$(whoami)" = "root" ]
then
  echo -e "\n${RED}[ERROR]${ENDCOLOR} The script needs to run as root!\n"
  exit 1
fi

####################
# Check for screen #
####################

if [ ! "${STY}" ]
then
  echo -e "${YELLOW}[WARNING]${ENDCOLOR} Not running in a screen! Restarting in a screen session."
  # Check if screen is installed, if it's not try to install it
  if [ ! $(which screen 2> /dev/null) ]
  then
    echo -e "[INFO] screen isn't installed. Trying to install it."
    yum install screen -y -q

    # Checking again to make sure it was installed, if it wasn't, exit.
    if [ ! $(which screen 2> /dev/null) ]
    then
      echo -e "${RED}[ERROR]${ENDCOLOR} Couldn't install screen!\nExiting..."
      exit 1
    fi
  fi
  # Restart the script in a screen
  screen -S siteclony bash -c "sh siteclony.sh; bash"
  exit 0
fi

# We should be in a screen at this point

##################################
# Working dir and log file setup #
##################################

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


###########################
# Set up all dependencies #
###########################
INCLUDES_PATH="/root/includes.siteclony"
INCLUDES_URL="https://raw.githubusercontent.com/lwgbeckman/SiteClony/main/includes.siteclony"

# Download the required files if they don't already exist
if [ ! -d $INCLUDES_PATH ]
then
  echo -e "${YELLOW}[WARNING]${ENDCOLOR} Didn't find the required includes in $INCLUDES_PATH.\nDownloading them from $INCLUDES_URL" | tee -a $LOG

  # Creating the directory
  mkdir $INCLUDES_PATH

  # Downloading the files
  # Required files first (exit if we can't download them)
  for file in functions.sh variables.sh
  do
    wget -q $INCLUDES_URL/$file -P $INCLUDES_PATH
    if [ $? -ne 0 ]
    then 
      echo -e "${RED}[ERROR]${ENDCOLOR} Something went wrong! Couldn't download $file!\nExiting..." | tee -a $ERROR_LOG
      exit 1
    fi
    chmod +x $INCLUDES_PATH/$file
  done

  # Optional files, not exiting, but some things might not look correct
  for file in logo.txt dialog.conf
  do
    wget -q $INCLUDES_URL/$file -P $INCLUDES_PATH
    if [ $? -ne 0 ]
    then 
      echo -e "${YELLOW}[WARNING]${ENDCOLOR} Couldn't download ${RED}$file${ENDCOLOR}! Some things might not look correct, but the script will still work." | tee -a $ERROR_LOG
    fi
  done
fi

################################################################################################
### DEV MODE ONLY                                                                             ##
### Using the dev directory in /home/SiteClony/includes.siteclony while working on the script ##
################################################################################################
#INCLUDES_PATH=/home/SiteClony/includes.siteclony

# Include the scripts from /root/includes.siteclony
for script in $INCLUDES_PATH/*.sh
do
  source $script
done

# Catch SIGINT (Ctrl+C) and execute the 'quit' function 
trap quit INT

# Load the dialog config file
DIALOGRC=$INCLUDES_PATH/dialog.conf


########
# Main #
########

# Get the number of domains on the server
max_domains=$(whmapi1 get_domain_info | grep " domain:" | wc -l)

# Select the source domain
echo -e "Selecting the SOURCE domain\n" >> $DOMAIN_SELECTION_LOG
getDomainOptions
sourceDomainSelection

# Select the target domain
echo -e "\nSelecting the TARGET domain\n" >> $DOMAIN_SELECTION_LOG
getDomainOptions
# Remove the source domain from the list
sed -i "/ $source_domain /d" $OPTIONS_FILE
targetDomainSelection


# Check if the "Add New Domain" option was selected
id=$(cat $DIR/out.tmp)

if [ $id -eq 0 ]
then

  # Ask for the new domain name
  dialog --backtitle "Choose a name for the new domain" --inputbox "Choose a name for the new domain " 8 60 2> $DIR/out.tmp
  
  #Check if the domain name is valid
  target_domain=$(cat $DIR/out.tmp)
  if ! checkDomain $target_domain
  then
    # Domain name is NOT valid
    clear
    echo -e "${RED}[ERROR]${ENDCOLOR} $target_domain is not a valid domain name!\nExiting..." 
    exit 1
  fi
  # Domain name IS valid

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
    
    # Trying to create a new account
    
    # Asking for the new account info
    random_pass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-24})
    suggested_username=$(awk -F. '{print $1}' <<< $target_domain)
    
    # dialog --backtitle "Provide the information for the new account" --title "Create a new account" --form "New account information" 15 50 3 "Username:" 1 3 "$suggested_username" 1 15 25 25 "Password:" 3 3 "$random_pass" 3 15 25 25 2> $DIR/out.tmp

    dialog --backtitle "Provide the information for the new account" --title "Create a new account" --form "New account information" 15 50 3 \
    "Username:" 1 3 "$suggested_username" 1 15 25 25 \
    "Password:" 3 3 "$random_pass" 3 15 25 25 \
    2> $DIR/out.tmp

    # Checking if the username is valid
    selected_username=$(head -1 $DIR/out.tmp)
    if ! checkUsername $selected_username
    then
      # The username is not valid
      clear
      echo -e "${RED}[ERROR]${ENDCOLOR} The selected Username is invalid!\nExiting..."
      exit 1
    fi
    # The username is valid

    # Checking if the password is valid
    selected_password=$(tail -1 $DIR/out.tmp)
    if ! checkPass $selected_password
    then 
      #The password is too weak
      clear
      echo -e "${RED}[ERROR]${ENDCOLOR} The selected password is invalid!\nExiting..."
      exit 1
    fi
    # The password is valid

    # Create the account with the selected information
    if ! createAcc $selected_username $target_domain $selected_password
    then
        # Couldn't create the account, bailing out
        echo "Exiting..."
        exit 1
    fi

    # Created the account without errors ( hopefully )
    echo -e "${GREEN}Account created!${ENDCOLOR}\n${YELLOW}Username:${ENDCOLOR} $selected_username\n${YELLOW}Domain:${ENDCOLOR} $target_domain\n${YELLOW}Password:${ENDCOLOR} $selected_password\n\n" > $LOG

    if ! getTargetInfo $target_domain
    then
      # Something went wrong, most likely couldn't find the docroot for some reason
      clear
      echo -e "${RED}[ERROR]${ENDCOLOR} Something went wrong! Most likely couldn't find the docroot. (${RED}cat $ERROR_LOG${ENDCOLOR})\nExiting..."
      exit 1
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

fi

# Remove the selected domain from the list 
sed -i "/^$(cat $DIR/out.tmp) /d" $OPTIONS_FILE


# TODO: Make the deets editable 
# NOTE: Need to do more error checking afterwards...
#
# dialog --backtitle "Deets review" --title "Gathered information" --form "Do you want to proceed with this information? (<TAB> to jump to OK/Cancel)" 25 100 17 \
# "Source Domain:" 1 3 "$source_domain" 1 25 100 50 \
# "Source Account:" 2 3 "$source_account" 2 25 100 50 \
# "Source Docroot:" 3 3 "$source_docroot" 3 25 100 50 \
# "DB name:" 5 3 "$source_DB_name" 5 25 100 50 \
# "DB user:" 6 3 "$source_DB_user" 6 25 100 50 \
# "DB pass:" 7 3 "$source_DB_pass" 7 25 100 50 \
# 2> $DIR/out.tmp


# Present the deets and ask to continue or cancel
if ! dialog --colors --yesno "Do you want to start the site clone with this configuration?\n\n\n\Zb\Z1SOURCE\Zn\n\n\Z4Server:\Zn  $source_server\n\Z4Domain:\Zn  $source_domain\n\Z4Account:\Zn $source_account\n\Z4Docroot:\Zn $source_docroot\n\n\Z4DB name:\Zn $source_DB_name\n\Z4DB user:\Zn $source_DB_user\n\Z4DB pass:\Zn $source_DB_pass\n\n\Zb\Z2TARGET\Zn\n\n\Z4Server:\Zn  $target_server\n\Z4Domain:\Zn  $target_domain\n\Z4Account:\Zn $target_account\n\Z4Docroot:\Zn $target_docroot\n\n\Z4DB name:\Zn $target_DB_name\n\Z4DB user:\Zn $target_DB_user\n\Z4DB pass:\Zn $target_DB_pass" 30 75
then
  clear
  echo "Bye!"
  exit 1
fi

clear
echo -e "\n${BLUE}Copy the deets and paste them in your ticket!${ENDCOLOR}\n"
getDeets
echo -e "${GREEN}Press any key to continue...${ENDCOLOR}"
read -p ""

echo "Starting the clone"


























