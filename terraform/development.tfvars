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

# AWS availability zones
availability_zones = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]

# Private subnets
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

# Public subnets
public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
