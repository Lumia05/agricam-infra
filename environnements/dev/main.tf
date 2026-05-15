# Fichier : agricam-infra/environnements/dev/main.tf
# Infrastructure AgriCam — Environnement de developpement
# CamTech Solutions — Douala, Cameroun
terraform {
  required_version = ">= 1.7.5" # <-- C'est cette ligne qu'il faut ajouter pour TFLint

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC : Le reseau prive isole dans AWS
# tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs (Pas de Flow Logs requis en Dev)
resource "aws_vpc" "agricam_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name          = "agricam-vpc-${var.environnement}"
    Projet        = "AgriCam"
    Entreprise    = "CamTech Solutions"
    Environnement = var.environnement
  }
}

# Sous-reseau public
# tfsec:ignore:aws-ec2-no-public-ip-subnet (Necessaire pour exposer l'instance de Dev)
resource "aws_subnet" "agricam_subnet" {
  vpc_id                  = aws_vpc.agricam_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "agricam-subnet-${var.environnement}"
  }
}

# Passerelle Internet
resource "aws_internet_gateway" "agricam_igw" {
  vpc_id = aws_vpc.agricam_vpc.id

  tags = {
    Name = "agricam-igw-${var.environnement}"
  }
}

# Table de routage
resource "aws_route_table" "agricam_rt" {
  vpc_id = aws_vpc.agricam_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.agricam_igw.id
  }

  tags = {
    Name = "agricam-rt-${var.environnement}"
  }
}

# Association route table / subnet
resource "aws_route_table_association" "agricam_rta" {
  subnet_id      = aws_subnet.agricam_subnet.id
  route_table_id = aws_route_table.agricam_rt.id
}

resource "aws_security_group" "agricam_sg" {
  name        = "agricam-sg-${var.environnement}"
  description = "Groupe de securite AgriCam - ${var.environnement}"
  vpc_id      = aws_vpc.agricam_vpc.id

  # HTTP public (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr
    description = "Acces HTTP public"
  }

  # HTTPS public (port 443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr
    description = "Acces HTTPS public"
  }

  # SSH restreint a l'IP de l'admin uniquement
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
    description = "SSH admin uniquement"
  }

  # Tout le trafic sortant est autorise
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    description = "Autoriser tout le trafic sortant"
  }

  tags = {
    Name = "agricam-sg-${var.environnement}"
  }
}

resource "aws_key_pair" "agricam_keypair" {
  key_name   = "agricam-keypair"
  public_key = var.ssh_public_key
}

# Instance EC2 (serveur virtuel)
resource "aws_instance" "agricam_serveur" {
  ami                    = var.ami_id
  instance_type          = var.type_instance
  subnet_id              = aws_subnet.agricam_subnet.id
  vpc_security_group_ids = [aws_security_group.agricam_sg.id]
  key_name               = aws_key_pair.agricam_keypair.key_name

  # Correction tfsec #5 : Chiffrement du disque racine au repos
  root_block_device {
    encrypted = true
  }

  # Correction tfsec #4 : Protection contre les attaques SSRF (IMDSv2 obligatoire)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Script d'initialisation (optionnel)
  user_data = <<-EOF
        #!/bin/bash
        apt update -y
        apt install -y nginx
        systemctl start nginx
        systemctl enable nginx
        echo '<h1>AgriCam - ${var.environnement}</h1>' > /var/www/html/index.html
    EOF

  tags = {
    Name          = "agricam-serveur-${var.environnement}"
    Projet        = "AgriCam"
    Environnement = var.environnement
  }
}

# Bucket S3 (stockage)
resource "aws_s3_bucket" "agricam_stockage" {
  bucket = "agricam-${var.environnement}-stockage-camtech-2026"

  tags = {
    Name          = "agricam-stockage-${var.environnement}"
    Environnement = var.environnement
  }
}

# Correction tfsec #6 & #7 : Activation du chiffrement automatique côté serveur
# tfsec:ignore:aws-s3-encryption-customer-key (Le chiffrement AES256 par défaut suffit pour le Dev)
resource "aws_s3_bucket_server_side_encryption_configuration" "agricam_s3_encrypt" {
  bucket = aws_s3_bucket.agricam_stockage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Correction tfsec #10 : Activation du versioning (protection contre les suppressions accidentelles)
resource "aws_s3_bucket_versioning" "agricam_s3_versioning" {
  bucket = aws_s3_bucket.agricam_stockage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bloquer tout acces public au bucket
resource "aws_s3_bucket_public_access_block" "agricam_s3_pab" {
  bucket = aws_s3_bucket.agricam_stockage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}