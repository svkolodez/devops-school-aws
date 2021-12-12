
variable "whitelist" {
  type = list(string)
  default = ["0.0.0.0/0"]
}

variable "centos_image_id" {
  type = string
  default = "ami-08b6d44b4f6f7b279"
}

provider "aws" {
  profile = "default"
  region = "eu-central-1"
}

resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "eu-central-1a"

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "eu-central-1b"

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id
}

resource "aws_security_group" "http_https" {
  vpc_id      = aws_default_vpc.default.id
  name        = "http_https"
  description = "Allow HTTP(S) inbound 80/tcp 443/tcp"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = var.whitelist
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = var.whitelist
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_security_group" "ssh" {
  vpc_id      = aws_default_vpc.default.id
  name        = "ssh"
  description = "Allow SSH inbound 22/tcp"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = var.whitelist
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_security_group" "mysql" {
  vpc_id      = aws_default_vpc.default.id
  name        = "mysql"
  description = "Allow MySQL inbound 3306/tcp"
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = var.whitelist
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_elb" "wpelb" {
  name = "wpelb"
  subnets = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  security_groups = [aws_default_security_group.default.id, aws_security_group.http_https.id]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_efs_file_system" "wordpress" {
  creation_token   = "wordpress"
  performance_mode = "generalPurpose"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_db_instance" "wpdb" {
  name                   = "wpdb"
  identifier             = "wpdb"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  username               = "root"
  password               = "mypassword"
  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_default_security_group.default.id, aws_security_group.mysql.id]

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress"
  image_id      = var.centos_image_id
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_default_security_group.default.id, aws_security_group.http_https.id, aws_security_group.ssh.id, aws_elb.wpelb.source_security_group_id]

#  network_interfaces {
#    associate_public_ip_address = true
#  }

  user_data = filebase64("script.sh")

  depends_on = [aws_db_instance.wpdb]

  tags = {
    "Terraform" : "true"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  vpc_zone_identifier = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]

  desired_capacity = 2
  max_size         = 2
  min_size         = 1

  launch_template {
    id = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key = "Terraform"
    value = "true"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "wordpress" {
  autoscaling_group_name = aws_autoscaling_group.wordpress.id
  elb                    = aws_elb.wpelb.id
}
