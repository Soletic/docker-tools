#!/bin/bash

repos=("hosting-docker-ubuntu" "hosting-docker-mailer-webvps" "hosting-docker-phpserver" "hosting-docker-mysql" "hosting-docker-phpmyadmin" "hosting-docker-sshd" "hosting-docker-ssh-chroot" "hosting-docker-ssh-webvps" "hosting-docker-wikitten" "hosting-docker-redmine")
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

build_with_no_cache=false
build_with_pull=true
for i in "$@"; do
case $i in
	--no-cache)
		build_with_no_cache=true
		;;
	--no-pull)
		build_with_pull=false
		;;
	*)
		# unknown option
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
	echo "## docker build -t soletic/$name --no-cache=${build_with_cache} ./src/$repo"
	if [ $is_pull -eq 0 ] || [ "$build_with_pull" = "false" ]; then
		docker build -t soletic/$name --no-cache=${build_with_no_cache} ./src/$repo
	else
		docker build --pull -t soletic/$name --no-cache=${build_with_no_cache} ./src/$repo
	fi
done