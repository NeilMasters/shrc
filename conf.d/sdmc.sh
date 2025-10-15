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


function error() {
	echo -e "\033[0;31mERROR: $1\033[0m"
}

function ok() {
	echo -e "\033[0;32m$1\033[0m"
}

function launchClient() {
	ok "Launching your client to open ${1}"
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
			ok "Shutting down active listen pid ${ACTIVE_LISTEN}"
			kill -9 "${ACTIVE_LISTEN}"
		done
	fi

	sdm disconnect -all >> /dev/null 2>&1
}

function connect() {
	sdm listen "${CONNECTION}" &
	sdm connect "${CONNECTION}"
}

function getConnected() {
	sdm status | jc --asciitable | jq -r '.[] | select( .status == "connected")' | jq -r '.address'
}

# Check for dependencies
declare -a DEPENDENCIES=("jq" "jc" "sdm" "awk")

for DEPENDENCY in "${DEPENDENCIES[@]}"
do
	HAS_DEP=$(which "${DEPENDENCY}")

	if [[ $HAS_DEP == "" ]];
	then
		error "You are missing the ${DEPENDENCY}."
		error "brew install ${DEPENDENCY}"
		error "exiting..."
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
		error "You are not logged in and you have no SDM_EMAIL environmental variable set."
		error "Add SDM_EMAIL to your ~/.*rc file."
		error "exiting..."
		exit 0
	fi

    sdm login
fi

# Always disconnect to remove the possibility of accidentally connecting to the
# wrong resource. Should in theory be impossible as its based on port
# assigning.
ok "Disconnecting you from all resources"
disconnect

ok "You are not currently connected to anything. Select from the list below to connect"
ok "or CTRL+C to exit"

declare -a CONNECTIONS=$(sdm status | jc --asciitable | jq -r '.[].datasource')

select CONNECTION in $CONNECTIONS
do
	sdm connect "${CONNECTION}" >> /dev/null 2>&1
	CONNECTED=$(getConnected)
	break
done

if [[ $CONNECTED == "" ]];
then
	error "We could not connect you or you made an invalid choice."
	error "exiting..."
	exit 0
fi

# Launch
launchClient "${CONNECTED}"