provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name               = "${var.default_name}-vpc"
  cidr               = var.vpc_cidr
  azs                = var.availability_zones
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  enable_nat_gateway = false

  tags = merge(
    var.default_tags,
    {
      "Name" = "${var.default_name}-vpc"
    },
  )
}
