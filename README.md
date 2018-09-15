# cicd-workshop

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

This repo will contain script and terraform files for:

1 x UCP

2 x DTR



The mission is to have simple and reproducable instructions to be able to setup CICD.

Workflow

{git push} -> [git repo (guthub)] -- webhook --> Jenkins

Jenkins starts to build the image, but only if the repo contains a /Dockerfile or /docker-compose and pushes the image to DTR

DTR starts security scan of image and sends a webhook to Jenkins

Jenkins deploys image via UCP


