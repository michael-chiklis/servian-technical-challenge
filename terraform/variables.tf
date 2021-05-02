variable "default_name" {
  description = "A default name used as a basis for naming resources"
}

variable "default_tags" {
  description = "Tags common to all resources"
}

variable "vpc_cidr" {
  description = "Subnet of the VPC in CIDR"
}

variable "region" {
  description = "AWS region"
}

variable "private_subnets" {
  description = "Private subnets"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnets"
  type        = list(string)
}

variable "database_subnets" {
  description = "Database subnets"
  type        = list(string)
}

variable "docker_image" {
  description = "Docker image"
}

variable "cpu" {
  description = "Containter CPU shares"
}

variable "memory" {
  description = "Container memory"
}
