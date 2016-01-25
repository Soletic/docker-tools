#!/bin/bash

BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
if [ -z "${DOCKER_HOSTING}" ]; then
    >&2 echo 'ENV var $DOCKER_HOSTING does not exist'
    exit 1
fi

# Default value
JSON_DOCKER_WEBVPS="{\"webvps\": [], \"src\": \"$DOCKER_HOSTING/webvps\"}"
JSON_DOCKER_PATH=$BASEDIR/webvps.json

# Test if config file exist and load
if [[ -f $BASEDIR/.envwebvps ]]; then
	echo "Load .envwebvps"
	. $BASEDIR/.envwebvps
fi

if [[ -f $JSON_DOCKER_PATH ]]; then
	JSON_DOCKER_WEBVPS=$(cat $JSON_DOCKER_PATH)
fi

HOSTING_SRC=$(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".src")

source $BASEDIR/templates/lib

case "$1" in
	new)
		# Usage : new --name|-n soletic --host|-h soletic.org --host-alias <domaine list comma seperated> --diskquota|-dq 2000000 --id|-id 1 -s|--service phpserver -email <email>
		while [[ $# > 1 ]] 
		do
			key="$1"
			case $key in
				-n|--name)
					WEBVPS_NAME="$2"
					shift # past argument
					;;
				-h|--host)
					WEBVPS_HOST="$2"
					WEBVPS_HOST_ALIAS="www.$2"
					shift # past argument
					;;
				-dq|--diskquota)
					WEBVPS_DISK_QUOTA="$2"
					shift # past argument
					;;
				-id|--id)
					WEBVPS_ID="$2"
					shift # past argument
					;;
				-s|--service)
					WEBVPS_TYPE="$2"
					shift # past argument
					;;
				-email)
					WEBVPS_EMAIL="$2"
					shift # past argument
					;;
				--host-alias)
					WEBVPS_HOST_ALIAS="$2"
					shift # past argument
					;;
				*)
					# unknown option
					shift
					;;
			esac
		done
		# Check var and requirements
		if [ -z "$WEBVPS_NAME" ]; then
			>&2 echo "[new webvps] name missing"
			exit 1
		fi
		if [ -z "$WEBVPS_EMAIL" ]; then
			>&2 echo "[new webvps] email of client missing"
			exit 1
		fi
		if [ -z "$WEBVPS_HOST" ]; then
			>&2 echo "[new webvps] host missing"
			exit 1
		fi
		if [ -z "$WEBVPS_DISK_QUOTA" ]; then
			echo "[info] Default disk quota used : 2G"
			WEBVPS_DISK_QUOTA=2000000
		fi
		if [ -z "$WEBVPS_TYPE" ]; then
			>&2 echo "[new webvps] service missing"
			exit 1
		fi
		if [ ! -d $BASEDIR/templates/$WEBVPS_TYPE ]; then
			>&2 echo "Service template $WEBVPS_TYPE doesn't exist"
			exit 1
		fi

		# Check if webvps name already exist
		is_exist=$(_webvps_is_webvps_exist_by_property "name" "$WEBVPS_NAME")
		if [ "$is_exist" = true ]; then
			>&2 echo "Webvps $WEBVPS_NAME already exists in $JSON_DOCKER_PATH"
			exit 1
		fi
		if [ -d $HOSTING_SRC/$WEBVPS_NAME ]; then
			>&2 echo "Webvps $WEBVPS_NAME already exists in filesystem : $HOSTING_SRC/$WEBVPS_NAME. Please remove first."
			exit 1
		fi

		### Get webvps id
		if [ -z "$WEBVPS_ID" ]; then
			idsearch=1
			while [ true ]; do
				is_uid_exist=$(_webvps_is_webvps_exist_by_property "uid" "$idsearch")
				if [ "$is_uid_exist" = true ]; then
					idsearch=$[$idsearch+1]
				else
					WEBVPS_ID=$idsearch
					break
				fi
			done
		fi
		is_uid_exist=$(_webvps_is_webvps_exist_by_property "uid" "$WEBVPS_ID")
		if [ "$is_uid_exist" = true ]; then
			>&2 echo "User uid $WEBVPS_ID already exist"
			exit 1
		fi
		echo "[info] uid used : $WEBVPS_ID"

		# Set env for the webvps
		platform=$(uname)
		if [ "$platform" = "Darwin" ]; then # MacOSX, use current id user because it's impossible with docker-machine to harmonize user id
			WEBVPS_WORKER_UID=1000 # $(id -u)
		else
			WEBVPS_WORKER_UID=$(($WEBVPS_ID+10000))
		fi
		WEBVPS_PORT_HTTP=$(($WEBVPS_ID+200))"80"
		WEBVPS_PORT_HTTPS=$(($WEBVPS_ID+200))"43"
		WEBVPS_PORT_SSH=$(($WEBVPS_ID+200))"22"
		WEBVPS_PORT_MYSQL=$(($WEBVPS_ID+200))"36"
		WEBVPS_PORT_MONGO=$(($WEBVPS_ID+200))"17"

		# Set domain list
		if [ "$WEBVPS_HOST_ALIAS" = "no" ]; then
			WEBVPS_HOST_ALIAS=""
			WEBVPS_PROXY_HOSTS=$WEBVPS_HOST
		else
			WEBVPS_PROXY_HOSTS="$WEBVPS_HOST,$WEBVPS_HOST_ALIAS"
		fi
		
		echo "$WEBVPS_NAME setup"

		# Create dir
		mkdir -p $HOSTING_SRC/$WEBVPS_NAME

		# Create an env file
		cat > $HOSTING_SRC/$WEBVPS_NAME/webvps.env <<-EOF
				#!/bin/bash
				export WEBVPS_NAME=$WEBVPS_NAME
				export WEBVPS_HOST=$WEBVPS_HOST
				export WEBVPS_HOST_ALIAS=$WEBVPS_HOST_ALIAS
				export WEBVPS_PROXY_HOSTS=$WEBVPS_PROXY_HOSTS
				export WEBVPS_ID=$WEBVPS_ID
				export WEBVPS_WORKER_UID=$WEBVPS_WORKER_UID
				export WEBVPS_PORT_HTTP=$WEBVPS_PORT_HTTP
				export WEBVPS_PORT_HTTPS=$WEBVPS_PORT_HTTPS
				export WEBVPS_PORT_SSH=$WEBVPS_PORT_SSH
				export WEBVPS_PORT_MYSQL=$WEBVPS_PORT_MYSQL
				export WEBVPS_PORT_MONGO=$WEBVPS_PORT_MONGO
				export WEBVPS_TYPE=$WEBVPS_TYPE
				export WEBVPS_EMAIL=$WEBVPS_EMAIL
			EOF

		####
		# Load vps type plugin
		####
		source $BASEDIR/templates/$WEBVPS_TYPE/settings

		####
		# Docker compose init
		####
		ln -s $BASEDIR/templates/base.yml $HOSTING_SRC/$WEBVPS_NAME/base.yml
		cp $BASEDIR/templates/$WEBVPS_TYPE/$WEBVPS_TYPE-docker-compose.yml $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
		
		# Limit resources
		cpu_shares=128 # If overload, max 12.5% of CPU (fair rule)
		platform=$(uname)
		if [ "$platform" != "Darwin" ]; then
			cpu_total=$(_webvps_get_cpu_total)
			cpuset=$(expr $WEBVPS_ID % $cpu_total)
			mem_limit=1g
			sed -ri -e "s/%.+_cpuset%/$cpuset/" \
				-e "s/%.+_cpu_shares%/$cpu_shares/" \
				-e "s/%.+_memlimit%/$mem_limit/" $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
		else
			# MacOSX 
			if [ "$platform" = "Darwin" ]; then
				sed -E -i '' "/.+cpu.+[%\"]$/d"  $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
				sed -E -i '' "/.+mem.+[%\"]$/d"  $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
			fi
		fi

		####
		# Register VPS
		####
		echo $JSON_DOCKER_WEBVPS | jq ".webvps |= .+ [{\"name\": \"$WEBVPS_NAME\", \"host\": \"$WEBVPS_HOST\", \"host_alias\": \"$WEBVPS_HOST_ALIAS\", \"uid\": $WEBVPS_ID, \"diskquota\": $WEBVPS_DISK_QUOTA, \"email\": \"${WEBVPS_EMAIL}\" }]" > $JSON_DOCKER_PATH

		####
		# Setup service and refresh
		####
		_${WEBVPS_TYPE}_setup $WEBVPS_NAME
		_${WEBVPS_TYPE}_refresh $WEBVPS_NAME

		echo " > Created ! Now execute : webvps.sh up $WEBVPS_NAME"
		;;
	service-register)
		# Dev in porgress
		;;
	refresh)
		# Refresh informations and setting for all webvps. Useful to fix problems
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			if [ ! -z "$2" ] && [ "$2" != "$webvps" ]; then
				continue
			fi
			_webvps_refresh $webvps
		done
		;;
	delete)
		if [ -z $2 ]; then
			>&2 echo "Delete command requires the webvps name"
			exit
		fi
		webvps=$2
		for webvps_loop in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			if [ "$webvps_loop" = "$webvps" ]; then
				source $HOSTING_SRC/$webvps/webvps.env
				source $BASEDIR/templates/$WEBVPS_TYPE/settings

				# Call hook remove for service
				echo "_${WEBVPS_TYPE}_remove ${webvps}"
				_${WEBVPS_TYPE}_remove "${webvps}"

				cd $HOSTING_SRC/$webvps;
				echo "Docker stoping and removing containers"
				docker-compose stop
				docker-compose rm -f

				echo "Remove files : $HOSTING_SRC/$webvps"
				rm -Rf $HOSTING_SRC/$webvps

				echo "Unregistering vps $webvps"
				echo $JSON_DOCKER_WEBVPS | jq "del(.webvps[$i])" > $JSON_DOCKER_PATH
				echo "$webvps remove. If images have been built by docker-compose, you have to remove it manualy"
				exit
			fi 
			((i+=1))
		done
		>&2 echo "$webvps not found"
		;;
	up|rm|start|stop|recreate)
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			if [ ! -z "$2" ] && [ "$2" != "$webvps" ]; then
				continue
			fi
			echo "Webvps $webvps"
			echo "=============="
			. $HOSTING_SRC/$webvps/webvps.env
			cd $HOSTING_SRC/$webvps;
			source $BASEDIR/templates/$WEBVPS_TYPE/settings
			if [ "$1" = "up" ]; then
				docker-compose up -d

				# Call hook after_start for service
				echo "_${WEBVPS_TYPE}_after_start ${webvps}"
				_${WEBVPS_TYPE}_after_start "${webvps}"
			elif [ "$1" = "recreate" ]; then
				docker-compose stop
				docker-compose rm -f
				docker-compose build --no-cache 
				docker-compose up -d --force-recreate
				_webvps_refresh $webvps

				# Call hook after_start for service
				echo "_${WEBVPS_TYPE}_up ${webvps}"
				_${WEBVPS_TYPE}_after_start "${webvps}"
			else
				docker-compose $1
				if [ "$1" = "start" ]; then
					# Call hook after_start for service
					echo "_${WEBVPS_TYPE}_up ${webvps}"
					_${WEBVPS_TYPE}_after_start "${webvps}"
				fi
			fi
		done
		;;
	list)
		declare -a tablines
		declare -a colsizes
		declare -a colname=("uid" "name" "host" "host_alias" "diskquota" "email")
		declare -a collabels=( 'UID' 'Name' 'Host' 'Alias' 'Disk space quota' 'Email contact' )
		for (( i = 0; i < ${#collabels[@]}; i++ )); do
			colsizes[i]=${#collabels[$i]}
		done
		webvps_total=$(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps | length')
		for (( i = 0; i < $webvps_total; i++ )); do
			for (( j = 0; j < ${#colname[@]}; j++ )); do
				jsonkey=${colname[$j]}
				value=$(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".webvps[$i] | .$jsonkey")
				if [ ${#value} -gt ${colsizes[$j]} ]; then
					colsizes[$j]=${#value}
				fi
			done
		done
		# Print
		for (( i = 0; i < ${#collabels[@]}; i++ )); do
			printf "${collabels[$i]}"
			printf "%"$(expr ${colsizes[$i]} - ${#collabels[$i]} + 4)"s" ""
		done
		echo ""
		for (( vps_i = 0; vps_i < $webvps_total; vps_i++ )); do
			for (( i = 0; i < ${#collabels[@]}; i++ )); do
				jsonkey=${colname[$i]}
				value=$(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".webvps[$vps_i] | .$jsonkey")
				printf "$value"
				printf "%"$(expr ${colsizes[$i]} - ${#value} + 4)"s" ""
			done
			echo ""
		done
		;;
	info)
		if [ -z "$2" ]; then
			>&2 echo "Command usage : $0 info <webvps>"
			exit 1
		fi
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			if [ "$2" != "$webvps" ]; then
				continue
			fi
			echo "Information for $webvps"
			echo "======================="
			container_list=
			# Env
			echo "## Environment"
			. $HOSTING_SRC/$webvps/webvps.env
			cat $HOSTING_SRC/$webvps/webvps.env
						
			# credentials
			source $BASEDIR/templates/$WEBVPS_TYPE/settings
			_${WEBVPS_TYPE}_print_credentials "${webvps}"
		done
		;;
	*)
		>&2 echo "Command $1 not found. Usage : webvps.sh <command> <options>"
		exit 1
esac

