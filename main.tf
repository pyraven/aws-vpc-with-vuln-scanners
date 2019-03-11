# set up provider and region
provider "aws" {
  region = "${var.aws_region}"
}

# create elastic ip for nat gateway
resource "aws_eip" "elastic-ip" {}

# create vpc
resource "aws_vpc" "test" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name = "test-vpc"
  }
}

# create public subnet
resource "aws_subnet" "public-subnet" {
  vpc_id            = "${aws_vpc.test.id}"
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2b"

  tags {
    Name = "Scanner Public Subnet"
  }
}

# create private subnet
resource "aws_subnet" "private-subnet" {
  vpc_id            = "${aws_vpc.test.id}"
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"

  tags {
    Name = "Target Private Subnet"
  }
}

# create internet gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.test.id}"

  tags {
    Name = "VPC Internet Gateway"
  }
}

# create route table
resource "aws_route_table" "public-rt" {
  vpc_id = "${aws_vpc.test.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway.id}"
  }

  tags {
    Name = "Public Subnet Route Table"
  }
}

# create association
resource "aws_route_table_association" "public-rt-assoc" {
  subnet_id      = "${aws_subnet.public-subnet.id}"
  route_table_id = "${aws_route_table.public-rt.id}"
}

# create nat gateway
resource "aws_nat_gateway" "gw" {
  allocation_id = "${aws_eip.elastic-ip.id}"
  subnet_id     = "${aws_subnet.private-subnet.id}"

  tags = {
    Name = "NAT Gateway"
  }
}

# create target security group
resource "aws_security_group" "target_sg" {
  # all traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  vpc_id = "${aws_vpc.test.id}"
}

# create scanner security group #update your ips
resource "aws_security_group" "scanner_sg" {
  # ssh port
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ip_address}"]
  }

  # nessus port
  ingress {
    from_port   = 8834
    to_port     = 8834
    protocol    = "tcp"
    cidr_blocks = ["${var.ip_address}"]
  }

  # nexpose port
  ingress {
    from_port   = 3780
    to_port     = 3780
    protocol    = "tcp"
    cidr_blocks = ["${var.ip_address}"]
  }

  # all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.ip_address}"]
  }

  vpc_id = "${aws_vpc.test.id}"
}

# create redhat target
resource "aws_instance" "redhat_instance" {
  ami                         = "${var.red_hat_ami}"
  instance_type               = "t3.medium"
  vpc_security_group_ids      = ["${aws_security_group.target_sg.id}"]
  key_name                    = "${var.key_name}"
  associate_public_ip_address = false
  subnet_id                   = "${aws_subnet.private-subnet.id}"

  tags {
    Name = "RedHat Target"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 30
    delete_on_termination = true
  }
}

# nexpose scanner
resource "aws_instance" "nexpose_instance" {
  ami                         = "${var.red_hat_ami}"
  instance_type               = "t3.medium"
  vpc_security_group_ids      = ["${aws_security_group.scanner_sg.id}"]
  key_name                    = "${var.key_name}"
  subnet_id                   = "${aws_subnet.public-subnet.id}"
  associate_public_ip_address = true

  tags {
    Name = "Nexpose Scanner"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 50
    delete_on_termination = true
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = "${file("keys/testing-key.pem")}"
  }

  provisioner "file" {
    source      = "files/Rapid7Setup-Linux64.bin"
    destination = "/tmp/Rapid7Setup-Linux64.bin"
  }

  # update username and password
  provisioner "remote-exec" {
    inline = ["sudo yum update -y",
      "sudo chmod +x /tmp/./Rapid7Setup-Linux64.bin",
      "sudo /tmp/./Rapid7Setup-Linux64.bin -q -Vfirstname='Raven' -Vlastname='Crow' -Vcompany='Corvids International' -Vusername='myadmin' -Vpassword1='Y0uR_S3Cure_P@SSw0rd-H3rE' -Vpassword2='Y0uR_S3Cure_P@SSw0rd-H3rE'",
      "sudo systemctl start nexposeconsole",
    ]
  }
}

# nessus scanner
resource "aws_instance" "nessus_instance" {
  ami                         = "${var.red_hat_ami}"
  instance_type               = "t3.medium"
  vpc_security_group_ids      = ["${aws_security_group.scanner_sg.id}"]
  key_name                    = "${var.key_name}"
  subnet_id                   = "${aws_subnet.public-subnet.id}"
  associate_public_ip_address = true

  tags {
    Name = "Nessus Scanner"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 50
    delete_on_termination = true
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = "${file("keys/testing-key.pem")}"
  }

  # update filename as needed
  provisioner "file" {
    source      = "files/Nessus-8.2.3-es7.x86_64.rpm"
    destination = "/tmp/Nessus-8.2.3-es7.x86_64.rpm"
  }

  # update filename as needed
  provisioner "remote-exec" {
    inline = ["sudo yum update -y",
      "sudo rpm -ivh /tmp/Nessus-8.2.3-es7.x86_64.rpm",
      "sudo /bin/systemctl start nessusd.service",
    ]
  }
}
