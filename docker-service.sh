#!/bin/bash

JSON_DOCKER_SERVICES=$(cat /home/docker/hosting/services.json)

# Block size of the system. To get it : sudo fdisk -l $(df -P . | tail -1 | cut -d' ' -f 1) | grep ^Unités
BLOCK_SIZE=512

if [ "$1" = "autoremove" ]; then
	docker rmi $(docker images | grep "<none>" | awk "{print \$3}")
	exit 0
fi

function _setquota {
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

# Command to manage all webvps
i=0
for webvps in $(echo $JSON_DOCKER_SERVICES | jq --raw-output '.webvps[] | .name'); do
        echo "Webvps $webvps"
        echo "=============="
        export DOCKER_SERVICE_NAME=$webvps
        export DOCKER_SERVICE_HOST=$(echo $JSON_DOCKER_SERVICES | jq --raw-output ".webvps[$i] | .host")
        export DOCKER_SERVICE_USERID_SHARED=$(echo $JSON_DOCKER_SERVICES | jq --raw-output ".webvps[$i] | .uid")
        DOCKER_SERVICE_DISK_QUOTA=$(echo $JSON_DOCKER_SERVICES | jq --raw-output ".webvps[$i] | .diskquota")
        DOCKER_SERVICE_DISK_QUOTA=$(($DOCKER_SERVICE_DISK_QUOTA*1024/$BLOCK_SIZE))
        cd /home/docker/hosting/src/$webvps;
        if [[ ! -d /home/docker/hosting/src/$webvps/volumes ]]; then
        	mkdir -p /home/docker/hosting/src/$webvps/volumes/www
        else
        	chown -R $DOCKER_SERVICE_USERID_SHARED /home/docker/hosting/src/$webvps/volumes/www
        fi
        case "$1" in
        	quota)
				if [ "$2" = "" ]; then
					echo "Quota instruction missing. Example of valid command : docker-service.sh quota add|remove"
				fi
				_setquota $2 $DOCKER_SERVICE_USERID_SHARED $DOCKER_SERVICE_DISK_QUOTA
				;;
			up)
				docker-compose up -d
				setquota -u $DOCKER_SERVICE_USERID_SHARED $DOCKER_SERVICE_DISK_QUOTA $DOCKER_SERVICE_DISK_QUOTA 1000000 1000000 -a
				;;
			start)
				docker-compose start
				;;
			stop)
				docker-compose stop
				;;
			rm)
				docker-compose rm
				_setquota remove $DOCKER_SERVICE_USERID_SHARED
				;;
			*)
				echo "Command $1 not found"
				exit 1
		esac
        ((i+=1))
done
