# Testing and Validation

Regular DR testing is essential. Per the [AWS Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/test-disaster-recovery.html): "Test disaster recovery implementation to validate the implementation. Regularly test failover to your DR site to verify that it operates properly and that RTO and RPO are met."

!!! warning "Untested DR Plans Fail"
    A DR plan that has never been tested is not a DR plan. AWS recommends testing at minimum quarterly, with full failover tests at least annually.

---

## Testing Strategy Overview

| Test Type | Frequency | Scope | Risk | Duration |
| ----------- | ----------- | ------- | ------ | ---------- |
| **Tabletop Exercise** | Monthly | Discussion-based walkthrough | None | 1–2 hours |
| **Component Test** | Monthly | Individual service failover | Low | 1–4 hours |
| **Partial Failover** | Quarterly | Subset of services to DR | Medium | 4–8 hours |
| **Full Failover** | Annually | Complete failover to us-west-2 | High | 8–24 hours |
| **Chaos Engineering** | Ongoing | Inject failures in production | Variable | Continuous |

---

## Tabletop Exercise

A tabletop exercise is a discussion-based walkthrough where the team talks through the DR process without actually executing it.

### Agenda Template

1. **Scenario presentation** (10 min): Describe the disaster scenario (e.g., "us-east-1 is experiencing a complete regional outage")
2. **Detection** (15 min): How would we detect this? What alarms fire? Who gets notified?
3. **Decision** (15 min): Who decides to failover? What criteria? What's the escalation path?
4. **Execution** (30 min): Walk through each step of the failover runbook. Who does what?
5. **Validation** (15 min): How do we verify DR is working? What tests do we run?
6. **Communication** (10 min): Who communicates to customers? What channels?
7. **Failback** (15 min): When and how do we return to primary?
8. **Gaps and action items** (10 min): What did we discover? What needs to be fixed?

### Scenarios to Test

- [ ] Complete us-east-1 regional outage
- [ ] Single AZ failure in us-east-1
- [ ] Primary database corruption
- [ ] DNS failure
- [ ] Certificate expiration
- [ ] Accidental deletion of critical resources
- [ ] Security breach requiring region isolation

---

## Component Testing

Test each service's DR capability individually.

### Aurora Global Database Failover

```bash

# Check current global cluster status
aws rds describe-global-clusters \
    --global-cluster-identifier my-global-cluster \
    --query "GlobalClusters[0].GlobalClusterMembers[].{
        Cluster:DBClusterArn,
        IsWriter:IsWriter,
        State:GlobalWriteForwardingStatus
    }"

# Planned failover (managed, minimal downtime)
aws rds failover-global-cluster \
    --global-cluster-identifier my-global-cluster \
    --target-db-cluster-identifier arn:aws:rds:us-west-2:<account-id>:cluster:my-cluster-dr

# Monitor failover progress
watch -n 5 "aws rds describe-global-clusters \
    --global-cluster-identifier my-global-cluster \
    --query 'GlobalClusters[0].Status'"
```

### Validation after failover

```bash

# Verify us-west-2 is now the writer
aws rds describe-global-clusters \
    --global-cluster-identifier my-global-cluster \
    --query "GlobalClusters[0].GlobalClusterMembers[?IsWriter==\`true\`].DBClusterArn"

# Test write to new primary
psql -h my-cluster-dr.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U dbadmin -d mydb -c "INSERT INTO dr_test (test_time) VALUES (NOW());"

# Verify replication to old primary (now secondary)
psql -h my-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U dbadmin -d mydb -c "SELECT * FROM dr_test ORDER BY test_time DESC LIMIT 1;"
```

### Expected results

| Metric | Target | Actual |
| -------- | -------- | -------- |
| Failover time | < 1 minute | ___ |
| Data loss (RPO) | < 1 second | ___ |
| Write availability after failover | Immediate | ___ |

### DynamoDB Global Tables

```bash

# Write to us-east-1
aws dynamodb put-item --region us-east-1 \
    --table-name my-global-table \
    --item '{"pk":{"S":"dr-test"},"timestamp":{"S":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"},"region":{"S":"us-east-1"}}'

# Read from us-west-2 (should appear within ~1 second)
sleep 2
aws dynamodb get-item --region us-west-2 \
    --table-name my-global-table \
    --key '{"pk":{"S":"dr-test"}}' \
    --query "Item"
```

### S3 Cross-Region Replication

```bash

# Upload test object to source bucket
aws s3 cp test-dr-file.txt s3://my-primary-bucket/dr-test/ --region us-east-1

# Check replication status
aws s3api head-object \
    --bucket my-primary-bucket \
    --key dr-test/test-dr-file.txt \
    --query "ReplicationStatus"

# Expected: "COMPLETED"

# Verify object exists in DR bucket
aws s3api head-object \
    --bucket my-dr-bucket \
    --key dr-test/test-dr-file.txt \
    --region us-west-2
```

