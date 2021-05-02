# A default name used as a basis for naming resources
default_name = "servian-technical-challenge"

# Tags common to all resources
default_tags = {
  Terraform   = "true"
  Environment = "development"
}

# Subnet of the VPC in CIDR
vpc_cidr = "10.0.0.0/16"

# AWS region
region = "ap-southeast-2"

# Private subnets
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

# Public subnets
public_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database subnets
database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

# Docker image
docker_image = "servian/techchallengeapp:latest"

# Containter CPU shares
cpu = 512

# Container memory
memory = 1024
