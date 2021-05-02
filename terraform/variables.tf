variable "default_name" {
  description = "A default name used as a basis for naming resources"
}

variable "default_tags" {
  description = "Tags common to all resources"
}

variable "vpc_cidr" {
  description = "Subnet of the VPC in CIDR"
  default     = "10.0.0.0/16"
}

variable "region" {
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "private_subnets" {
  description = "Private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnets" {
  description = "Database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

variable "docker_image" {
  description = "Docker image"
  default     = "servian/techchallengeapp:latest"
}

variable "app_healthcheck" {
  description = "App healthcheck path"
  default     = "/healthcheck/"
}

variable "cpu" {
  description = "Containter CPU shares"
  default     = 256
}

variable "memory" {
  description = "Container memory"
  default     = 512
}

variable "app_port" {
  description = "App port"
  default     = 3000
}

variable "db_port" {
  description = "DB port"
  default     = 5432
}

variable "db_name" {
  description = "RDS DB user and name"
  default     = "postgres"
}

variable "db_instance_size" {
  description = "RDS DB instance type"
  default     = "db.t3.small"
}

variable "desired_replicas" {
  description = "Desired replicas"
  default     = 2
}

variable "min_replicas" {
  description = "Min replicas"
  default     = 2
}

variable "max_replicas" {
  description = "Max replicas"
  default     = 2
}

variable "autoscaling_mem_target" {
  description = "Autoscaling memory target"
  default     = 20
}

variable "autoscaling_cpu_target" {
  description = "Autoscaling CPU target"
  default     = 20
}

variable "log_retention_days" {
  default     = 1
  description = "Number of days to retain logs"

}
