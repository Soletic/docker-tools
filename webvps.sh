#!/bin/bash

BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Default value
JSON_DOCKER_WEBVPS='{"webvps": [], "src": "$BASEDIR/../webvps"}'
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
			# Convert because size could be scientific notation
			printf -v size "%.f" "$3"
			setquota -u $2 $size $size 1000000 1000000 -a
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
	chown -R $WEBVPS_WORKER_UID:$WEBVPS_WORKER_UID $HOSTING_SRC/$webvps/volumes/www
	# Fix quota
	_setquota add $WEBVPS_WORKER_UID $(_webvps_getinfo $webvps "diskquota")
}

function _webvps_getinfo {
	if [ -z $1 ] || [ -z $2 ]; then
		>&2 echo "_webvps_getinfo require two arguments : webvps name and key of the info"
		exit
	fi
	local webvps=$1
	local key=$2
	local i=0
	for webvps_loop in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output '.webvps[] | .name'); do
		if [ "$webvps_loop" = "$webvps" ]; then
			echo $(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".webvps[$i] | .$key")
		fi 
		((i+=1))
	done
	echo ""
}

# Check is a webvps as a property with specific value
function _webvps_is_webvps_exist_by_property {
	if [ -z $1 ] || [ -z $2 ]; then
		>&2 echo "_webvps_is_exist require two arguments : <property> and <value>"
		exit
	fi
	local property=$1
	local value=$2
	local i=0
	for property_value in $(echo $JSON_DOCKER_WEBVPS | jq --raw-output ".webvps[] | .$property"); do
		if [ "$property_value" = "$value" ]; then
			echo true
			return
		fi 
	done
	echo false
}

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

		# Check if the sshd container running (require to add a user allowing access volumes)
		WEBVPS_SSH_CONTAINER_ID=$(docker ps --format="{{.ID}}" --filter="name=sshd.webvps")
		if [ "$WEBVPS_SSH_CONTAINER_ID" = "" ]; then
			>&2 echo "SSH webvps container missing and required to setup sshd access. Please run the container sshd.webvps"
			exit 1
		fi

		# Set env for the webvps
		WEBVPS_WORKER_UID=$(($WEBVPS_ID+10000))
		WEBVPS_PORT_HTTP=$(($WEBVPS_ID+200))"80"
		WEBVPS_PORT_HTTPS=$(($WEBVPS_ID+200))"43"
		WEBVPS_PORT_SSH=$(($WEBVPS_ID+200))"22"
		WEBVPS_PORT_MYSQL=$(($WEBVPS_ID+200))"36"

		if ! type "nproc" > /dev/null; then
			cpu_total=1
		else
			cpu_total=$(nproc)
		fi

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
				export WEBVPS_TYPE=$WEBVPS_TYPE
				export WEBVPS_EMAIL=$WEBVPS_EMAIL
			EOF

		#### Docker compose 
		# Create docker-compose and image base
		ln -s $BASEDIR/templates/base.yml $HOSTING_SRC/$WEBVPS_NAME/base.yml
		cp $BASEDIR/templates/$WEBVPS_TYPE/$WEBVPS_TYPE-docker-compose.yml $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
		is_mysql=$(cat $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml | grep -e "^mysql")
		is_phpserver=$(cat $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml | grep -e "^phpserver")
		# Limit resources
		cpu_shares=128 # If overload, max 12.5% of CPU (fair rule)
		platform=$(uname)
		if [ "$is_phpserver" != "" ] && [ "$platform" != "Darwin" ]; then # MacOSX has sed options differents from Ubuntu
			cpuset=$(expr $WEBVPS_ID % $cpu_total)
			mem_limit=1g
			sed -ri -e "s/%phpserver_cpuset%/$cpuset/" -e "s/%phpserver_cpu_shares%/$cpu_shares/" -e "s/%phpserver_memlimit%/$mem_limit/" $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
		fi
		if [ "$is_mysql" != "" ] && [ "$platform" != "Darwin" ]; then # MacOSX has sed options differents from Ubuntu
			cpuset=$(expr $(expr $WEBVPS_ID + 1) % $cpu_total) # cpu different of web
			mem_limit=512m
			sed -ri -e "s/%mysql_cpuset%/$cpuset/" -e "s/%mysql_cpu_shares%/$cpu_shares/" -e "s/%mysql_memlimit%/$mem_limit/" $HOSTING_SRC/$WEBVPS_NAME/docker-compose.yml
		fi

		#### Init volumes
		# Is phpserver ?
		if [ "$is_phpserver" != "" ]; then
			mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/www/{conf,logs,html,cgi-bin}
			mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/www/conf/{apache2,certificates}
			mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/home
			cat > $HOSTING_SRC/$WEBVPS_NAME/volumes/www/html/index.html <<-EOF
					Welcome $WEBVPS_HOST
				EOF
		fi
		# Is mysql ?
		if [ "$is_mysql" != "" ]; then
			mkdir -p $HOSTING_SRC/$WEBVPS_NAME/volumes/www/backup/mysql
		fi

		# Add the new webvps in json file
		echo $JSON_DOCKER_WEBVPS | jq ".webvps |= .+ [{\"name\": \"$WEBVPS_NAME\", \"host\": \"$WEBVPS_HOST\", \"host_alias\": \"$WEBVPS_HOST_ALIAS\", \"uid\": $WEBVPS_ID, \"diskquota\": $WEBVPS_DISK_QUOTA, \"email\": \"${WEBVPS_EMAIL}\" }]" > $JSON_DOCKER_PATH
		
		# Add sftuser
		docker exec -it sshd.webvps /chroot.sh adduser -u $WEBVPS_NAME -id $WEBVPS_WORKER_UID
		docker exec -it sshd.webvps /root/scripts/chroot_init_mysql.sh conf -u $WEBVPS_NAME -P $WEBVPS_PORT_MYSQL

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
				# Remove sftpuser
				WEBVPS_SSH_CONTAINER_ID=$(docker ps --format="{{.ID}}" --filter="name=sshd.webvps")
				if [ "$WEBVPS_SSH_CONTAINER_ID" != "" ]; then
					docker exec -it sshd.webvps /chroot.sh deluser -u $webvps
				fi
		
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
				# Create user in the chroot ssh

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
			echo "WEBVPS_NAME=$WEBVPS_NAME"
			echo "WEBVPS_HOST=$WEBVPS_HOST"
			echo "WEBVPS_HOST_ALIAS=$WEBVPS_HOST_ALIAS"
			echo "WEBVPS_PROXY_HOSTS=$WEBVPS_PROXY_HOSTS"
			echo "WEBVPS_ID=$WEBVPS_ID"
			echo "WEBVPS_WORKER_UID=$WEBVPS_WORKER_UID"
			echo "WEBVPS_PORT_HTTP=$WEBVPS_PORT_HTTP"
			echo "WEBVPS_PORT_HTTPS=$WEBVPS_PORT_HTTPS"
			echo "WEBVPS_PORT_SSH=$WEBVPS_PORT_SSH"
			echo "WEBVPS_PORT_MYSQL=$WEBVPS_PORT_MYSQL"
			echo "WEBVPS_TYPE=$WEBVPS_TYPE"
			echo "WEBVPS_EMAIL=$WEBVPS_EMAIL"
			
			# Mysql credentials
			echo "## Mysql credentials"
			cat $HOSTING_SRC/$webvps/volumes/www/backup/mysql/credentials

			# SFTP credentials
			WEBVPS_SSH_CONTAINER_ID=$(docker ps --format="{{.ID}}" --filter="name=sshd.webvps")
			if [ "$WEBVPS_SSH_CONTAINER_ID" != "" ]; then
				echo "## SFTP credentials"
				docker exec -it sshd.webvps bash -c "cat /chroot/$webvps/credentials"
			fi

		done
		;;
	*)
		>&2 echo "Command $1 not found. Usage : webvps.sh <command> <options>"
		exit 1
esac

