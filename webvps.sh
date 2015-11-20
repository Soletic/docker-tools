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
	hash setquota 2>/dev/null || { echo >&2 "No quota setup because setquota command missing in your system"; return; }
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

function _refresh {
	# Refresh permissions file on volume
	webvps=$1
	. $HOSTING_SRC/$webvps/webvps.env
	chown -R $WEBVPS_UID_WWW:$WEBVPS_UID_WWW $HOSTING_SRC/$webvps/volumes/www
	# Fix quota
	_setquota add $WEBVPS_UID_WWW $(_webvps_getinfo $webvps "diskquota")
}

function _webvps_getinfo {
	if [ -z $1 ] || [ -z $2 ]; then
		>&2 echo "_webvps_getinfo require two arguments : webvps name and key of the info"
		exit
	fi
	webvps=$1
	key=$2
	i=0
	for webvps_loop in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
		if [ "$webvps_loop" = "$webvps" ]; then
			echo $(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".webvps[$i] | .$key")
		fi 
		((i+=1))
	done
	echo ""
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
		echo "$WEBVPS_NAME setup"
		# Init volumes
		mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/www/html $HOSTING_SRC/$WEBVPS_NAME/volumes/mysql
		cat > $HOSTING_SRC/$WEBVPS_NAME/volumes/www/html/index.html <<-EOF
				Welcome $WEBVPS_HOST
			EOF
		# Create an env file
		cat > $HOSTING_SRC/$WEBVPS_NAME/webvps.env <<-EOF
				#!/bin/bash
				export WEBVPS_NAME=$WEBVPS_NAME
				export WEBVPS_HOST=$WEBVPS_HOST
				export WEBVPS_UID_WWW=$WEBVPS_WWW_UID
			EOF
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
		# Refresh
		_refresh $WEBVPS_NAME
		echo " > Created ! Now execute : webvps.sh up $WEBVPS_NAME"
		;;
	refresh)
		# Refresh informations and setting for all webvps. Useful to fix problems
		for webvps in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
			_refresh $webvps
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
				cd $HOSTING_SRC/$webvps;
				docker-compose stop
				docker-compose rm -f
				rm -Rf $HOSTING_SRC/$webvps
				echo $JSON_DOCKER_WEBVPS | jq "del(.webvps[$i])" > $JSON_DOCKER_PATH
				echo "$webvps remove (but not associated image)"
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
			if [ "$1" = "up" ]; then
				docker-compose up -d
			elif [ "$1" = "recreate" ]; then
				docker-compose stop
				docker-compose rm -f
				docker-compose build --no-cache 
				docker-compose up -d --force-recreate
				_refresh $webvps
			else
				docker-compose $1
			fi
		done
		;;
	*)
		>&2 echo "Command $1 not found. Usage : webvps.sh <command> <options>"
		exit 1
esac

