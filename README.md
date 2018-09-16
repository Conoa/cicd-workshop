# cicd-workshop

## What is this?
This repo contains setup scripts for Conoa CICD workshop. <br>

## Todo
- [x] Terraform a docker swarm in AWS
- [ ] Simple copy n' paste for UCP + 2 DTR


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
Setup DTR-1 with 
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://54.93.166.245 \
  --ucp-node ip-10-0-6-14.cicd.conoa.se
```
Setup DTR-2 with 
```
docker run -it --rm docker/dtr:latest install \
  --ucp-insecure-tls \
  --ucp-password changeme \
  --ucp-username admin \
  --ucp-url https://54.93.166.245 \
  --ucp-node ip-10-0-6-132.cicd.conoa.se
```

## Jenkins



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

