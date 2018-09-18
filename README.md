# cicd-workshop

## What is this?
This repo contains setup scripts for Conoa CICD workshop. <br>

## Workshop workflow
1. Install docker
2. Install UCP + DTR på en maskin + 1 worker i dev
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

## Installera docker
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
cat << EOT >> .bashrc
export DOMAIN="cicd.k8s.se"
export ENV=${HOSTNAME%-*}
export UCP_FQDN="\${ENV}-ucp.\${DOMAIN}"
export DTR_FQDN="\${ENV}-dtr.\${DOMAIN}"
EOT
# exit
```
## Installera UCP i dev
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:latest install \
  --admin-username admin  \
  --admin-password changeme \
  --san ${UCP_FQDN} \
  --san ${DTR_FQDN} \
  --san ${ENV}-worker.${DOMAIN} \
  --controller-port 443 \
  --disable-tracking \
  --disable-usage
docker swarm join-token worker
```
### Installera DTR i dev
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://${DTR_FQDN} \
  --ucp-node ${ENV}-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://${DTR_FQDN}:4443
```
## Installera UCP i prod
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:latest install \
  --admin-username admin  \
  --admin-password changeme \
  --san ${UCP_FQDN} \
  --san ${DTR_FQDN} \
  --san ${ENV}-worker.${DOMAIN} \
  --controller-port 443 \
  --disable-tracking \
  --disable-usage
docker swarm join-token worker
```
### Installera DTR i prod
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://${DTR_FQDN} \
  --ucp-node ${ENV}-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://${DTR_FQDN}:4443
```

## Installera licenser
Görs i GUI

## Sätt upp layer 7 routing
admin -> admin settings -> layer 7 routing -> enable

## Sätt upp CA-trust i dev
```
sudo curl -k \
  https://${DTR_FQDN}:4443/ca \
  -o /etc/pki/ca-trust/source/anchors/${DTR_FQDN}:4443.crt
sudo update-ca-trust
sudo systemctl restart docker
sudo docker login -u admin ${DTR_FQDN}:4443
```

## Sätt upp CA-trust i prod
```
sudo curl -k \
  https://${DTR_FQDN}:4443/ca \
  -o /etc/pki/ca-trust/source/anchors/${DTR_FQDN}:4443.crt
sudo update-ca-trust
sudo systemctl restart docker
sudo docker login -u admin ${DTR_FQDN}:4443
```

## Skapa ett repo för jenkins image och ladda ner security database
1. http://dev-dtr.cicd.conoa.se:4443 -> new repo -> admin / jenkins
1. system -> security -> enable scaning + sync database

## Bygg jenkins
```
mkdir -p jenkins/build
cd jenkins
export UCP_FQDN="dev-ucp.cicd.conoa.se"
export DTR_FQDN="dev-dtr.cicd.conoa.se"
sudo curl -k \
  https://${DTR_FQDN}:4443/ca \
  -o /etc/pki/ca-trust/source/anchors/${DTR_FQDN}:4443.crt
sudo update-ca-trust
AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
source env.sh
docker login -u admin -p changeme https://${DTR_FQDN}:4443
```
Bygg jenkins i swarm
```
cd build
cat << EOT > Dockerfile
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
    mkdir /var/jenkins_home/jobs/ && \
    /usr/local/bin/install-plugins.sh generic-webhook-trigger github
EOT
docker build -t ${DTR_FQDN}:4443/admin/jenkins:latest .
cd ..
docker image push ${DTR_FQDN}:4443/admin/jenkins:latest
```

## Sätt upp jenkins som en service
Starta en jenkins container mha docker-compose.yml
```
cat << EOT > docker-compose.yml
version: '3.5'
services:
  jenkins:
    image: dev-dtr.cicd.conoa.se:4443/admin/jenkins
    deploy:
      placement:
        constraints: [node.role == worker]
      labels:
        com.docker.lb.hosts: dev-jenkins.cicd.conoa.se
        com.docker.lb.port: 8080
        com.docker.network: jenkins-network
    networks:
      - jenkins-network
networks:
  jenkins-network:
    driver: overlay
