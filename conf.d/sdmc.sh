#!/bin/bash

###############################################################################
#
# The small script will handle strongdm login, connection handling and client 
# opening for you.
#
# If you are a frequent database user and jump around a lot of clusters this
# application might be helpful and speed you up.
#
# If you do make frequent use of it do yourself a favour and set SDM_EMAIL in
# your rc file.
#
# requirements:
# jq ~ brew install jq
# jc ~ brew install jc
# sdm cli ~ sdm desktop -> click your profile picture -> actions -> 
# install sdm in PATH
#
# usage:
# $ sdmc
#
###############################################################################

function message() {
	echo "${1}"
}

function launchClient() {
	message "Launching your client to open ${1}"
	open "mysql://${1}"
}

function getConnected() {
	sdm status | jc --asciitable | jq -r '.[] | select( .status == "connected")' | jq -r '.address'
}

# Check for dependencies
declare -a DEPENDENCIES=("jq" "jc" "sdm")

for DEPENDENCY in "${DEPENDENCIES[@]}"
do
	HAS_DEP=$(which "${DEPENDENCY}")

	if [[ $HAS_DEP == "" ]];
	then
		message "You are missing the ${DEPENDENCY}, exiting..."
		exit 1
	fi
done

# Is the user logged in?
# The 'no' is caught from stderr oddly.
SDM_STATUS_RESPONSE=$(sdm status 2>&1 >/dev/null)

if [[ $SDM_STATUS_RESPONSE == 'You are not authenticated. Please login again.' ]]; 
then
	if [[ $SDM_EMAIL == "" ]];
	then
		message "You are not logged in and you have no SDM_EMAIL environmental variable set."
		message "Open the sdm desktop application and login or set SDM_EMAIL as an environmental variable."	
		exit 0
	fi

    sdm login
fi

# Get any existing connections
CONNECTED=$(getConnected)

# If there is none get the list and offer up choices.
if [[ $CONNECTED == "" ]];
then
	message "You are not currently connected to anything. Select from the list below to connect."

	declare -a CONNECTIONS=$(sdm status | jc --asciitable | jq -r '.[].datasource')

	select CONNECTION in $CONNECTIONS
	do
		sdm connect "${CONNECTION}"
		CONNECTED=$(getConnected)
		break
	done
fi

# Launch
launchClient "${CONNECTED}"