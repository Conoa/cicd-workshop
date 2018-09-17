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
    mkdir /var/jenkins_home/jobs/

