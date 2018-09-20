# cicd-workshop

## Överblick
1. Install docker
1. Install UCP + DTR på en maskin + 1 worker i dev
1. Install UCP + DTR på en maskin + 1 worker i prod
1. Lägg upp license i dev + prod
1. Enable Layer 7 Routing
1. Sätt upp CA-trust på alla 4 maskiner
1. Skapa repot admin/jenkins i dev-DTR
1. Bygg en Jenkins image och pusha till dev-dtr/admin/jenkins
1. Starta jenkins container i dev-worker
1. Skapa ett admin/app repo i dev och ett admin/app repo i prod
1. Sätt upp ett github-repo med webhook mot vår test-dtr
1. Skapa ett jenkins jobb som ska bygga vår test applikation, samt pusha till dev-DTR
1. När en ny tag pushas in i dev-DTR så ska en säkerhetscan startas
1. Promota en image från dev till prod

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
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:3.0.2 install \
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

## Installera UCP i prod
```
docker container run -it --rm --name=ucp -v /var/run/docker.sock:/var/run/docker.sock docker/ucp:3.0.2 install \
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

## Installera licenser
Logga in på store.docker.com och hämta ut en trial license.
Ladda upp licensen vid inloggning.

## Sätt upp layer 7 routing
admin -> admin settings -> layer 7 routing -> enable

### Installera DTR i dev
```
docker run -it --rm docker/dtr:2.5.5 install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://${UCP_FQDN} \
  --ucp-node ${ENV}-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://${DTR_FQDN}:4443
```
### Installera DTR i prod
```
docker run -it --rm docker/dtr:2.5.5 install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://${UCP_FQDN} \
  --ucp-node ${ENV}-ucp \
  --replica-https-port 4443 \
  --replica-http-port 81 \
  --dtr-external-url https://${DTR_FQDN}:4443
```

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
docker login -u admin ${DTR_FQDN}:4443
```

## Skapa ett repo för jenkins image och ladda ner security database
1. http://dev-dtr.cicd.k8s.se:4443 -> new repo -> admin / jenkins
1. system -> security -> enable scaning + sync database

## Konfigurera vår lokala klient för att kommunicera mot Docker Swarm
Vi vill inte prata med vår lokala docker daemon utan med vår swarm.

Med hjälp av client-bundle så kan vi kommunicera säkert med vår swarm, från både klient och servers perspektiv (Mutual SSL auth).
```
mkdir ucp-api && cd ucp-api
export UCP_FQDN="dev-ucp.cicd.k8s.se"
export DTR_FQDN="dev-dtr.cicd.k8s.se"
AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
source env.sh
docker login -u admin -p changeme dev-dtr.cicd.k8s.se:4443
docker info
```

## Bygg jenkins i swarm
```
mkdir -p jenkins/build
cd jenkins/build
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
docker image push ${DTR_FQDN}:4443/admin/jenkins:latest
```

## Sätt upp jenkins som en service
Starta en jenkins container mha docker-compose.yml
```
cat << EOT > docker-compose.yml
version: '3.0'
services:
  jenkins:
    image: dev-dtr.cicd.k8s.se:4443/admin/jenkins
    deploy:
      placement:
        constraints: [node.role == worker]
      labels:
        com.docker.lb.hosts: dev-jenkins.cicd.k8s.se
        com.docker.lb.port: 8080
        com.docker.lb.network: jenkins-network
    networks:
      - jenkins-network
networks:
  jenkins-network:
    driver: overlay
EOT
docker stack deploy -c docker-compose.yml jenkins
curl -I http://dev-jenkins.cicd.k8s.se
```

## Skapa DTR repo i både dev och prod för vår kommande app
http://dev-dtr.cicd.k8s.se:4443 -> new repo -> admin / app

http://prod-dtr.cicd.k8s.se:4443 -> new repo -> admin / app

## Kodrepo för vårt bygge (om det behövs)
1. https://github.com/docker-training/dops-final-project -> Fork
1. Gå in i det forkade repot och verifiera att allting "ser bra ut"

## Konfigurera ett build jobb i Jenkins
URL: http://dev-jenkins.cicd.k8s.se
1. Skapa nytt item
1. Name: BuildJob
1. Typ: Freestyle
1. OK
   1. Ta bort gamla byggen
      1.  Max byggen: 1
   1. SCM
      1. Git
      1. Repo URL: https://github.com/rjes/dops-final-project.git
   1. Build triggers
      1. Generic webhook trigger
      1. Request parameters
         1. Request parameter: `repoName`
         1. Value filter: `Empty/tomt`
      1. token: 3Hkv0zarwg2YtS8i9v2v
      1. Cause: BuildJob
   1. Build
      1. Add build step -> execute shell
      1. ```
         imageName=${repoName_0}
         test -z ${imageName} && exit 1
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
         docker build -t ${imageName}:${BUILD_ID} .
         docker tag ${imageName}:${BUILD_ID} ${DTR_FQDN}/admin/${imageName}:${BUILD_ID}
         docker push ${DTR_FQDN}/admin/${imageName}:${BUILD_ID}
         ```
      1. Save or apply


