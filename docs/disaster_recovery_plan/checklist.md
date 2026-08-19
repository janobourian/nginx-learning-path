# Disaster Recovery Checklist

This comprehensive disaster recovery checklist follows AWS Well-Architected Reliability Pillar principles and AWS Disaster Recovery whitepaper best practices for multi-region deployment across us-east-1 (primary) and us-west-2 (DR).

## Pre-Implementation (Design Phase)

### Business Requirements

- [ ] Define RPO and RTO per workload/application
- [ ] Classify workloads by criticality (Tier 1/2/3)
- [ ] Choose DR strategy per tier
- [ ] Document acceptable data loss and downtime
- [ ] Get stakeholder sign-off
- [ ] Estimate DR cost using AWS Pricing Calculator

### Architecture

- [ ] Design mirrored VPC in us-west-2
- [ ] Plan IP addressing (non-overlapping CIDRs if peering)
- [ ] Design Route 53 failover routing
- [ ] Plan DNS TTL strategy
- [ ] Design database replication topology
- [ ] Plan storage replication strategy
- [ ] Design compute scaling strategy for DR region
- [ ] Document all regional service dependencies

## Infrastructure Setup

### Networking

- [ ] Create VPC in us-west-2
- [ ] Create subnets, route tables, NAT gateways
- [ ] Set up VPC peering or Transit Gateway
- [ ] Configure Route 53 health checks
- [ ] Configure Route 53 failover routing policies
- [ ] Set up Global Accelerator (if used)
- [ ] Configure CloudFront origin failover
- [ ] Verify inter-region connectivity and latency

### Compute

- [ ] Set up AMI cross-region copy pipeline
- [ ] Create launch templates in us-west-2
- [ ] Create Auto Scaling groups in us-west-2 (scaled down)
- [ ] Deploy ECS task definitions in us-west-2
- [ ] Set up ECR replication to us-west-2
- [ ] Deploy Lambda functions to us-west-2
- [ ] Configure Elastic Disaster Recovery (if used)

### Database

- [ ] Create Aurora Global Database with secondary in us-west-2
- [ ] Create RDS cross-region read replicas
- [ ] Enable DynamoDB Global Tables
- [ ] Set up ElastiCache Global Datastore
- [ ] Verify replication lag < acceptable threshold
- [ ] Test database failover procedure

### Storage

- [ ] Enable S3 Cross-Region Replication
- [ ] Enable S3 Replication Time Control (if RPO < 15 min needed)
- [ ] Configure EBS snapshot cross-region copy via AWS Backup
- [ ] Set up EFS replication to us-west-2
- [ ] Verify replication is active and healthy

### Security

- [ ] Replicate Secrets Manager secrets to us-west-2
- [ ] Create Multi-Region KMS keys
- [ ] Request/import ACM certificates in us-west-2
- [ ] Verify IAM roles exist for DR region resources
- [ ] Verify security groups and NACLs in DR VPC

### Application Integration

- [ ] Create SQS queues in us-west-2
- [ ] Create SNS topics in us-west-2
- [ ] Configure EventBridge cross-region rules
- [ ] Verify application can switch to DR endpoints

### Monitoring & Alerting

- [ ] Set up CloudWatch alarms in us-west-2
- [ ] Create cross-region CloudWatch dashboard
- [ ] Configure SNS notifications for DR events
- [ ] Set up AWS Backup plans with cross-region copy
- [ ] Verify backup vault exists in us-west-2

### Infrastructure as Code

- [ ] Deploy CloudFormation StackSets to both regions
- [ ] Verify DR region stack is in correct state (scaled down)
- [ ] Store IaC templates in version control
- [ ] Document manual steps not covered by IaC

## DR Testing

- [ ] Schedule regular DR tests (quarterly minimum)
- [ ] Run tabletop exercise with all teams
- [ ] Run failover test to us-west-2
- [ ] Verify all services are functional in DR region
- [ ] Measure actual RTO and RPO during test
- [ ] Verify failback procedure works
- [ ] Document test results and gaps
- [ ] Update runbooks based on findings

## During a DR Event (Failover)

- [ ] Confirm the disaster (not a false alarm)
- [ ] Notify stakeholders and initiate communication plan
- [ ] Execute failover runbook
- [ ] Promote Aurora secondary to primary
- [ ] Promote RDS read replicas
- [ ] Scale up compute in us-west-2
- [ ] Verify Route 53 / Global Accelerator routes traffic to DR
- [ ] Verify all services are healthy in DR region
- [ ] Monitor application logs and metrics
- [ ] Communicate status to stakeholders

## Post-Failover (Running in DR)

- [ ] Monitor DR region performance
- [ ] Verify data integrity
- [ ] Keep primary region resources for failback
- [ ] Document timeline of events
- [ ] Plan failback when primary is restored

## Failback (Return to Primary)

- [ ] Verify primary region is healthy
- [ ] Re-establish data replication from DR to primary
- [ ] Wait for replication to catch up
- [ ] Execute failback (reverse of failover)
- [ ] Verify all services healthy in primary
- [ ] Switch traffic back to primary
- [ ] Verify DR region returns to standby state
- [ ] Conduct post-incident review
- [ ] Update DR plan based on lessons learned
