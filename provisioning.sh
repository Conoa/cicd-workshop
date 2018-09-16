#!/bin/sh 
set -x
export DOCKERURL="https://storebits.docker.com/ee/centos/sub-7019e3a8-f1cf-434c-b454-952669b3e8b2"
echo "$DOCKERURL/centos" > /etc/yum/vars/dockerurl
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo "$DOCKERURL/centos/docker-ee.repo"
yum-config-manager --enable docker-ee-stable-17.06
yum -y -q install docker-ee
sync
mkdir /etc/docker
cat << EOT > /etc/docker/daemon.json
{
"hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
EOT
systemctl start docker
usermod -a -G docker centos

