# cicd-workshop

This repo will contain script and terraform files for:
1 x UCP
2 x DTR

The mission is to have simple and reproducable instructions to be able to setup CICD.
Workflow
<git push> -> [git repo (guthub)] -- webhook --> Jenkins
Jenkins starts to build the image, but only if the repo contains a /Dockerfile or /docker-compose and pushes the image to DTR
DTR starts security scan of image and sends a webhook to Jenkins
Jenkins deploys image via UCP

