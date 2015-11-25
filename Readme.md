# A docker hosting solution with Docker

Soletic is a non profit organisation prividing hosting solutions for others organisation engaged in social innovation.

Web build a solution to setup a physical server with a complete system to deploy **Virtual Private Server** (VPS) with docker.

The project was created by [Laurent Chedanne](https://twitter.com/lchedanne) with the support of [Nicolas Claverie](https://twitter.com/artscorestudio)

We are french and have tried to write in english. Excuse us for our language mistakes :-)

## What is a VPS ?

A VPS is a stack of containers providing web services (http server, ssh, ...) in order to serve a web feature (website, ...). Indeed, you can build a server to provide a share hosting solution with finest resources control.

We have decided to use Docker.

Advantages :

* Each VPS has resources limited for fair sharing : CPU, RAM and disk space
* You only need two servers : one for running webvps and one for backup.
* A suit of tools for an easy manage 

This documentation explains :

* The setup of servers
* Howto deploy a VPS
* Backup and restore mechanism
* Limitations
* Useful commands to manage
* Roadmap and howto contribute

## Docker host installation

### Setup the Docker Host Server

In this section, we describe howto to prepare your host server for all your future services we will have to deploy.

The documentation has been written for Ubuntu Trusty.

Requirements :

* A server with Ubuntu Trusty
* A user with sudo authorisation (never use the root !)

#### Create the hosting directory

We create the hosting directory :

```
$ sudo mkdir -p /home/docker/hosting/webvps
$ export DOCKER_HOSTING=/home/docker/hosting
```

Don't forget : **Add the export command in the ```~/.profile``` !!!**

#### Install docker


```
$ sudo apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
$ sudo vi /etc/apt/sources.list.d/docker.list
	+ deb https://apt.dockerproject.org/repo ubuntu-trusty main
$ sudo apt-get update
$ sudo apt-get purge lxc-docker*
```
Verify that apt is pulling from the right repository (apt.dockerproject.org).

```
$ sudo apt-cache policy docker-engine
```

And install

```
$ sudo apt-get install docker-engine
$ sudo service docker start
```

Verify docker is installed correctly.

```
$ sudo docker run hello-world
```

This command downloads a test image and runs it in a container. When the container runs, it prints an informational message. Then, it exits.

```
$ sudo mkdir /home/docker
$ sudo mkdir /home/docker/hosting
$ sudo mkdir /home/docker/lib
```

#### Install docker-compose

```
$ cd $DOCKER_HOSTING
$ sudo su root
$ curl -L https://github.com/docker/compose/releases/download/1.5.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
$ chmod +x /usr/local/bin/docker-compose
```

#### Move docker data (optionnal)

If the partition's size /var/lib/docker is smaller than your /home, we can move it following this instructions

```
$ sudo service docker stop
$ sudo chmod go+rx lib/
$ sudo rsync -aXS /var/lib/docker/. /home/docker/lib/
$ sudo vi /etc/fstab
	+ /home/docker/lib        /var/lib/docker none    bind    0       0
$ sudo mount -a
$ sudo service docker start
```

### Build docker images providing by Soletic

Install our tools suite for docker management :

```
$ cd /path/to/hosting
$ sudo git clone https://github.com/Soletic/docker-tools.git ./tools
$ sudo chmod u+x ./tools/*.sh
$ sudo ./tools/install_soletic_image.sh
```

### Quota disk space management

