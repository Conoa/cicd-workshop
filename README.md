# cicd-workshop

## What is this?
This repo contains setup scripts for Conoa CICD workshop. <br>

## Workshop workflow
1. [Install docker](#step1)
2. [Install UCP + DTR på en maskin + 1 worker i dev]
3. Install UCP + DTR på en maskin + 1 worker i prod
4. Lägg upp license i dev + prod
5. Sätt upp CA-trust på alla 4 maskiner
6. Skapa repot admin/jenkins i dev-DTR
7. Bygg en Jenkins image och pusha till dev-dtr/admin/jenkins
8. Starta jenkins container i dev-worker
9. Skapa ett admin/app repo i dev och ett admin/app repo i prod
10. Sätt upp ett github-repo med webhook mot vår test-dtr
11. Skapa ett jenkins jobb som ska bygga vår test applikation, samt pusha till dev-DTR
12. När en ny tag pushas in i dev-DTR så ska en säkerhetscan startas
  * Om sec-scan har mer än 1 critical: promota image till admin/vulnerable-app
  * Om sec-scan har 0 crit: promota image (mirror) till prod-dtr/admin/app
13. Manuell deploy av image till prod.

<a name="step1"><h3>Install docker</h3></a>
```
export DOCKERURL="https://storebits.docker.com/ee/centos/sub-7019e3a8-f1cf-434c-b454-952669b3e8b2"
echo "$DOCKERURL/centos" | sudo tee /etc/yum/vars/dockerurl
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
sudo yum-config-manager --add-repo "$DOCKERURL/centos/docker-ee.repo"
sudo yum-config-manager --enable docker-ee-stable-17.06
sudo yum -y -q install docker-ee unzip
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker centos
```
<a name="step2"><h3>Install UCP på en maskin + 1 worker i dev]</h3></a>
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:latest install \
  --admin-username admin  \
  --admin-password changeme \
  --san dev-ucp.cicd.conoa.se \
  --san dev-worker.cicd.conoa.se \
  --san dev-dtr.cicd.conoa.se \
  --controller-port 443 \
  --disable-tracking \
  --disable-usage
docker swarm join-token worker
```
### Installera DTR
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://dev-ucp.cicd.conoa.se \
  --ucp-node dev-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://dev-dtr.cicd.conoa.se:4443
```

<a name="step3"><h3>Install UCP på en maskin + 1 worker i prod</h3></a>
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:latest install \
  --admin-username admin  \
  --admin-password changeme \
  --san prod-ucp.cicd.conoa.se \
  --san prod-dtr.cicd.conoa.se \
  --san prod-worker.cicd.conoa.se \
  --controller-port 443 \
  --disable-tracking \
  --disable-usage
docker swarm join-token worker
```
### Installera DTR
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://prod-ucp.cicd.conoa.se \
  --ucp-node prod-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://prod-dtr.cicd.conoa.se:4443
```

<a name="step4"><h3>Lägg upp licensen i dev + prod</h3></a>
Görs i GUI

<a name="step5">Sätt upp CA-trust i dev </h3></a>
```
export DTR_FQDN="dev-dtr.cicd.conoa.se:4443"
sudo curl -k \
  https://${DTR_FQDN}:4443/ca \
  -o /etc/pki/ca-trust/source/anchors/${DTR_FQDN}:4443.crt
```