## Konfigurera git repot
1. Konfigurera github
   1. Settings (https://github.com/rjes/dops-final-project/settings)
   1. Webhook URL:
      1. URL: http://dev-jenkins.cicd.conoa.se/generic-webhook-trigger/invoke
      1. Query parameter: token=3Hkv0zarwg2YtS8i9v2v&repoName=app
   1. Disable SSL verification
   1. Push event

 
## Kontrollera byggjobbet i Jenkins
1. Gå in i https://dev-jenkins.cicd.k8s.se/
1. Gå in i det aktuella bygget och klicka på "Console output"

## Kontrollera så imagen har skickats upp till DTR
1. Gå in på https://dev-dtr.cicd.k8s.se:4443
1. Klicka på repositories -> admin/app -> images

## Enable security scans för vårt app repo och promotions
När en image inte har några critical vulnerabilities så promotas imagen till app-qa
1. repositories -> admin/app -> settings -> scan on push
1. save
1. skapa repo admin/app-qa
1. Sätt upp en promotion i app repot mot app-qa
   1. Critical Vulnerabilities: Less or equal 0
   1. Add
   1. Target repo: admin/app-qa
   1. tag-name: %n
   1. Save
1. Trigga en webhook från github
1. Det kommer ta c.a. 4 minuter att scana vår build.
1. Visa att vi inte får någon image i app-qa samt att ingen promotion har körts i app repot

## Promotion från QA till prod DTR
1. Ändra `app`repot's promotion
   1. Critical Vulnerabilities: Less or equal till 20
1. Trigga en ny webhook från github
1. Verifiera att den senaste builden hamnar i app-qa repot
1. Skapa ett nytt repo som används för att skeppa images mellan dev och prod.
   1. dev-dtr -> new repo -> admin/app-mirroring
   1. Sätt upp en ny mirror
      1. Registry URL: https prod-dtr.cicd.k8s.se:4443
      1. Advanced -> add CA from `curl https://${DTR_FQDN}:4443/ca`
      1. Repo: admin/app
      1. Save
      1. Vi lägger inte till några `triggers/filters` eftersom vi vill pusha allt när det väl har passerat QA
      1. Vi låter `tag name` vara som det är
1. Manuell promotion från `app-qa`
   1. Klicka på `view details` på en image
   1. Klicka på `promote`
   1. Target repository: `admin / app-mirroring`
   1. Tag name in target: `Build nummer`
   1. Gå in i `app-mirroring` repot och visa att det finns en image där nu samt att mirrors har körts
   1. Logga in i prod-dtr och visa att imagen finns

## Webhook från prod-dtr för att produktionssätta applikationen
1. Logga in i prod-dtr
1. repositories -> admin/app -> webhooks
   1. Notifications to Receive: tag pushed to repo
   1. http://dev-jenkins.cicd.k8s.se/generic-webhook-trigger/invoke?token=PKosy4fD6YCyzBHktQJw&imageName=app
1. Logga in i http://dev-jenkins.cicd.k8s.se/
   1. Nytt jobb
      1. Name: DeployJob
      1. Type: Freestyle
   1. SCM: `None`
   1. Generic Webhook Trigger
      1. Token: PKosy4fD6YCyzBHktQJw
      1. Post content parameters
         1. Variable: imageName
         1. Expression: $.contents.imageName
         1. JSONPath
         1. Value filter: ``
      1. Post content parameters
         1. Variable: repository
         1. Expression: $.contents.repository
         1. JSONPath
         1. Value filter: ``
   1. Build (shell commands)
      ```
      if [ -z ${imageName} ] || [ ${imageName} == "foo/bar:latest" ] ; then exit 0 ; fi
      export UCP_FQDN="prod-ucp.cicd.k8s.se"
      export DTR_FQDN="prod-dtr.cicd.k8s.se:4443"
      AUTHTOKEN=$(curl -sk -d '{"username":"admin","password":"changeme"}' https://${UCP_FQDN}/auth/login | cut -d\" -f4)
      curl -k -H "Authorization: Bearer $AUTHTOKEN" -s https://${UCP_FQDN}/api/clientbundle -o bundle.zip && unzip -o bundle.zip
      export DOCKER_TLS_VERIFY=1 
      export COMPOSE_TLS_VERSION=TLSv1_2
      export DOCKER_CERT_PATH=$PWD
      export DOCKER_HOST=tcp://${UCP_FQDN}:443 
      docker login -u admin -p changeme https://${DTR_FQDN}
      cat << EOT > docker-compose.yml
      version: "3.0"
      services:
        web:
          image: ${DTR_FQDN}/${imageName}
          deploy:
            labels:
              com.docker.lb.hosts: ourapp.cicd.k8s.se
              com.docker.lb.port: 3000
              com.docker.lb.network: ourapp-network
          networks:
            - ourapp-network
      networks:
        ourapp-network:
          driver: overlay
      EOT
      docker stack deploy -c docker-compose.yml ${repository}
      ```
   1. Apply and save
   1. Promotea en image från dev-DTR
   1. `curl -I http://ourapp.cicd.k8s.se`
   


