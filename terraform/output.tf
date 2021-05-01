# TODO remove when finished
output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "alb_domain" {
  value = aws_lb.alb.dns_name
}
