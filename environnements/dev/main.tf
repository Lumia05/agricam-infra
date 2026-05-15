# Fichier : agricam-infra/environnements/dev/main.tf
# Infrastructure AgriCam — Environnement de developpement
# CamTech Solutions — Douala, Cameroun
terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

provider "aws" {
    region = var.aws_region
}

# VPC : Le reseau prive isole dans AWS
resource "aws_vpc" "agricam_vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "agricam-vpc-${var.environnement}"
        Projet = "AgriCam"
        Entreprise = "CamTech Solutions"
        Environnement = var.environnement
    }
}

# Sous-reseau public
resource "aws_subnet" "agricam_subnet" {
    vpc_id = aws_vpc.agricam_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "${var.aws_region}a"
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
    subnet_id = aws_subnet.agricam_subnet.id
    route_table_id = aws_route_table.agricam_rt.id
}

resource "aws_security_group" "agricam_sg" {
    name = "agricam-sg-${var.environnement}"
    description = "Groupe de securite AgriCam - ${var.environnement}"
    vpc_id = aws_vpc.agricam_vpc.id

# HTTP public (port 80)
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Acces HTTP public"
    }

# HTTPS public (port 443)
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Acces HTTPS public"
    }

# SSH restreint a l'IP de l'admin uniquement
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.ip_admin]
        description = "SSH admin uniquement"
    }

# Tout le trafic sortant est autorise
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}


resource "aws_key_pair" "agricam_keypair" {
    key_name = "agricam-keypair-${var.environnement}"
    public_key = file("~/.ssh/agricam_key.pub")
}

# Instance EC2 (serveur virtuel)
resource "aws_instance" "agricam_serveur" {
    ami = var.ami_id
    instance_type = var.type_instance
    subnet_id = aws_subnet.agricam_subnet.id
    vpc_security_group_ids = [aws_security_group.agricam_sg.id]
    key_name = aws_key_pair.agricam_keypair.key_name

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
        Name = "agricam-serveur-${var.environnement}"
        Projet = "AgriCam"
        Environnement = var.environnement
    }
}

# Bucket S3 (stockage)
resource "aws_s3_bucket" "agricam_stockage" {
    bucket = "agricam-${var.environnement}-stockage-camtech-2026"

    tags = {
        Name = "agricam-stockage-${var.environnement}"
        Environnement = var.environnement
    }
}

# Bloquer tout acces public au bucket
resource "aws_s3_bucket_public_access_block" "agricam_s3_pab" {
    bucket = aws_s3_bucket.agricam_stockage.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}