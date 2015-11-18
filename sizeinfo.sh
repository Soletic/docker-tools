#!/bin/bash

DOCKER_PATH="/var/lib/docker"
if [ "$#" -eq 1 ]
	then
	DOCKER_PATH=$1
	fi


for d in `docker ps | awk '{print $1}' | tail -n +2`; do
    d_name=`docker inspect -f {{.Name}} $d`
    echo "========================================================="
    echo "$d_name ($d) container size:"
    sudo du -d 2 -h $DOCKER_PATH/devicemapper | grep `docker inspect -f "{{.Id}}" $d`
    echo "$d_name ($d) volumes:"
    docker inspect -f "{{.Volumes}}" $d | sed 's/map\[//' | sed 's/]//' | tr ' ' '\n' | sed 's/.*://' | xargs sudo du -d 1 -h
done