### Route 53 Failover

```bash

# Check health check status
aws route53 get-health-check-status \
    --health-check-id <health-check-id> \
    --query "HealthCheckObservations[].StatusReport.Status"

# Simulate failure: temporarily make primary unhealthy

# Option 1: Stop the primary ALB target group instances

# Option 2: Use Route 53 ARC to manually switch

# Using ARC routing control (data plane operation)
aws route53-recovery-cluster update-routing-control-state \
    --routing-control-arn arn:aws:route53-recovery-control::<account-id>:routingcontrol/<id> \
    --routing-control-state Off \
    --region us-west-2

# Verify DNS resolves to DR region
dig +short myapp.example.com

# Should return us-west-2 ALB IP
```

### ElastiCache Global Datastore

```bash

# Check replication status
aws elasticache describe-global-replication-groups \
    --global-replication-group-id my-global-redis \
    --query "GlobalReplicationGroup.Members[].{
        Group:ReplicationGroupId,
        Region:ReplicationGroupRegion,
        Role:Role,
        Status:Status
    }"

# Failover to DR
aws elasticache failover-global-replication-group \
    --global-replication-group-id my-global-redis \
    --primary-region us-west-2 \
    --primary-replication-group-id my-redis-dr
```

### EFS Replication

```bash

# Check replication status
aws efs describe-replication-configurations \
    --file-system-id fs-primary-xxxx \
    --region us-east-1 \
    --query "Replications[0].Destinations[0].{
        Status:Status,
        Region:Region,
        LastReplicatedTimestamp:LastReplicatedTimestamp
    }"
```

---

## Full Failover Test

### Pre-Test Preparation

- [ ] Schedule maintenance window and notify stakeholders
- [ ] Ensure all team members are available
- [ ] Verify DR region resources are in expected state
- [ ] Take snapshots/backups of all primary resources as safety net
- [ ] Prepare rollback plan
- [ ] Set up a shared communication channel (Slack, Teams)
- [ ] Assign roles: Incident Commander, Database Lead, Network Lead, Application Lead, Communications Lead

### Failover Execution Checklist

| Step | Action | Owner | Expected Time | Actual Time | Status |
| ------ | -------- | ------- | --------------- | ------------- | -------- |
| 1 | Announce failover test start | IC | 0 min | |
| 2 | Failover Aurora Global Database | DB Lead | < 1 min | |
| 3 | Verify Aurora writer in us-west-2 | DB Lead | 1 min | |
| 4 | Scale up EC2/ECS in us-west-2 | App Lead | 5 min | |
| 5 | Switch Route 53 / ARC to DR | Net Lead | 1 min | |
| 6 | Verify DNS resolves to us-west-2 | Net Lead | 2 min | |
| 7 | Run application smoke tests | App Lead | 5 min | |
| 8 | Verify data integrity | DB Lead | 10 min | |
| 9 | Monitor for 30 minutes | All | 30 min | |
| 10 | Announce failover test complete | IC | 0 min | |

### Validation During Full Failover

```bash

# Verify all services are healthy in us-west-2

# 1. Aurora - can write
psql -h <dr-cluster-endpoint> -U dbadmin -d mydb \
    -c "INSERT INTO dr_test VALUES (NOW(), 'full-failover-test');"

# 2. DynamoDB - can read/write
aws dynamodb put-item --region us-west-2 \
    --table-name my-table \
    --item '{"pk":{"S":"failover-test"},"data":{"S":"success"}}'

# 3. S3 - can read/write
aws s3 cp test.txt s3://my-dr-bucket/failover-test/ --region us-west-2

# 4. Application endpoints
curl -s https://myapp.example.com/health | jq .
curl -s https://myapp.example.com/api/v1/status | jq .

# 5. Check which region is serving traffic
curl -s https://myapp.example.com/api/v1/region

# Expected: us-west-2
```

### Metrics to Record

| Metric | Target | Actual | Pass/Fail |
| -------- | -------- | -------- | ----------- |
| Total failover time (RTO) | < ___ min | ___ min |
| Data loss (RPO) | < ___ sec | ___ sec |
| Aurora failover time | < 1 min | ___ |
| DNS propagation time | < 60 sec | ___ |
| Application availability after failover | 100% | ___ |
| Error rate during failover | < 1% | ___ |
| Compute scale-up time | < 5 min | ___ |

---

## Failback Test

After a successful failover test, validate the failback procedure:

### Failback Steps

1. **Re-establish replication** from us-west-2 (current primary) to us-east-1

    ```bash
    # For Aurora: failover global cluster back to us-east-1
    aws rds failover-global-cluster \
        --global-cluster-identifier my-global-cluster \
        --target-db-cluster-identifier arn:aws:rds:us-east-1:<account-id>:cluster:my-cluster
    ```

