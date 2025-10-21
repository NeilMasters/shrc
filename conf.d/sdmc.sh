#!/bin/bash

###############################################################################
#
# The small script will handle strongdm login, connection handling and client 
# opening for you.
#
# requirements:
# brew install jq jc dialog awk
# sdm cli ~ sdm desktop -> click your profile picture -> actions -> 
# install sdm in PATH
#
# usage:
# $ sdmc (connect|request)
#
###############################################################################

CMD=$1

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
	CONNECTION="${1}"
	sdm listen "${CONNECTION}" 2>&1 >/dev/null &
	sdm connect "${CONNECTION}" 2>&1 >/dev/null

	sleep 1
}

function getConnected() {
	sdm status | jc --asciitable | jq -r '.[] | select( .status == "connected")' | jq -r '.address'
}

function getApprovedResource() {
	sdm status | jc --asciitable | jq -r ".[] | select( .datasource == \"${1}\")" | jq -r '.address'
}

function connectAndLaunch() {
	connect "${1}"
	CONNECTED=$(getConnected)

	if [[ $CONNECTED == "" ]];
	then
		error "We could not connect you or you made an invalid choice."
		error "exiting..."
		exit 0
	fi

	# Launch
	launchClient "${CONNECTED}"
}

# Check for dependencies
declare -a DEPENDENCIES=("jq" "jc" "sdm" "awk" "dialog")

MISSING_DEPS=false
for DEPENDENCY in "${DEPENDENCIES[@]}"
do
	HAS_DEP=$(which "${DEPENDENCY}")

	if [[ $HAS_DEP == "" ]];
	then
		MISSING_DEPS=true
		error "You are missing the ${DEPENDENCY}."
		error "brew install ${DEPENDENCY}"
	fi
done

if [[ $MISSING_DEPS = true ]];
then
	error "exiting..."
	exit 1
fi

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

disconnect

if [[ $CMD == "" || $CMD == "connect" ]];
then
	# Always disconnect to remove the possibility of accidentally connecting to the
	# wrong resource. Should in theory be impossible as its based on port
	# assigning.
	ok "Select from the list below to connect or CTRL+C to exit"

	declare -a CONNECTIONS=$(sdm status | jc --asciitable | jq -r '.[].datasource')

	select CONNECTION in $CONNECTIONS
	do
		connect "${CONNECTION}"
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
fi

if [[ $CMD == "request" ]];
then
	if [ ! -f ~/.sdmresources ]; then
    	error "~/.sdmresources not found"
    	error ""
    	ok "Do you want us to create a basic file for you to edit? (N/y)"

    	read CREATE_FILE

    	if [[ $CREATE_FILE == "y" ]];
    	then
    		echo 'declare -a SDM_RESOURCES=(' >> ~/.sdmresources
    		echo '"Easy to read name 1" "id-1-from-strongdm"' >> ~/.sdmresources
    		echo '"Easy to read name 2" "id-2-from-strongdm"' >> ~/.sdmresources
    		echo ')' >> ~/.sdmresources
    		
    		ok "We have created the file, this process will now exit so you can edit the file."
    		ok "exiting..."
    		exit 0
    	fi

    	ok "We did not create the file for you, to use the request process this"
    	ok "file needs to exist and be populated with your commonly used clusters"
    	ok "exiting..."
    	exit 0
	fi

	source ~/.sdmresources

	RESOURCE_CHOICE=$(dialog --clear \
        	--title "Choose a resource to make a request" \
            --menu "Choose one of the following resources:" \
            400 200 4 \
            "${SDM_RESOURCES[@]}" 2>&1 >/dev/tty)


	RESOURCE_CHOICE_ID=""
	for RESOURCE_INDEX in "${!SDM_RESOURCES[@]}"
	do
		if [[ ${SDM_RESOURCES[$RESOURCE_INDEX]} == $RESOURCE_CHOICE ]];
		then
			RESOURCE_CHOICE_ID="${SDM_RESOURCES[$RESOURCE_INDEX+1]}"
			break
		fi
	done

	clear

	if [[ $RESOURCE_CHOICE_ID == "" ]];
	then
		ok "You cancelled or made an invalid selection"
		ok "exiting..."
		exit 0
	fi

	ok "Please enter a reason for this access."
	read REASON

	declare -a TIMES=(
		"15 Minutes" "15m" 
		"30 Minutes" "30m" 
		"1 Hour" "1h" 
		"2 Hours" "2h"
		"4 Hours" "4h")

	TIME_CHOICE=$(dialog --clear \
        	--title "Choose a length of time" \
            --menu "Choose a length of time for this request:" \
            400 200 4 \
            "${TIMES[@]}" 2>&1 >/dev/tty)


	TIME_CHOICE_ID=""
	for TIME_INDEX in "${!TIMES[@]}"
	do
		if [[ ${TIMES[$TIME_INDEX]} == $TIME_CHOICE ]];
		then
			TIME_CHOICE_ID="${TIMES[$TIME_INDEX+1]}"
			break
		fi
	done

	clear

	if [[ $RESOURCE_CHOICE_ID != "" ]];
	then
		ACCESS_REQUEST_ID=$(sdm access to "${RESOURCE_CHOICE_ID}" \
			--timeout "30s" \
			--reason "${REASON}" \
			--duration "${TIME_CHOICE_ID}")

		ok "I will now wait for that approval for a max of 15 seconds in case"
		ok "the request is auto approved..."

		x=1
		while [ $x -le 15 ]
		do
		  echo "Checking for approval to ${RESOURCE_CHOICE_ID}"
		  IS_APPROVED=$(getApprovedResource "${RESOURCE_CHOICE_ID}")

		  if [[ $IS_APPROVED != "" ]];
		  then
		  	connectAndLaunch "${RESOURCE_CHOICE_ID}"

		  	exit 0
		  fi
		  sleep 1

		  x=$(( $x + 1 ))
		done

		ok "Your request was not auto approved."
		ok 
		ok "Your access request has been sent, you will receive a notification"
		ok "soon when it is approved. Re-running 'sdmc connect' command will show"
		ok "that connection once it has been approved."
	fi
fi