#!/bin/bash

version="1.4"
author="George Beckman"

#######################################################################################
# Colors                                                                              #
#######################################################################################

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
ENDCOLOR="\e[0m"

#######################################################################################
# Version                                                                             #
#######################################################################################
Version()
{
  echo -e "\tcPanel WP site clone script"
  echo -e "\tCreated by ${YELLOW}$author${ENDCOLOR}"
  echo -e "\tVersion: ${GREEN}$version${ENDCOLOR}\n"

}


echo  ""

#######################################################################################
# Help									              #
#######################################################################################
Help()
{
   # Display Help
   echo "This is a simple site clone script for WordPress websites on a server with cPanel"
   echo
   echo -e "${YELLOW}Syntax: sh site_clone.sh [-d|f|h|v|V] [source_domain.tld] [destination_domain.tld]${ENDCOLOR}"
   echo "options:"
   echo "d	Dry run. Doesn't make any changes."
   echo "f	Force. Ignores all errors unless it reaches a critical error."
   echo "h	Print this Help."
   echo "v	Verbose mode. Prints out aditional information during certain operations."
   echo "V	Print software version."
   echo
}

force=0

#######################################################################################
# cPanel API Error checking function					              #
#######################################################################################
uapi_error_check()
{
	old_IFS=$IFS
        if [ $(grep status tmp.log | awk '{print $2}') -eq 0 ]
        then
                errors=$(sed -n '/errors:/, /messages:/{ /errors:/! { /messages:/! p } }' tmp.log)
                export IFS="-"
                for i in $errors
                do
                        if [[ -n "${i// }" ]]
                        then
                                echo -e "${RED}[ERROR] $i ${ENDCOLOR}"
                        fi
                done
		if [ $force -eq 0 ]
		then
			echo -e "Do you want to proceed?"
			select yn in "Yes" "No"; do
				case $yn in
					Yes )
						echo -e "Proceeding."
						break;;
					No )
						IFS=$old_IFS
				       		exit;;	
		       		esac
	       		done
		fi
        else
                echo -e "${GREEN}[DONE]${ENDCOLOR} $1"
        fi
	IFS=$old_IFS
}

#######################################################################################
# Main Program  							              #
#######################################################################################

dry_run=0
verbose=0

#######################################################################################
# Process the input options. 							      #
#######################################################################################
# Get the options

while getopts ":dfhvV" option; do
   case $option in
	d) # Dry Run (don't clone anything)
	   dry_run=1	   
	   ;;
   	f) # Force (Ignore non critical errors)
	   force=1
	   ;;
	h) # Display Help
           Help
           exit;;
	v) # Print more information
	   verbose=1
	   ;;
	V) # Print script version
	   Version
   	   exit;;	   
       \?) # Invalid option
	   echo -e "${RED}[ERROR] Invalid option${ENDCOLOR}\n"
	   Help
	   exit;; 
   esac
done

shift $((OPTIND - 1))

source_domain=$(awk -F "==|:" '{print $1}' /etc/userdatadomains | grep "^$1$")
destination_domain=$(awk -F "==|:" '{print $1}' /etc/userdatadomains | egrep "^$2$")

source_user=$(awk -F "==|:" '{print $1, $2}' /etc/userdatadomains | egrep "^$source_domain" | awk '{print $2}')
destination_user=$(awk -F "==|:" '{print $1, $2}' /etc/userdatadomains | egrep "^$destination_domain" | awk '{print $2}')

echo ""

fail=0

if [ -z "$source_domain" ]
then
      echo -e "${RED}[ERROR] Source domain has to be a valid domain name${ENDCOLOR}"
      fail=1
fi

if [ -z "$destination_domain" ]
then
      echo -e "${RED}[ERROR] Destination domain has to be a valid domain name${ENDCOLOR}\n"
      fail=1
fi

if [ $fail -eq 1 ]
then
        Help
        exit 0
fi

source_docroot=$(awk -F "==|:" '{print $1, $6}' /etc/userdatadomains | egrep "^$source_domain " | cut -d " " -f 2)
destination_docroot=$(awk -F "==|:" '{print $1, $6}' /etc/userdatadomains | egrep "^$destination_domain " | cut -d " " -f 2)


if [ -z "$source_docroot" ]
then
      echo -e "${RED}[ERROR] Source document root doesn't exist${ENDCOLOR}\n"
      fail=1
fi

