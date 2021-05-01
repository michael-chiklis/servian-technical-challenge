provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

#
# VPC
#

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

#
# DB password and secret
#

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.default_name}-db-password"

  # FIXME
  # policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Effect = "Allow"
  #       principal = {
  #         aws = aws_iam_role.app_role.arn
  #       },
  #       Action   = "secretsmanager:GetSecretValue"
  #       Resource = "*"
  #       Condition = {
  #         "ForAnyValue:StringEquals" = {
  #           "secretsmanager:VersionStage" = "AWSCURRENT"
  #         }
  #       }
  #     },
  #   ]
  # })

  tags = var.default_tags
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

#
# DB
#

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

#
# ECS
#

resource "aws_lb" "alb" {
  name                       = "${var.default_name}-lb"
  load_balancer_type         = "application"
  subnets                    = module.vpc.public_subnets
  security_groups            = [module.app_sg.security_group_id]
  enable_deletion_protection = false

  tags = var.default_tags
}

resource "aws_lb_target_group" "target_group" {
  name        = "${var.default_name}-tg"
  vpc_id      = module.vpc.vpc_id
  protocol    = "HTTP"
  port        = 80
  target_type = "ip"

  health_check {
    path = var.health_check_path
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  protocol          = "HTTP"
  port              = "80"

  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  name = "${var.default_name}-ecs"

  container_insights = true

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
    }
  ]

  tags = var.default_tags
}

resource "aws_cloudwatch_log_group" "seed_db" {
  name              = "${var.default_name}-seed-db-logs"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "${var.default_name}-app-logs"
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "seed_db" {
  family = "${var.default_name}-seed-db"

  execution_role_arn       = aws_iam_role.app_role.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024

  # FIXME use jsonencode
  container_definitions = <<EOF
[
  {
    "name": "${var.default_name}-seed-db",
    "image": "${var.docker_image}",
    "cpu": 512,
    "memory": 1024,
    "environment": [
      {
        "name": "VTT_DBHOST",
        "value" : "${module.db.db_instance_address}"
      }
    ],
    "secrets": [
      {
        "name": "VTT_DBPASSWORD",
        "valueFrom": "${aws_secretsmanager_secret.db_password.arn}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-region": "${var.region}",
        "awslogs-group": "${aws_cloudwatch_log_group.seed_db.name}",
        "awslogs-stream-prefix": "seed-db"
      }
    }
  }
]
EOF
}

resource "aws_ecs_task_definition" "app" {
  family = "${var.default_name}-app"

  execution_role_arn       = aws_iam_role.app_role.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024

  # FIXME use jsonencode
  container_definitions = <<EOF
[
  {
    "name": "${var.default_name}-app",
    "image": "${var.docker_image}",
    "cpu": 512,
    "memory": 1024,
    "portMappings": [
      {
        "containerPort": 3000
      }
    ],
    "environment": [
      {
        "name": "VTT_DBHOST",
        "value" : "${module.db.db_instance_address}"
      }
    ],
    "secrets": [
      {
        "name": "VTT_DBPASSWORD",
        "valueFrom": "${aws_secretsmanager_secret.db_password.arn}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-region": "${var.region}",
        "awslogs-group": "${aws_cloudwatch_log_group.app.name}",
        "awslogs-stream-prefix": "app"
      }
    }
  }
]
EOF
}

resource "aws_iam_role" "app_role" {
  name = "${var.default_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "${var.default_name}-app-role-elb-policy"

    policy = jsonencode({
      Version = "2012-10-17"

      Statement = [
        {
          Effect = "Allow",
          Action = "secretsmanager:GetSecretValue",
          Resource: aws_secretsmanager_secret.db_password.arn
        },
        {
          Effect = "Allow",
          Action = "kms:Decrypt",
          Resource: "*" # FIXME
        }
      ]
    })
  }
}

resource "aws_ecs_service" "app" {
  name            = "${var.default_name}-app"
  cluster         = module.ecs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  # iam_role        = aws_iam_role.app_role.arn

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [module.app_sg.security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "${var.default_name}-app"
    container_port   = 3000
  }

  desired_count = 2

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
}
