provider "aws" {
  region = var.region
}

#
# VPC
#

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = "${var.default_name}-vpc"

  cidr                         = var.vpc_cidr
  azs                          = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets              = var.private_subnets
  public_subnets               = var.public_subnets
  database_subnets             = var.database_subnets
  enable_nat_gateway           = true
  create_database_subnet_group = true

  tags = var.default_tags
}

module "lb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name = "${var.default_name}-lb-sg"

  vpc_id = module.vpc.vpc_id

  # HTTP from anywhere
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  # Egress to VPC
  computed_egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = var.vpc_cidr
    }
  ]

  number_of_computed_egress_with_cidr_blocks = 1

  tags = var.default_tags
}

module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name = "${var.default_name}-app-sg"

  vpc_id = module.vpc.vpc_id

  # App access for ALB
  computed_ingress_with_source_security_group_id = [
    {
      from_port                = var.app_port
      to_port                  = var.app_port
      protocol                 = "tcp"
      description              = "App access from loadbalancers"
      source_security_group_id = module.lb_sg.security_group_id
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  # Egress anywhere to access AWS services
  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]

  tags = var.default_tags
}

module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4"

  name = "${var.default_name}-db-sg"

  vpc_id = module.vpc.vpc_id

  # DB access from app
  computed_ingress_with_source_security_group_id = [
    {
      from_port                = var.db_port
      to_port                  = var.db_port
      protocol                 = "tcp"
      description              = "DB access from app"
      source_security_group_id = module.app_sg.security_group_id
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  # Egress to VPC
  computed_egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = var.vpc_cidr
    }
  ]

  number_of_computed_egress_with_cidr_blocks = 1

  tags = var.default_tags
}

#
# DB password and secret
#

resource "random_password" "db_password" {
  length  = 32
  special = false
}

# AWS Secrets Manager Secrets are soft-deleted for a period, and reprovisioning one with the same
# name is not allowed. Prefix the secret with a random string to work around this.
resource "random_string" "prefix" {
  length  = 4
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${random_string.prefix.result}-${var.default_name}-db-password"

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

  engine                                = var.db_name
  engine_version                        = "13.2"
  family                                = "postgres13"
  major_engine_version                  = "13"
  instance_class                        = var.db_instance_size
  allocated_storage                     = 20
  max_allocated_storage                 = 100
  storage_encrypted                     = true
  username                              = var.db_name
  password                              = random_password.db_password.result
  port                                  = var.db_port
  multi_az                              = true
  subnet_ids                            = module.vpc.database_subnets
  vpc_security_group_ids                = [module.db_sg.security_group_id]
  maintenance_window                    = "Mon:00:00-Mon:03:00"
  backup_window                         = "03:00-06:00"
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  backup_retention_period               = 0
  skip_final_snapshot                   = true
  deletion_protection                   = false
  performance_insights_enabled          = false
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
# ALB
#

resource "aws_lb" "alb" {
  name = "${var.default_name}-lb"

  load_balancer_type         = "application"
  subnets                    = module.vpc.public_subnets
  security_groups            = [module.lb_sg.security_group_id]
  enable_deletion_protection = false

  tags = var.default_tags
}

resource "aws_lb_target_group" "target_group" {
  name = "${var.default_name}-tg"

  vpc_id      = module.vpc.vpc_id
  protocol    = "HTTP"
  port        = 80
  target_type = "ip"

  health_check {
    path = var.app_healthcheck
  }

  tags = var.default_tags
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

#
# ECS
#

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  name = "${var.default_name}-ecs"

  container_insights = true
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
    }
  ]

  tags = var.default_tags
}

resource "aws_cloudwatch_log_group" "seed_db" {
  name = "${var.default_name}-seed-db-logs"

  retention_in_days = var.log_retention_days

  tags = var.default_tags
}

resource "aws_cloudwatch_log_group" "app" {
  name = "${var.default_name}-app-logs"

  retention_in_days = var.log_retention_days

  tags = var.default_tags
}