if [ -z "$destination_docroot" ]
then
      echo -e "${RED}[ERROR] Destination document root doesn't exist${ENDCOLOR}\n"
      fail=1
fi

source_config="$source_docroot/wp-config.php"

if [ ! -f "$source_config" ]
then
      echo -e "${RED}[ERROR] Source docroot is not a WordPress installation${ENDCOLOR}\n"
      fail=1
fi

if [ $fail -eq 1 ]
then
        exit 0
fi

echo -e "Source: ${GREEN}$source_domain${ENDCOLOR}"
echo -e "Source Docroot: ${YELLOW}$source_docroot${ENDCOLOR}\n"
echo -e "Destination: ${GREEN}$destination_domain${ENDCOLOR}"
echo -e "Destination Docroot: ${YELLOW}$destination_docroot${ENDCOLOR}\n"

echo -e "Starting the cloning process...\n"

if [ $dry_run -eq 1 ]
then

	echo -e "\n${YELLOW}This is a dry run, NO changes have been made${ENDCOLOR}\n"
	exit 0
fi

###########################################################################################################################

########################################### UAPI ##########################################################################

# Creating a new DB on destination
echo -e "${YELLOW}[INFO]${ENDCOLOR} Creating a new database on destination"
destination_db="$destination_user"_wp
if [ $verbose -eq 1 ]
then
	uapi --user=$destination_user Mysql create_database name=$destination_db | tee tmp.log
else
	uapi --user=$destination_user Mysql create_database name=$destination_db > tmp.log
fi

uapi_error_check "Database ${GREEN}$destination_db${ENDCOLOR} created!"

# Creating a new DB user on destination
echo -e "${YELLOW}[INFO]${ENDCOLOR} Creating a new user for the DB $destination_db"
destination_pass="McRaWHktp3BELCS"
if [ $verbose -eq 1 ]
    then
	uapi --user=$destination_user Mysql create_user name=$destination_db password=$destination_pass | tee tmp.log
else
	uapi --user=$destination_user Mysql create_user name=$destination_db password=$destination_pass > tmp.log
fi

uapi_error_check "User ${GREEN}$destination_db${ENDCOLOR} created!"

# Giving the detination user privilages on the destination DB
echo -e "${YELLOW}[INFO]${ENDCOLOR} Giving the user ${YELLOW}$destination_db${ENDCOLOR} ALL privileges on ${YELLOW}$destination_db${ENDCOLOR}"
if [ $verbose -eq 1 ]
    then
	uapi --user=$destination_user Mysql set_privileges_on_database user=$destination_db database=$destination_db privileges=ALL | tee tmp.log
else
	uapi --user=$destination_user Mysql set_privileges_on_database user=$destination_db database=$destination_db privileges=ALL > tmp.log
fi

uapi_error_check

###########################################################################################################################

################################### DB dump ###############################################################################

# Dumping the DB
echo -e "${YELLOW}[INFO]${ENDCOLOR} Dumping the source DB"
source_db=$(grep 'DB_NAME' $source_docroot/wp-config.php | cut -d "'" -f 4)
mysqldump "$source_db" > "/home/temp/$source_db.sql" 2> /tmp/sc_error

# Checking if the dump was successful
if [[ $? != 0 ]]
then
        err=$(</tmp/sc_error)
        echo -e "${RED}[ERROR] $err${ENDCOLOR}"
        rm -f /tmp/sc_error
	if [ $force -eq 0 ]
	then
		echo -e "Do you want to force the dump?"
        	select yn in "Yes" "No"; do
			case $yn in
				Yes )
					echo -e "Proceeding with force."
					mysqldump -f "$source_db" > "/home/temp/$source_db.sql" 2>/dev/null
                                	echo -e "${YELLOW}[WARNING]${ENDCOLOR} Database ${GREEN}$source_db${ENDCOLOR} dumped with ${RED}errors${ENDCOLOR}, some tables might be corrupt."
					break;;
                        	No )
                                	exit;;
                	esac
		done
	else
		echo -e "Proceeding with force."
                mysqldump -f "$source_db" > "/home/temp/$source_db.sql" 2>/dev/null
		echo -e "${YELLOW}[WARNING]${ENDCOLOR} Database ${GREEN}$source_db${ENDCOLOR} dumped with ${RED}errors${ENDCOLOR}, some tables might be corrupt."
	fi
else
        echo -e "${GREEN}[DONE]${ENDCOLOR} Database ${GREEN}$source_db${ENDCOLOR} dumped!"