The ```quota``` package is useful to setup a disk space quota management. [See this docker issue to understand the strategy](hytps://github.com/docker/docker/issues/471#issuecomment-22715725)

```
$ sudo apt-get -y install quota quotatool
```

Editer le fichier /etc/fstab pour remplacer defaults,relatime de la ligne /home par defaults,usrquota,grpquota,relatime :

```
/dev/sda3       /home   ext4    defaults,usrquota,grpquota,relatime     1       2
```
```
$ sudo mount -o remount /home
$ sudo quotaon -avug
```


### Run a stack of required containers

#### HTTP Proxy

The server hosts containers and we use a proxy container to redirect request from a domain name to the right container. We use the image [jwilder/nginx-proxy](https://github.com/jwilder/nginx-proxy) in this purpose.

First we have to start this container in your server :

```
$ sudo mkdir -p $DOCKER_HOSTING/certs
$ sudo docker run -d -p 80:80 -p 443:443 -v $DOCKER_HOSTING/certs:/etc/nginx/certs -v /var/run/docker.sock:/tmp/docker.sock:ro --name http-proxy jwilder/nginx-proxy
```

#### SSH and SFTP services

Start the container to expose the ssh service used to access data of others containers

```
$ sudo docker run -d -p 2222:22 -v $DOCKER_HOSTING/webvps:/home -e CHROOT_USER_HOME_BASEPATH=/volumes/www --name sshd.webvps --privileged soletic/ssh-webvps
```

* option --privileged required to give mount permissions inside the container ([see here >](https://github.com/docker/docker/issues/5254))
* A root password is generated but it is generated at each start for security reasons.

This container provides a solution to create an sftp and ssh access for each webvps. By default, the user will have git, php et mysql commands with its volume data mounted.

[See the git repository of the docker image for more information >](https://github.com/Soletic/hosting-docker-sshd)


## Deploy a VPS

### Create and first run of the VPS

```
$ cd $DOCKER_HOSTING
$ sudo tools/webvps.sh new -n example -h example.org -s lamp -email contact@example.org
```

**!! -- Note the password to give it to the client. -- !!**

Explication about options :

* -n : unique name to refer project
* -h : host domaine name. Auto add the domaine name with www prefix
* -s : service name to deploy as webvps
	* lamp : 3 containers with mysql, phpserver and phpmyadmin
	* phpserver : 1 container with phpserver
* -email : email of the client

More options with :

* -dq : disk quota. For example for 2G : 2000000
* -id : set manually the unique user id
* --host-alias : 
	* Either set "no" if you don't want auto complete the domain name (with www)
	* Or set a comma seperated list of domains name

```
If you want to activate SSL, see the section "Limitations and troubles > SSL Support"
```

Now, up the webvps

```
$ cd /path/to/hosting
$ sudo tools/webvps.sh up example
```
**!! -- Read and note the mysql credentials -- !!**

The file ```$DOCKER_HOSTING/<webvpsname>/volumes/var/www/backup/mysql/credentials``` stores the credentials of mysql user created.

### Create your own service

Writing in progress...

## Backup and restore

### Backup

#### Automysqlbackup

The mysql image contains a automysqlbackup script. The bash script is launched by crontab every day to backup daily, weekly and monthly the database in the directory ```$DOCKER_HOSTING/<webvpsname>/volumes/var/www/backup/mysql```

#### Rsync

Configure the server with another server to rsync the ```$DOCKER_HOSTING```

#### Docker repository (à écrire)

This article is interesting to play with commit and tag : http://stackoverflow.com/questions/25335505/how-do-i-use-the-git-like-capabilities-of-docker

Useful to rollback if an error occured.

### Restore (à écrire)

Writing in progress...

## Upgrade and security management

### Information that you have to know !

```
BE AWARE THAT IF YOU RM A CONTAINER AND UP AGAIN, YOU WILL LOSE :
- configuration of php, mysql
- crontab scheduled

```

To avoid the problem, there is one solution : 

* create your own docker image in ```$DOCKER_HOSTING/src/<own_image>```
* built it
* Modify the docker-compose of the webvps

Indeed, you never have to modify configuration system of a container !

### Understanding of the strategy

All images has been built with ubunty:trusty. To update packages of all running containers, you must build regurlaly the based images :

```
$ cd $DOCKER_HOSTING
$ sudo ./tools/install_soletic_image.sh
```
And recreate webvps

```
$ ./tools/webvps recreate
```

You can't apply this method in these cases if new volumes has been added in the based image or if you want to mount a new volume from host.

```
We advice you to test with sample webvps before !!!
$ ./tools/webvps recreate my_sample_webvps
```

# Useful command line

**List all webvps**

```
$ sudo $DOCKER_HOSTING/tools/webvps.sh list
```

**Get all informations about a webvps**

```
$ sudo $DOCKER_HOSTING/tools/webvps.sh info <webvps name>
```

**Stop, rm, up, recreate, start a webvps**

```
$ sudo $DOCKER_HOSTING/tools/webvps.sh stop <webvps name>
$ sudo $DOCKER_HOSTING/tools/webvps.sh start <webvps name>
$ sudo $DOCKER_HOSTING/tools/webvps.sh rm <webvps name>
$ sudo $DOCKER_HOSTING/tools/webvps.sh up <webvps name>
$ sudo $DOCKER_HOSTING/tools/webvps.sh recreate <webvps name>
```

If you miss the vps name, the command will be applied for all webvps !!!

* The recreate command stop, rm, build (without cache) and up the webvps

**Terminal in container running**

```
$ sudo docker exec -it <webvps name>.<phpserver|mysql|...> bash
```

**If entry point failed, you can run the image with bash as entry point :**

```
$ docker run --rm -it --entrypoint="" --volumes-from soletic_dev.data soletic/webvps bash
```

**Command to generate big files (and test quota). Here a file of 5M) :**

```
$ dd if=/dev/zero of=file.txt count=5 bs=1M
```

# Troubles and limitations

## MacosX

Docker compose doesn't work !

## Container size limit

By default, a container size can't greater than the default value of dm.basesize (10G or 100G depends on the docker version).

We didn't find how to get the default value for docker installed to the server.

In the docker tools of Soletic, a script list all container with size indications to help you if the server would have disk space troubles.

## SSL Support

With [jwilder/nginx-proxy](https://github.com/jwilder/nginx-proxy), the behavior for the proxy when port 80 and 443 are exposed is as follows:

* If a container has a usable cert, port 80 will redirect to 443 for that container so that HTTPS is always preferred when available.
* If the container does not have a usable cert, a 503 will be returned.

```
So when you setup a webvps, you 
- can't have a domain and subdomains configured with ssl for one and no ssl in the other hand
- can have vhosts with differents domains, every vhost choosing ssl or not
```

### Add ssl support for a domain to a container

The webmaster of a webvps can't add himself certificates because you have to add certificates in the certs directory of http proxy (mounted with /home/docker/hosting/certs)

* [optional] If you have trusted certificates signed, copy the *.key and *.crt in directory ```www/conf/certificates```. The file name have to the same of the host domaine !
* Copy this files in the certs directory of the proxy
* In directory ```www/conf``` create the file ```apache.reload``` to force reload of apache (max one minute to reload)
* Restart the http proxy container

### Remove ssl support to a container

* Remove certificates from ```/home/docker/hosting/certs```
* Stop the proxy server, delete it and up again

# Documentation

* [Une très bonne introduction à Docker](http://blog.thoward37.me/articles/where-are-docker-images-stored/) pour comprendre sa structuration et vocabulaire
* [jq command](https://stedolan.github.io/jq/manual/). jq is a lightweight and flexible command-line JSON processor
* [Using Supervisor with Docker](https://docs.docker.com/v1.8/articles/using_supervisord/)
* [Dockerizing an SSH daemon service](https://docs.docker.com/v1.8/examples/running_ssh_service/)
* [If you run SSHD in your Docker containers, you're doing it wrong!](http://jpetazzo.github.io/2014/06/23/docker-ssh-considered-evil/) : petit cours pour se baser de ssh dans bien des cas et mettre ne place nsenter si vraiment besoin
* [How do I parse command line arguments in bash?](http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash)
* [Docker - How to analyze a container's disk usage?](http://stackoverflow.com/questions/26753087/docker-how-to-analyze-a-containers-disk-usage)
* [Petit cours pour jouer avec les images docker comme on ferait avec git](http://stackoverflow.com/questions/25335505/how-do-i-use-the-git-like-capabilities-of-docker)
* [PHP 5.6 sur Unbuntu](http://devdocs.magento.com/guides/v2.0/install-gde/prereq/php-ubuntu.html#instgde-prereq-php56-install-ubuntu)
* [Supervisor documentation](http://supervisord.org/configuration.html#program-x-section-values)
* [Setting Up Git in Conjunction with an ISPConfig chroot (JailKit)](https://www.howtoforge.com/community/threads/setting-up-git-in-conjunction-with-an-ispconfig-chroot-jailkit.62570/)

# Contribute

## Roadmap

* Tester sur kimsufi le docker-compose et limit CPU et MEM
* Système de mail (avec mailjet et juste sendmail)
	* Ne pas oublier d'activer pour le sshwebvps
	* msmtp
		* https://hub.docker.com/r/sysdia/docker-php-server/~/dockerfile/
		* http://doc.ubuntu-fr.org/tutoriel/		comment_envoyer_un_mail_par_smtp_en_ligne_de_commande
	* Hostname au container : 
		* docker run -h myhostname
		* Voir fichier /etc/hostname
	* OpenDKIM : https://hub.docker.com/r/marvambass/versatile-postfix/ + https://www.exratione.com/2014/07/setting-up-spf-and-dkim-for-an-ubuntu-1404-mail-server/
	* Use sendgrid free or Amazon SES : https://sendgrid.com/pricing / https://aws.amazon.com/fr/ses/
* Migrer soletic.org et owncloud
* Relancer automatiquement les containers au démarrage
* Stratégie de backup
	* rsync de /path/to/hosting pour redéploiement rapide
	* commit et push vers depot central des containers avec tag :instance
* Mettre la doc .md sur un wiki Markdown et accessible sur les deux serveurs ks.
	* Un wiki markdown PHP : http://wikitten.vizuina.com/
* Voir pour un mécanisme de restauration facile...
	* La restauration doit se faire avec la base mysql pour récupérer les comptes utilisateurs et mot de passe 	

## Ideas

* Authorise to setup crontab in our phpserver (without lost if rebuild container)
* [Secure phpMyAdmin container](https://www.digitalocean.com/community/tutorials/how-to-install-and-secure-phpmyadmin-on-ubuntu-14-04)
* docker tools :
	* Improve webvps.sh to guess a new free uid for webvps html data 
	* Improve webvps.sh to delete images when a webvps is deleted
* Un systeme d'alerte des webvps qui vont atteindre leur quota d'espace disque
* Traffic Control in the Linux kernel (command tc) to limit bandwith
* Créer une registry Docker propre à Sol&TIC [tuto ici >](https://blog.docker.com/2013/07/how-to-use-your-own-registry/). Permettrait de faire du backup...
* mysql restore : Créer un programme de restauration de bdd (qui sera lancé via [docker-run](https://github.com/iTech-Developer/docker-run))
* Créer un soletic/wordpress
* Créer un soletic/yunohost
* Certificat auto généré sur phpserver ne fonctionne pas sur domaine ET sous domaine
	* [Voir le tuto initialement suivi](http://blog.endpoint.com/2014/10/openssl-csr-with-alternative-names-one.html) 
	* Fichier concerné : [start-apache2.sh](https://github.com/Soletic/hosting-docker-phpserver/blob/master/start-apache2.sh)
	
## Contribution process

* Create an issue to discuss
* Fork, improve and pull request !