2. **Wait for replication to sync** — verify lag is zero

3. **Switch traffic back** to us-east-1

    ```bash
    # Using ARC routing control
    aws route53-recovery-cluster update-routing-control-state \
        --routing-control-arn arn:aws:route53-recovery-control::<account-id>:routingcontrol/<primary-id> \
        --routing-control-state On \
        --region us-west-2

    aws route53-recovery-cluster update-routing-control-state \
        --routing-control-arn arn:aws:route53-recovery-control::<account-id>:routingcontrol/<dr-id> \
        --routing-control-state Off \
        --region us-west-2
    ```

4. **Scale down DR region** compute resources

5. **Verify** primary region is serving traffic and DR is back to standby

---

## Chaos Engineering

Use [AWS Fault Injection Service (FIS)](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html) to inject controlled failures and validate resilience.

### Example FIS Experiments

### Terminate EC2 instances in primary region

```json
{
    "description": "Terminate 50% of EC2 instances in primary ASG",
    "targets": {
        "ec2Instances": {
            "resourceType": "aws:ec2:instance",
            "resourceTags": {"Environment": "production", "Region": "primary"},
            "selectionMode": "PERCENT(50)"
        }
    },
    "actions": {
        "terminateInstances": {
            "actionId": "aws:ec2:terminate-instances",
            "parameters": {},
            "targets": {"Instances": "ec2Instances"}
        }
    },
    "stopConditions": [
        {
            "source": "aws:cloudwatch:alarm",
            "value": "arn:aws:cloudwatch:us-east-1:<account-id>:alarm:HighErrorRate"
        }
    ]
}
```

### Inject Aurora cluster failover

```json
{
    "description": "Failover Aurora cluster",
    "targets": {
        "cluster": {
            "resourceType": "aws:rds:cluster",
            "resourceArns": ["arn:aws:rds:us-east-1:<account-id>:cluster:my-cluster"]
        }
    },
    "actions": {
        "failoverCluster": {
            "actionId": "aws:rds:failover-db-cluster",
            "targets": {"Clusters": "cluster"}
        }
    }
}
```

!!! tip "Start Small"
    Begin with non-production environments. Gradually increase scope and blast radius. Always have stop conditions (CloudWatch alarms) that automatically halt experiments if impact exceeds thresholds.

### Chaos Engineering Checklist

- [ ] Define steady-state hypothesis (what "normal" looks like)
- [ ] Start with tabletop: "What would happen if...?"
- [ ] Run experiment in staging first
- [ ] Set stop conditions (CloudWatch alarms)
- [ ] Run experiment in production during business hours with team on standby
- [ ] Measure impact on RTO/RPO
- [ ] Document findings and remediate gaps
- [ ] Repeat with increased scope

---

## AWS Resilience Hub

[AWS Resilience Hub](https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html) continuously validates and tracks the resilience of your workloads.

```bash

# Create an application in Resilience Hub
aws resiliencehub create-app \
    --name my-application \
    --assessment-schedule Daily

# Import resources
aws resiliencehub import-resources-to-draft-app-version \
    --app-arn <app-arn> \
    --source-arns '["arn:aws:cloudformation:us-east-1:<account-id>:stack/my-stack/*"]'

# Set resiliency policy (define RTO/RPO targets)
aws resiliencehub create-resiliency-policy \
    --policy-name production-policy \
    --tier MissionCritical \
    --policy '{
        "Software":{"rtoInSecs":300,"rpoInSecs":60},
        "Hardware":{"rtoInSecs":300,"rpoInSecs":60},
        "AZ":{"rtoInSecs":300,"rpoInSecs":60},
        "Region":{"rtoInSecs":3600,"rpoInSecs":300}
    }'

# Run assessment
aws resiliencehub start-app-assessment \
    --app-arn <app-arn> \
    --app-version published \
    --assessment-name quarterly-dr-assessment \
    --resiliency-policy-arn <policy-arn>
```

Resilience Hub will identify gaps between your target RTO/RPO and your actual architecture, and provide recommendations.

---

## Test Report Template

After each DR test, document results:

```markdown

# DR Test Report — [Date]

## Test Type: [Tabletop / Component / Partial / Full Failover]

## Participants: [Names and roles]

## Scenario: [Description of simulated disaster]

## Timeline
| Time | Event | Notes |
|------|-------|-------|
| HH:MM | Test started |
| HH:MM | Failover initiated |
| HH:MM | Services available in DR |
| HH:MM | Validation complete |
| HH:MM | Failback initiated |
| HH:MM | Test complete |

## Results
| Metric | Target | Actual | Pass/Fail |
|--------|--------|--------|-----------|
| RTO | |
| RPO | |

## Issues Found
1. [Issue description] — [Severity] — [Owner] — [Due date]

## Action Items
1. [Action] — [Owner] — [Due date]

## Lessons Learned
- [Key takeaway]
```