## Todo
- [x] Terraform a docker swarm in AWS
- [ ] Simple copy n' paste for UCP + 2 DTR
- [ ] Better provisioning (docker shouldn't listen on *:2375 *)
- [ ] Add unzip at cloud-init



## Terraform
Terraform reads all .tf files in a directory.

Add your access and secret key to credentials.tf
```
 cat << EOT > credentials.tf
  provider "aws" {
  access_key = "YOUR ACCESS KEY"
  secret_key = "YOUR SECRET KEY"
  region = "eu-central-1"
 }
 EOT
```
If the AMI isn't found, search after a new one: 
```
aws --region eu-central-1 ec2 describe-images --owners aws-marketplace --filters Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce
```

To setup our instances, just run:
```
terraform apply
```

## UCP
Setup UCP with
```
cat << EOT | sudo tee /etc/docker/daemon.json
{
"hosts": ["unix:///var/run/docker.sock"]
}
EOT
sudo systemctl restart docker
```
You need to run the above on all nodes
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:latest install \
  --admin-username admin  \
  --admin-password changeme \
  --san manager-0.cicd.conoa.se \
  --san swarm-0.cicd.conoa.se \
  --san swarm-1.cicd.conoa.se \
  --san ucp.cicd.conoa.se \
  --san dtr1.cicd.conoa.se \
  --san dtr2.cicd.conoa.se \
  --controller-port 443 \
  --disable-tracking \
  --disable-usage
```
Browse to UCP node and configure:
* Add license
* Layer 7 routing

## DTR
Setup DTR
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://manager-0.cicd.conoa.se \
  --ucp-node swarm-0 \
  --replica-https-port 444 \
  --replica-http-port 81 \
  --dtr-external-url https://dtr1.cicd.conoa.se:444
```
## Jenkins
We need to use a special Jenkins Dockerfile (stacks/jenkins/build/Dockerfile):
```
mkdir -p stacks/jenkins/build/
cat << EOT > stacks/jenkins/build/Dockerfile
FROM jenkins/jenkins:lts
USER root
ENV JAVA_OPTS "-Djenkins.install.runSetupWizard=false"
RUN DEBIAN_FRONTEND=non-interactive apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common && \
  curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian stretch stable" && \
  apt-get update && \
  apt-get install -y docker-ce && \
  rm -rf /var/lib/apt/*
USER jenkins
RUN touch /var/jenkins_home/.last_exec_version && \
    echo 2.0 > /var/jenkins_home/upgraded && \
    mkdir /var/jenkins_home/jobs/ &&
    /usr/local/bin/install-plugins.sh generic-webhook-trigger
EOT
```
We also need a docker-compose.yml (stacks/jenkins/docker-compose.yml):
```
mkdir -p stacks/jenkins/
cat << EOT > stacks/jenkins/docker-compose.yml
version: '3.5'
services:
  jenkins:
    image: dtr1.cicd.conoa.se:444/admin/jenkins
    build:
      context: ./build
    ports:
      - "8080:8080"
    deploy:
      com.docker.lb.hosts: jenkins.cicd.conoa.se
      com.docker.lb.network: jenkins-network
      com.docker.lb.port: 80
    networks:
      - jenkins-network
networks:
  jenkins:
    driver: overlay
EOT
```
We need some credentials
```
UCP_FQDN=manager-0.cicd.conoa.se
DTR_FQDN=dtr1.cicd.conoa.se:444
AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
export DOCKER_TLS_VERIFY=1
export COMPOSE_TLS_VERSION=TLSv1_2
export DOCKER_CERT_PATH=$PWD
export DOCKER_HOST=tcp://${UCP_FQDN}:443
docker login -u admin -p changeme https://${DTR_FQDN}
```
Now let the swarm build and run our Jenkins container
```
docker-compose -f stacks/jenkins/docker-compose.yml build jenkins
docker-compose -f stacks/jenkins/docker-compose.yml push jenkins
docker stack deploy -c stacks/jenkins/docker-compose.yml jenkins
```
Enable DTR security scanning




## CICD
This repo will contain script and terraform files for:<br>
1 x UCP<br>
2 x workers that will also run 2 x DTR<br>
<br>
The mission is to have simple and reproducable instructions to be able to setup CICD.<br>
<br>
Workflow<br>
{git push} -> [git repo (github)] -- webhook --> Jenkins<br>
Jenkins starts to build the image, but only if the repo contains a /Dockerfile or /docker-compose and pushes the image to DTR<br>
<br>
DTR starts security scan of image and sends a webhook to Jenkins<br>
<br>
Jenkins deploys image via UCP<br>

