#!/bin/bash

repos=("hosting-docker-ubuntu" "hosting-docker-mailer-webvps" "hosting-docker-phpserver" "hosting-docker-mysql" "hosting-docker-phpmyadmin" "hosting-docker-sshd" "hosting-docker-ssh-chroot" "hosting-docker-ssh-webvps")
repos_with_pull=("hosting-docker-ubuntu")

if [ -z "$DOCKER_HOSTING" ]; then
	DOCKER_HOSTING=/home/docker/hosting
fi
if [ ! -d $DOCKER_HOSTING ]; then
	>&2 echo "Directory $DOCKER_HOSTING doesn't exist"
	exit 1
fi
if [ ! -d $DOCKER_HOSTING/src ]; then
	mkdir $DOCKER_HOSTING/src
fi

build_with_cache=true
while [[ $# > 1 ]] 
do
	key="$1"
	case $key in
		--no-cache)
			build_with_cache=false
			;;
		*)
			# unknown option
			shift
			;;
	esac
done

cd $DOCKER_HOSTING
for repo in "${repos[@]}"
do
	if [ ! -d $DOCKER_HOSTING/src/$repo ]; then
		git clone https://github.com/Soletic/$repo.git ./src/$repo
	else
		cd src/$repo
		git pull
		cd $DOCKER_HOSTING
	fi
	is_pull=0
	for repo_test in "${repos_with_pull[@]}"
	do
		if [ "$repo_test" = "$repo" ]; then
			is_pull=1
			break
		fi
	done
	name=$(echo "$repo" | sed -e "s/hosting-docker-//g")
	if [ $is_pull -eq 0 ]; then
		docker build -t soletic/$name --no-cache=${build_with_cache} ./src/$repo
	else
		docker build --pull -t soletic/$name --no-cache=${build_with_cache} ./src/$repo
	fi
done