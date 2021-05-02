# Servian Technical Challenge

## Prerequisites

- Docker
- Bash
- AWS Account

## Usage

You can either export your AWS credentials into your environment, or prepend any further commands
with them e.g.
```sh
$ export AWS_ACCESS_KEY_ID=<SNIP>
$ export AWS_SECRET_ACCESS_KEY=<SNIP>
```

This submission will deploy a single environment named `development`. You can review the
configurable parameters in `./terraform/development.tfvars` and `./terraform/variables.tf`. Most
parameters use the defaults specified in `./terraform/variables.tf`. If you wish to use a
non-default vaule, you can specify a value in `./terraform/development.tfvars`. The default network
might clash with other VPCs in your account - it's `10.0.0.0/16`.

Build a Terraform plan with the following command. This will also build and use a Docker container
containing Terraform and awscli. All that is required is Docker and to pass your AWS credentials
into the environment for this command:
```sh
$ ./scripts/terraform-plan-development
+++ Initializing Terraform
<SNIP>
+++ Running Docker image

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_appautoscaling_policy.dev_to_cpu will be created
  + resource "aws_appautoscaling_policy" "cpu" {

<SNIP>

Plan: 68 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + alb_domain = (known after apply)

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Saved the plan to: plans/development

To perform exactly these actions, run the following command to apply:
    terraform apply "plans/development"
```

After reviewing the Terraform plan, it can be applied with the following command:
```sh
$ ./scripts/terraform-apply-development
+++ Initializing Terraform
<SNIP>
+++ Running Docker image
random_password.db_password: Creating...
random_string.prefix: Creating...
random_password.db_password: Creation complete after 0s [id=none]
random_string.prefix: Creation complete after 0s [id=wxuS]
<SNIP>
aws_appautoscaling_policy.dev_to_memory: Creating...
aws_appautoscaling_policy.dev_to_cpu: Creating...
aws_appautoscaling_policy.dev_to_memory: Creation complete after 0s [id=servian-technical-challenge-memory]
aws_appautoscaling_policy.dev_to_cpu: Creation complete after 0s [id=servian-technical-challenge-cpu]

Apply complete! Resources: 68 added, 0 changed, 0 destroyed.

Outputs:

alb_domain = "servian-technical-challenge-lb-1938294554.ap-southeast-2.elb.amazonaws.com"
```
The application should be served on the output `alb_domain`. There is no HTTPS. It might also
take a moment to become healthy while the standalone DB seed task completes, but this is unlikely.

To destroy all resources, use the following command:
```sh
$ ./scripts/terraform-destroy-development
```
You will be prompted to confirm.

Here is a command I used to test the auto scaling. You will need to install `siege` and substitute
the output URL:
```sh
$ siege \
  -v \
  -b \
  -c50 \
  --content-type "application/json" \
  'http://servian-technical-challenge-lb-1258354833.ap-southeast-2.elb.amazonaws.com/api/task/ POST {"title":"","priority":1000,"completed":false,"id":0,"Title":"Test"}'
```

## TODO

- [x] Shellcheck scipt
- [x] Terraform scripts
- [x] VPC
- [x] RDS
- [x] AWS Secrets Manager secret for DB password
- [x] ECS seed standalone task
- [x] ECS app service
- [x] Autoscaling
- [x] Cleanup
- [x] Documentation

## Issues and next steps

- Domain name and SSL certificate
- Loadtest script
- Script to taint null-resource which runs the seed job
- Wait for the standalone seed DB task to complete before provisioning the app service
- Smoke test
- Splitting Terraform into modules
- CI/CD

## System design

- Application is deployed with RDS and ECS (Fargate)
- Database is seeded with a standalone ECS task
- Automation uses Terraform and AWS CLI
- See [the ADRs](doc/adr) for more details

### System diagram

![System diagram](doc/assets/system-diagram.png "Draft systems diagram")

[System diagram drawio source](doc/assets/system-diagram.drawio)

### Draft system diagram

![Draft system diagram](doc/assets/draft-system-diagram.jpeg "System diagram")