fi


###########################################################################################################################

#################################### Docroot ##############################################################################

# Syncing docroots
echo -e "${YELLOW}[INFO]${ENDCOLOR} Syncing Docroots"

# Backing up the destination docroot
cp -rp $destination_docroot{,.bak}

# Syncing source docroot to destination docroot
if [ $verbose -eq 1 ]
then
	rsync -avhP "$source_docroot/" "$destination_docroot/"
else
	rsync -a "$source_docroot/" "$destination_docroot/"
fi

echo -e "${GREEN}[DONE]${ENDCOLOR}"

# Fixing permissions
echo -e "${YELLOW}[INFO]${ENDCOLOR} Changing ownership to ${YELLOW}$destination_user:$destination_user${ENDCOLOR}"
find $destination_docroot ! -user $destination_user -exec chown "$destination_user:$destination_user" {} \;
chgrp nobody $destination_docroot
echo -e "${GREEN}[DONE]${ENDCOLOR}"

###########################################################################################################################

################################## Database operations ####################################################################

# Changing the correct DB credentials in destination wp-config.php
echo -e "${YELLOW}[INFO]${ENDCOLOR} Setting the correct database name, user and password on destination wp-config.php"
destination_config="$destination_docroot/wp-config.php"

# DB NAME
sed -i "/DB_NAME/s/'[^']*'/'$destination_db'/2" $destination_config 

# DB USER
sed -i "/DB_USER/s/'[^']*'/'$destination_db'/2" $destination_config

# DB PASSWORD
sed -i "/DB_PASSWORD/s/'[^']*'/'$destination_pass'/2" $destination_config
echo -e "${GREEN}[DONE]${ENDCOLOR}"

# Importing the source DB dump to the destiantion DB
echo -e "${YELLOW}[INFO]${ENDCOLOR} Importing the source DB ${YELLOW}$source_db.sql${ENDCOLOR} into the destination DB ${YELLOW}$destination_db${ENDCOLOR}"
mysql $destination_db < "/home/temp/$source_db.sql" 
echo -e "${GREEN}[DONE]${ENDCOLOR}"

############################################################################################################################

###################################### Search & Replace ####################################################################

# Replacing all occurances of the source domain in the destination DB
echo -e "${YELLOW}[INFO]${ENDCOLOR} Replacing all occurances of the source domain ${YELLOW}$source_domain${ENDCOLOR} in the destination DB ${YELLOW}$destination_db${ENDCOLOR}"
if [ $verbose -eq 1 ]
    then
	wp search-replace "$source_domain" "$destination_domain" --path=$destination_docroot --allow-root 2> /tmp/sc_error
else
	wp search-replace "$source_domain" "$destination_domain" --path=$destination_docroot --allow-root 2> /tmp/sc_error 1> /dev/null
fi

if [[ $? != 0 ]]
then
        err=$(</tmp/sc_error)
        echo -e "${RED}[ERROR] $err${ENDCOLOR}"
else
        echo -e "${GREEN}[DONE]${ENDCOLOR}"
fi

# Replacing all occurances of the source domain in all destination docroot files recursively
#echo -e "${YELLOW}[INFO]${ENDCOLOR} Replacing all occurances of the source domain ${YELLOW}$source_domain${ENDCOLOR} in all destination docroot files recursively with the destination domain ${YELLOW}$destination_domain${ENDCOLOR}"
#find $destination_docroot -type f -exec sed -i "s/$source_domain/$destination_domain/g" {} \;
#echo -e "${GREEN}[DONE]${ENDCOLOR}"

echo -e "\nCloning of ${GREEN}$source_domain${ENDCOLOR} to ${GREEN}$destination_domain${ENDCOLOR} successfull!"

############################################################################################################################

#################################### Priming the undo script ###############################################################

# Setting the parameters in remove_last_clone.sh
#sed -i "s/source_db=.*/source_db=\"$source_db\"/" ./remove_last_clone.sh
#sed -i "s,destination_docroot=.*,destination_docroot=\"$destination_docroot\"," ./remove_last_clone.sh
#sed -i "s/destination_user=.*/destination_user=\"$destination_user\"/" ./remove_last_clone.sh
#sed -i "s/destination_db=.*/destination_db=\"$destination_db\"/" ./remove_last_clone.sh

#rm -f /tmp/sc_error
#rm -f ./tmp.log

echo  ""

















