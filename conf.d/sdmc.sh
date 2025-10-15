#!/bin/bash

###############################################################################
#
# The small script will handle strongdm login, connection handling and client 
# opening for you.
#
# Coming soon:
# automated requests
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
	message "OK: Launching your client to open ${1}"
	open "mysql://${1}"
}

function disconnect() {
	# disconnect() will disconnect you for any active connections and shutdown
	# any active listening port forwards.
	ACTIVE_LISTENS=$(ps -A | grep "[s]dm listen" | awk '{print $1}')

	if [[ $ACTIVE_LISTEN != "" ]];
	then
		for ACTIVE_LISTEN in "${ACTIVE_LISTENS[@]}"
		do
			echo "OK: Shutting down active listen pid ${ACTIVE_LISTEN}"
			kill -9 "${ACTIVE_LISTEN}"
		done
	fi

	sdm disconnect -all
}

function connect() {
	sdm listen "${CONNECTION}" &
	sdm connect "${CONNECTION}"
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
		message "ERROR: You are not logged in and you have no SDM_EMAIL environmental variable set."
		message "ERROR: Add SDM_EMAIL to your ~/.*rc file."
		exit 0
	fi

    sdm login
fi

disconnect

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