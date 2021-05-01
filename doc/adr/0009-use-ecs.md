# 9. Use ECS

Date: 2021-05-01

## Status

Accepted

## Context

What tools and services should be used to deploy the application?

## Decision

Use Amazon Elastic Container Service. This is since:
- The application is already published as a Docker image.
- The application is configurable via its environment.
- It is simpler and cheaper than Kubernetes.
- It is simpler than using EC2 in conjunction with cloud-init or Packer.
- It integrates with AWS Secrets Manager.
- It can run the database seed stand-alone job as a standalone ECS task.
- Supports auto scaling.
- Supports high availability deployments.

## Consequences

None.
