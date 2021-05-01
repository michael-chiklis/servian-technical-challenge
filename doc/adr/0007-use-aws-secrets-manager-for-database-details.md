# 7. Use AWS Secrets Manager for database details

Date: 2021-05-01

## Status

Accepted

## Context

How can the application securely access the database details? 

## Decision

Use AWS Secrets Manager.

## Consequences

The application will need to be deployed in a manner which can integrate with AWS Secrets Manager.
