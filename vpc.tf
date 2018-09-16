data "aws_availability_zones" "available" {}

resource "aws_key_pair" "conoa-sshkey" {
  key_name = "Conoa"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/p3BYVooBZeuZY3ul/Fo7sjhqnqaLUNwJT7AAmqA66qaTVytuPcIhnEEVrX8gTTILImhGx4QNO8QAtB/Wpv64a6X0v0anGKOzl6/JSs1s95Nz8iDTRHM2ZSH/02UExrFljN2Tq106+yAk+7tRwhbE4ucUVJRtd7svGOk5SlVdLaHw8rUD67dzpRXcSM84FUaLO//cxViHMyQm49Wh/a1ofjhRoLmsZusGHW1M9f1CcWa32sign/xb8BX4Uwe1Xw4Lc01J2Roxx0o5Cre2ccn+oXFllR7X3no+5FXL3reiYngQM7zdYFNIAK12haCvs9RODotKCi5kp4gIr9aRPfVb Gemensam SSH nyckel"
}

resource "aws_vpc" "CICD-vpc" {
    cidr_block = "${var.vpc-cidr}"
    enable_dns_support = true
    enable_dns_hostnames = true
    tags {
      Name = "CICD"
      Owner = "Robert Söderlund"
    }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
}

resource "aws_eip" "NatIP" {
  vpc      = true
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
}

resource "aws_subnet" "public-cidr" {
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  cidr_block = "${var.public-cidr}"
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
  availability_zone = "${data.aws_availability_zones.available.names[0]}"
}

resource "aws_subnet" "private-cidr" {
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  cidr_block = "${var.private-cidr}"
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
  availability_zone = "${data.aws_availability_zones.available.names[1]}"
}

resource "aws_route_table_association" "public-cidr" {
  subnet_id = "${aws_subnet.public-cidr.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private-cidr" {
  subnet_id = "${aws_subnet.private-cidr.id}"
  route_table_id = "${aws_route_table.private.id}"
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = "${aws_eip.NatIP.id}"
  subnet_id = "${aws_subnet.public-cidr.id}"
  depends_on = ["aws_internet_gateway.igw"]
}

resource "aws_network_acl" "CICD-network-acl" {
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
  egress {
    protocol = "-1"
    rule_no = 1
    action = "allow"
    cidr_block =  "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }
  ingress {
    protocol = "-1"
    rule_no = 2
    action = "allow"
    cidr_block =  "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }
}

resource "aws_route_table" "public" {
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.igw.id}"
    }
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  tags {
    Name = "CICD"
    Owner = "Robert Söderlund"
  }
  route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = "${aws_nat_gateway.natgw.id}"
  }
}

resource "aws_vpc_dhcp_options" "CICD-dhcp" {
  domain_name = "${var.DnsZoneName}"
  domain_name_servers = ["AmazonProvidedDNS"]
}

resource "aws_vpc_dhcp_options_association" "dns_resolver" {
    vpc_id = "${aws_vpc.CICD-vpc.id}"
    dhcp_options_id = "${aws_vpc_dhcp_options.CICD-dhcp.id}"
}

resource "aws_route53_zone" "DnsZone" {
  name = "${var.DnsZoneName}"
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  comment = "Managed by terraform"
}

/*resource "aws_route53_record" "cicd_conoa_se" {
   zone_id = "${aws_route53_zone.DnsZone.zone_id}"
   name = "ucp01-a.${var.DnsZoneName}"
   type = "A"
   ttl = "300"
   records = ["${aws_instance.ucp01-a.public_ip}"]
}*/

resource "aws_security_group" "Public" {
  name = "Public"
  vpc_id = "${aws_vpc.CICD-vpc.id}"
  ingress {
    from_port = "80"  
    to_port = "80"
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = "443"
    to_port     = "443"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "managers" {
  count = "${var.Managers}"
  key_name = "manager-${count.index}"
  ami = "${lookup(var.CentOS7AMI, var.region)}"
  instance_type = "t3.xlarge"
  associate_public_ip_address = "true"
  subnet_id = "${aws_subnet.public-cidr.id}"
  vpc_security_group_ids = ["${aws_security_group.Public.id}"]
  key_name = "${aws_key_pair.conoa-sshkey.id}"
  tags {
    Role = "UCP01"
  }
  user_data = <<HEREDOC
  #!/bin/bash
  yum update -y
HEREDOC
  connection {
    user = "centos"
    private_key = "${file("./rsa_conoa")}"
    agent = false
  }
  provisioner "file" {
    source = "provisioning.sh"
    destination = "/home/centos/provisioning.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x provisioning.sh",
      "/home/centos/provisioning.sh",
      "sudo docker swarm init"
    ]
  }
}

resource "aws_instance" "workers" {
  count = "${var.Workers}"
  key_name = "worker-${count.index}"
  depends_on = ["aws_instance.managers"]
  ami = "${lookup(var.CentOS7AMI, var.region)}"
  instance_type = "t3.large"
  associate_public_ip_address = "true"
  subnet_id = "${aws_subnet.private-cidr.id}"
  vpc_security_group_ids = ["${aws_security_group.Public.id}"]
  key_name = "${aws_key_pair.conoa-sshkey.id}"
  tags {
    Role = "DTR01"
  }
  user_data = <<HEREDOC
  #!/bin/bash
  yum update -y
HEREDOC
  connection {
    type = "ssh"
    user = "centos"
    password = "${file("./rsa_conoa")}"
    agent = false
  }
  provisioner "file" {
    source = "provisioning.sh"
    destination = "/home/centos/provisioning.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x provisioning.sh",
      "/home/centos/provisioning.sh",
      "sudo docker swarm join ${aws_instance.managers.0.private_ip}:2377 --token $(docker -H ${aws_instance.managers.0.private_ip} swarm join-token -q worker)"
    ]
  }
}
