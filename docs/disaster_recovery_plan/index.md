# Disaster Recovery Plan: AWS Multi-Region (N. Virginia ↔ Oregon)

## Overview

This section is a comprehensive technical paper for designing, implementing, and operating a Disaster Recovery (DR) plan across two AWS Regions: us-east-1 (N. Virginia) as primary and us-west-2 (Oregon) as secondary/recovery. It follows the AWS Well-Architected Reliability Pillar and the AWS whitepaper 'Disaster Recovery of Workloads on AWS'.

The goal is to provide a single reference that any team can follow to achieve resilience for the most common AWS services.

## Key Definitions

| Term | Definition |
| ------ | ------------ |
| RPO (Recovery Point Objective) | Maximum acceptable data loss measured in time |
| RTO (Recovery Time Objective) | Maximum acceptable downtime |
| MTTR (Mean Time To Recovery) | Average time to restore service |
| Failover | Process of switching from primary to DR region |
| Failback | Process of returning to primary region after recovery |

## DR Strategies

Based on the [AWS whitepaper](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html):

| Strategy | RPO | RTO | Cost | Description |
| ---------- | ----- | ----- | ------ | ------------- |
| Backup & Restore | Hours | 24h+ | $ | Periodic backups to DR region, redeploy infra on failover |
| Pilot Light | Minutes | 10min-hours | $$ | Data continuously replicated, core infra provisioned but off |
| Warm Standby | Seconds | Minutes | $$$ | Scaled-down but fully functional copy running in DR |
| Multi-Site Active/Active | Near-zero | Near-zero | $$$$ | Full production in both regions serving traffic |

```text
Cost vs RTO/RPO Spectrum:

High Cost $$$$  ┌─────────────────┐ Multi-Site Active/Active
               │                 │
          $$$  │     ┌───────────┤ Warm Standby
               │     │           │
           $$  │ ┌───┤           │ Pilot Light
               │ │   │           │
Low Cost   $  ┌┤ │   │           │ Backup & Restore
             ├─┴─┴───┴───────────┤
           High              Low
         RTO/RPO          RTO/RPO
```

## Region Pair: us-east-1 ↔ us-west-2

| Attribute | Primary | DR/Secondary |
| ----------- | --------- | -------------- |
| Region | us-east-1 (N. Virginia) | us-west-2 (Oregon) |
| Availability Zones | 6 AZs | 4 AZs |
| Distance | ~3,700 km / ~2,300 miles |
| Network Latency | ~60-70ms inter-region |
| **Why this pair** | Both are large regions with full service availability, commonly used DR pair, cost-effective (Oregon is one of the cheapest regions) |

## Services Covered

| Category | Services |
| ---------- | ---------- |
| **Compute** | EC2, ECS/Fargate, Lambda |
| **Database** | RDS, Aurora, DynamoDB, ElastiCache |
| **Storage** | S3, EBS, EFS |
| **Networking** | Route 53, CloudFront, Global Accelerator, VPC |
| **Application Integration** | SQS, SNS, EventBridge |
| **Security** | IAM, Secrets Manager, KMS, ACM |
| **Management** | CloudFormation/CDK, CloudWatch, AWS Backup |
| **Containers** | ECR, EKS |

## Section Contents

| Document | Description |
| ---------- | ------------- |
| [Implementation Plan](implementation_plan.md) | Per-service DR configuration with architecture diagrams |
| [Checklist](checklist.md) | Complete pre/during/post DR checklist |
| [Step by Step](step_by_step.md) | AWS CLI commands to set up DR for each service |
| [Testing and Validation](testing_and_validation.md) | DR testing procedures, game days, chaos engineering |
| [Troubleshooting](troubleshooting.md) | Common DR issues and fixes |

## Key References

| Resource | URL |
| ---------- | ----- |
| AWS DR Whitepaper | <https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html> |
| AWS Well-Architected Reliability Pillar | <https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html> |
| AWS Resilience Hub | <https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html> |
| AWS Backup | <https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html> |
| Aurora Global Database | <https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html> |
| DynamoDB Global Tables | <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html> |
| S3 Cross-Region Replication | <https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html> |
| Route 53 Health Checks | <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html> |
| AWS Elastic Disaster Recovery | <https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html> |
| AWS Global Accelerator | <https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html> |
