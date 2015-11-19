#!/bin/bash

BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Default value
JSON_DOCKER_WEBVPS='{"webvps": [], "src": "/home/docker/hosting/src"}'
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

function _setquota {
	hash foo 2>/dev/null || { echo >&2 "No quota setup because setquota command missing in your system"; return; }
	case "$1" in
		add)
			setquota -u $2 $3 $3 1000000 1000000 -a
			;;
		remove)
			setquota -u $2 0 0 0 0 -a
			;;
		*)
			echo "invalid _setquota calling : _setquota add|remove <uid> <blockquota>"
			return
			;;
	esac
	echo "Quota for $2"
	repquota -a | grep ^#$2
}

case "$1" in
	new)
		# Usage : new --name|-n soletic --host|-h soletic.org --diskquota|-dq 2000000 --www-uid|-wid 10001
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
					shift # past argument
					;;
				-dq|--diskquota)
					WEBVPS_DISK_QUOTA="$2"
					shift # past argument
					;;
				-wid|--www-uid)
					WEBVPS_WWW_UID="$2"
					shift # past argument
					;;
				*)
					# unknown option
					shift
					;;
			esac
		done
		# Check var
		if [ -z "$WEBVPS_NAME" ]; then
			>&2 echo "[new webvps] name missing"
			exit 1
		fi
		if [ -z "$WEBVPS_HOST" ]; then
			>&2 echo "[new webvps] host missing"
			exit 1
		fi
		if [ -z "$WEBVPS_DISK_QUOTA" ]; then
			>&2 echo "[new webvps] diskquota missing"
			exit 1
		fi
		if [ -z "$WEBVPS_WWW_UID" ]; then
			>&2 echo "[new webvps] www uid missing"
			exit 1
		fi
		if [ -d $HOSTING_SRC/$WEBVPS_NAME ]; then
			>&2 echo "Webvps $WEBVPS_NAME already exists in filesystem : $HOSTING_SRC/$WEBVPS_NAME"
			exit 1
		fi
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			if [ $webvps = $WEBVPS_NAME ]; then
				>&2 echo "Webvps $WEBVPS_NAME already exists in $JSON_DOCKER_PATH"
				exit 1
			fi
		done
		# Init volumes
		mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/www/html
		cat > $HOSTING_SRC/$WEBVPS_NAME/volumes/www/html/index.html <<-EOF
				Welcome $WEBVPS_HOST
			EOF
		chown -R $WEBVPS_WWW_UID $HOSTING_SRC/$WEBVPS_NAME/volumes/www
		# Create an env file
		cat > $HOSTING_SRC/$WEBVPS_NAME/webvps.env <<-EOF
				#!/bin/bash
				export WEBVPS_NAME=$WEBVPS_NAME
				export WEBVPS_HOST=$WEBVPS_HOST
				export WEBVPS_UID_WWW=$WEBVPS_WWW_UID
			EOF
		# Set quota
		_setquota add $WEBVPS_WWW_UID $WEBVPS_DISK_QUOTA
		# Create docker-compose and image base
		mkdir $HOSTING_SRC/$WEBVPS_NAME/webvps
		cat > $HOSTING_SRC/$WEBVPS_NAME/webvps/Dockerfile <<-EOF
				FROM soletic/webvps:latest
				MAINTAINER Soletic Hosting <serveur@soletic.org>
			EOF
		ln -s $BASEDIR/templates/webvps/base.yml $HOSTING_SRC/$WEBVPS_NAME/base.yml
		cp $BASEDIR/templates/webvps/docker-compose.yml $HOSTING_SRC/$WEBVPS_NAME/
		# Add the new webvps in json file
		echo $JSON_DOCKER_WEBVPS | jq ".webvps |= .+ [{\"name\": \"$WEBVPS_NAME\", \"host\": \"$WEBVPS_HOST\", \"uid\": $WEBVPS_WWW_UID, \"diskquota\": $WEBVPS_DISK_QUOTA}]" > $JSON_DOCKER_PATH
		;;
	refresh)
		# Refresh informations and setting for all webvps. Useful to fix problems
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			. $HOSTING_SRC/$webvps/webvps.env
			chown -R $UID_WWW $HOSTING_SRC/$webvps/volumes/www
		done
		;;
	up|rm|start|stop)
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			echo "Webvps $webvps"
			echo "=============="
			. $HOSTING_SRC/$webvps/webvps.env
			cd $HOSTING_SRC/$webvps;
			if [ "$1" = "up" ]; then
				docker-compose up -d
			else
				docker-compose $1
			fi
		done
		;;
	*)
		>&2 echo "Command $1 not found. Usage : webvps.sh <command> <options>"
		exit 1
esac
