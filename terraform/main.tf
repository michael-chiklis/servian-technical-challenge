provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = "${var.default_name}-vpc"

  cidr             = var.vpc_cidr
  azs              = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  enable_nat_gateway           = true
  create_database_subnet_group = true

  tags = var.default_tags
}

module "lb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name        = "${var.default_name}-lb-sg"
  description = "Security group with HTTP port open for everyone"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]

  tags = var.default_tags
}

module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name        = "${var.default_name}-app-sg"
  description = "Security group for loadbalancers to access the app"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 3000
      to_port                  = 3000
      protocol                 = "tcp"
      description              = "App access from loadbalancers"
      source_security_group_id = module.lb_sg.security_group_id
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  tags = var.default_tags
}

module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name        = "${var.default_name}-db-sg"
  description = "Security group for the app to access the DB"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "DB access from app"
      source_security_group_id = module.app_sg.security_group_id
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  tags = var.default_tags
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "${var.default_name}-db"

  engine               = "postgres"
  engine_version       = "13.2"
  family               = "postgres13"
  major_engine_version = "13"
  instance_class       = "db.t3.small"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  name     = "app"
  username = "postgres"
  password = random_password.db_password.result
  port     = 5432

  multi_az               = true
  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [module.db_sg.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  backup_retention_period = 0
  skip_final_snapshot     = true  # FIXME
  deletion_protection     = false # FIXME

  performance_insights_enabled          = false # FIXME
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }
  db_subnet_group_tags = {
    "Sensitive" = "high"
  }

  tags = var.default_tags
}
