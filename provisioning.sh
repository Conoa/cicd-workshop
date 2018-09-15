#!/bin/sh 
DOCKERURL="https://storebits.docker.com/ee/centos/sub-7019e3a8-f1cf-434c-b454-952669b3e8b2"
sudo -E sh -c 'echo "$DOCKERURL/centos" > /etc/yum/vars/dockerurl'
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
sudo -E yum-config-manager --add-repo "$DOCKERURL/centos/docker-ee.repo
yum-config-manager --enable docker-ee-stable-17.06
sudo yum -y install docker-ee-stable-17.06
sudo systemctl start docker
sudo docker run hello-world
sudo systemctl stop firewalld
sudo systemctl disable firewalld