EOT
docker stack deploy -c docker-compose.yml jenkins
curl -I -H "host: dev-jenkins.cicd.conoa.se" http://dev-jenkins.cicd.conoa.se
```

## Skapa DTR repo i både dev och prod för vår kommande app
http://dev-dtr.cicd.conoa.se:4443 -> new repo -> admin / app
http://prod-dtr.cicd.conoa.se:4443 -> new repo -> admin / app

## Forka dops-final-project
1. https://github.com/docker-training/dops-final-project -> Fork
1. Gå in i det forkade repot och verifiera att allting "ser bra ut"

## Konfigurera ett build jobb i Jenkins
1. Skapa nytt item
1. Name: Byggjobb
1. Typ: Freestyle
1. OK
   1. Ta bort gamla byggen
      1.  Max byggen: 1
   1. SCM
      1. Git
      1. Repo URL: https://github.com/rjes/dops-final-project.git
   1. Build triggers
      1. Generic webhook trigger
      1. Post content parameters
         1. Variable: repoName
         1. Expression: $.repository.name
         1. Type: JSONPath
         1. Value filter: [^a-z]
      1. Request parameters
         1. Request parameter: repoName
         1. Value filter: [^a-z]
      1. token: 3Hkv0zarwg2YtS8i9v2v
      1. Cause: RepoBuild
   1. Build
      1. Add build step -> execute shell
      1. ```
         test -z ${repoName_0} && exit 1
         export UCP_FQDN="dev-ucp.cicd.k8s.se"
         export DTR_FQDN="dev-dtr.cicd.k8s.se:4443"
         export ImageName="app"
         AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
         curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
         export DOCKER_TLS_VERIFY=1 
         export COMPOSE_TLS_VERSION=TLSv1_2
         export DOCKER_CERT_PATH=$PWD
         export DOCKER_HOST=tcp://${UCP_FQDN}:443 
         docker login -u admin -p changeme https://${DTR_FQDN}
         docker build -t ${repoName_0}:${BUILD_ID} .
         docker tag ${repoName_0}:${BUILD_ID} ${DTR_FQDN}/admin/${repoName_0}:${BUILD_ID}
         docker push ${DTR_FQDN}/admin/${repoName_0}:${BUILD_ID}
         #docker tag ${repoName_0}:${BUILD_ID} ${DTR_FQDN}/admin/${repoName_0}:latest
         #docker push ${DTR_FQDN}/admin/${repoName_0}:latest
         ```
      1. Save or apply


## Konfigurera git repot
1. Konfigurera github
   1. Settings (https://github.com/rjes/dops-final-project/settings)
   1. Webhook URL: https://dev-jenkins.cicd.conoa.se/generic-webhook-trigger/invoke?token=3Hkv0zarwg2YtS8i9v2v
   1. Disable SSL verification
   1. Push event

 
## Kontrollera byggjobbet i Jenkins
1. Gå in i https://dev-jenkins.cicd.conoa.se/
1. Gå in i det aktuella bygget och klicka på "Console output"

## Kontrollera så imagen har skickats upp till DTR
1. Gå in på https://dev-dtr.cicd.k8s.se:4443
1. Klicka på repositories -> admin/app -> images

## Enable security scans för vårt app repo och promotions
1. repositories -> admin/app -> settings -> scan on push
1. save
1. repositories -> admin/app -> mirrors
   1. New mirror
   1. Registry URL: prod-dtr.cicd.k8s.se:4443
   1. Advanced -> add CA from `curl https://${DTR_FQDN}:4443/ca`
   1. Triggers
      1. Critical vulnerabilities: less than or equals 0
      1. Mirrored image's tag: %n
      1. Save and apply
1. Gå in i github och pusha en ny webhook
1. Gå tillbaka in i dev-dtr och visa att imagen scanas och att imagen har critical vulns och inte pushas till prod-dtr.
1. Ändra triggers för mirror så critical vulns är mindre än 20
1. Kör en webhook igen

## Webhook från prod-dtr för att produktionssätta applikationen
1. Logga in i prod-dtr
1. repositories -> admin/app -> webhooks
   1. Notifications to Receive: tag pushed to repo
   1. http://dev-jenkins.cicd.conoa.se/generic-webhook-trigger/invoke?token=PKosy4fD6YCyzBHktQJw
1. Logga in i http://dev-jenkins.cicd.k8s.se/
   1. Nytt jobb
      1. Name: DeployJob
      1. Type: Freestyle
   1. Generic Webhook Trigger
      1. Token: Kosy4fD6YCyzBHktQJw
   1. Build (shell commands)
      ```
         export UCP_FQDN="dev-ucp.cicd.k8s.se"
         export DTR_FQDN="dev-dtr.cicd.k8s.se:4443"
         AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
         curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
         export DOCKER_TLS_VERIFY=1 
         export COMPOSE_TLS_VERSION=TLSv1_2
         export DOCKER_CERT_PATH=$PWD
         export DOCKER_HOST=tcp://${UCP_FQDN}:443 
         docker login -u admin -p changeme https://${DTR_FQDN} && docker stack deploy -c docker-compose.yml app
      ```
   1. Apply and save


<a name="step11"><h3>Sätt upp ett github-repo med webhook mot vår test-dtr</h3></a>
<a name="step12"><h3>Skapa ett jenkins jobb som ska bygga vår test applikation, samt pusha till dev-DTR
<a name="step12"><h3>När en ny tag pushas in i dev-DTR så ska en säkerhetscan startas
<a name="step12"><h3>






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