# Assumed by ECS when executing an app task
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

  # Allows access to the DB password secret
  inline_policy {
    name = "${var.default_name}-app-role-elb-policy"

    policy = jsonencode({
      Version = "2012-10-17"

      Statement = [
        {
          Effect = "Allow"
          Resource : aws_secretsmanager_secret.db_password.arn
          Action = "secretsmanager:GetSecretValue"
        }
      ]
    })
  }

  tags = var.default_tags
}

# Base policy with permission to services like ELB and ECR
resource "aws_iam_role_policy_attachment" "ecs_execution_role" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# There are two task definitions - one for the app serving the site and one for a task to seed the
# DB. This variable contains the container definition common to both.
locals {
  common_container_definition = {
    image  = var.docker_image
    cpu    = var.cpu
    memory = var.memory

    environment = [
      {
        name  = "VTT_DBHOST"
        value = module.db.db_instance_address
      },
      {
        name  = "VTT_DBNAME"
        value = var.db_name
      }
    ]

    secrets = [
      {
        name      = "VTT_DBPASSWORD"
        valueFrom = aws_secretsmanager_secret.db_password.arn
      }
    ]
  }
}

resource "aws_ecs_task_definition" "seed_db" {
  family = "${var.default_name}-seed-db"

  execution_role_arn       = aws_iam_role.app_role.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory

  container_definitions = jsonencode([
    merge(local.common_container_definition, {
      name = "${var.default_name}-seed-db"

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = var.region
          awslogs-group         = aws_cloudwatch_log_group.seed_db.name
          awslogs-stream-prefix = "seed-db"
        }
      }

      command = ["updatedb", "--skip-create-db"]
    })
  ])

  tags = var.default_tags
}

resource "aws_ecs_task_definition" "app" {
  family = "${var.default_name}-app"

  execution_role_arn       = aws_iam_role.app_role.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory

  container_definitions = jsonencode([
    merge(local.common_container_definition, {
      name = "${var.default_name}-app"

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = var.region
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-stream-prefix = "app"
        }
      }

      command = ["serve"]

      portMappings = [
        {
          containerPort = var.app_port
        }
      ]
    })
  ])

  tags = var.default_tags
}

# This is the network configuration used in the awscli command to run the standalone seed task
locals {
  standalone_seed_task_network_config = {
    awsvpcConfiguration : {
      assignPublicIp = "DISABLED"
      subnets        = module.vpc.private_subnets
      securityGroups = [module.app_sg.security_group_id]
    }
  }
}

# Run the standalone seed task with awscli - there's no native way to do this in Terraform
resource "null_resource" "run_standalone_seed_task" {
  triggers = {
    db_address = module.db.db_instance_address
  }

  provisioner "local-exec" {
    # TODO script to check for task success
    # TODO move to separate file
    command = <<EOF
aws ecs run-task \
  --region='${var.region}' \
  --cluster='${module.ecs.ecs_cluster_name}' \
  --task-definition='${aws_ecs_task_definition.seed_db.family}:${aws_ecs_task_definition.seed_db.revision}' \
  --launch-type='FARGATE' \
  --started-by='Terraform' \
  --network-configuration='${jsonencode(local.standalone_seed_task_network_config)}'
EOF
  }
}

resource "aws_ecs_service" "app" {
  depends_on = [null_resource.run_standalone_seed_task]

  name                               = "${var.default_name}-app"
  cluster                            = module.ecs.ecs_cluster_id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_replicas
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [module.app_sg.security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "${var.default_name}-app"
    container_port         = var.app_port
  }

  capacity_provider_strategy {
    base              = 0
    capacity_provider = "FARGATE"
    weight            = 1
  }

  tags = var.default_tags

  # Prevents redeployment if the service has auto scaled
  lifecycle {
    ignore_changes = [desired_count]
  }
}

#
# Auto scaling
#

resource "aws_appautoscaling_target" "app" {
  min_capacity       = var.min_replicas
  max_capacity       = var.max_replicas
  resource_id        = "service/${module.ecs.ecs_cluster_name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "dev_to_memory" {
  name = "${var.default_name}-memory"

  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = var.autoscaling_mem_target
  }
}

resource "aws_appautoscaling_policy" "dev_to_cpu" {
  name = "${var.default_name}-cpu"

  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.autoscaling_cpu_target
  }
}
