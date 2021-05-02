output "alb_domain" {
  value = aws_lb.alb.dns_name
}
