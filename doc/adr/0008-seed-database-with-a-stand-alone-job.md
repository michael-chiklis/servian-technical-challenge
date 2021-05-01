# 8. Seed database with a stand-alone job

Date: 2021-05-01

## Status

Accepted

## Context

How can the database be effectively and safely seeded? The seed command needs to be handled safely
as it will drop any existing tables.

## Decision

Seed the database as a stand-alone job after provisioning the database.

## Consequences

Infrastructure automation and/or app deployment services will be required to run this stand-alone
job.
