# Troubleshooting

Common issues encountered when implementing and operating DR across us-east-1 and us-west-2, with solutions based on official AWS documentation.

---

## Networking Issues

### Route 53 Failover Not Triggering

| Cause | Diagnosis | Fix |
| ------- | ----------- | ----- |
| Health check not failing | Check health check status in Route 53 console | Verify health check endpoint, port, path, and protocol |
| TTL too high | `dig +short myapp.example.com` returns stale IP | Reduce TTL to 60 seconds for failover records |
| Client DNS caching | Clients still resolve to old IP after failover | TTL is a suggestion; some resolvers ignore it. Use Global Accelerator for instant failover |
| Health check threshold too high | Health check requires multiple failures before marking unhealthy | Reduce failure threshold (default 3) or request interval (default 30s) |
| Failover record misconfigured | Check record set type and routing policy | Ensure primary has `Failover: PRIMARY` and secondary has `Failover: SECONDARY` |

```bash

# Check health check status
aws route53 get-health-check-status \
    --health-check-id <id> \
    --query "HealthCheckObservations[].{
        Region:Region,
        Status:StatusReport.Status,
        CheckedTime:StatusReport.CheckedTime
    }"

# List failover records
aws route53 list-resource-record-sets \
    --hosted-zone-id <zone-id> \
    --query "ResourceRecordSets[?Type=='A' && Failover!=null]"
```

!!! tip "Use Data Plane for Failover"
    Per the [AWS DR whitepaper](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html): "For maximum resiliency, you should use only data plane operations as part of your failover operation." Route 53 health checks and ARC routing controls are data plane operations. Changing DNS records or traffic dials are control plane operations.

### Global Accelerator Not Routing to DR

| Cause | Fix |
| ------- | ----- |
| DR endpoint group health check failing | Verify DR ALB/NLB is healthy and targets are registered |
| Traffic dial set to 0 for DR | Set traffic dial to 100 for DR endpoint group |
| Endpoint weight is 0 | Set endpoint weight > 0 |

```bash

# Check endpoint group health
aws globalaccelerator describe-endpoint-group \
    --endpoint-group-arn <arn> \
    --query "{
        Region:EndpointGroupRegion,
        HealthCheckPort:HealthCheckPort,
        HealthCheckPath:HealthCheckPath,
        TrafficDialPercentage:TrafficDialPercentage
    }"

# Update traffic dial to send all traffic to DR
aws globalaccelerator update-endpoint-group \
    --endpoint-group-arn <dr-endpoint-group-arn> \
    --traffic-dial-percentage 100
```

### VPC Peering Routes Missing

```bash

# Verify peering connection is active
aws ec2 describe-vpc-peering-connections \
    --filters "Name=status-code,Values=active" \
    --query "VpcPeeringConnections[].{
        Id:VpcPeeringConnectionId,
        Requester:RequesterVpcInfo.{VpcId:VpcId,Region:Region},
        Accepter:AccepterVpcInfo.{VpcId:VpcId,Region:Region}
    }"

# Check route tables have peering routes
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=<vpc-id>" \
    --query "RouteTables[].Routes[?VpcPeeringConnectionId!=null]"
```

---

## Database Issues

### Aurora Global Database Failover Fails

| Cause | Fix |
| ------- | ----- |
| Secondary cluster not healthy | Check cluster status: `aws rds describe-db-clusters --region us-west-2` |
| Replication lag too high | Wait for lag to decrease; check `AuroraGlobalDBReplicationLag` metric |
| Global cluster in `failing-over` state | Wait for previous failover to complete |
| Insufficient capacity in DR region | Ensure DB instance class is available in us-west-2 |

```bash

# Check global cluster status
aws rds describe-global-clusters \
    --global-cluster-identifier my-global-cluster \
    --query "GlobalClusters[0].{
        Status:Status,
        Members:GlobalClusterMembers[].{
            Cluster:DBClusterArn,
            IsWriter:IsWriter
        }
    }"

# Check replication lag
aws cloudwatch get-metric-statistics \
    --namespace "AWS/RDS" \
    --metric-name "AuroraGlobalDBReplicationLag" \
    --dimensions Name=DBClusterIdentifier,Value=my-cluster-dr \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Average \
    --region us-west-2
```

### Managed planned failover vs unplanned failover

| Type | Command | Use Case | Data Loss |
|------|---------|----------|-----------|
| Managed planned | `aws rds failover-global-cluster` | DR testing, planned maintenance | None (waits for sync) |
| Unplanned (detach + promote) | `aws rds remove-from-global-cluster` then promote | Primary region is down | Possible (up to replication lag) |

!!! warning "Unplanned Failover"
    If us-east-1 is completely unavailable, you cannot use `failover-global-cluster`. Instead, detach the secondary cluster from the global cluster and promote it. This may result in data loss equal to the replication lag at the time of failure.

```bash

# Unplanned failover: detach secondary and promote
aws rds remove-from-global-cluster \
    --global-cluster-identifier my-global-cluster \
    --db-cluster-identifier arn:aws:rds:us-west-2:<account-id>:cluster:my-cluster-dr \
    --region us-west-2

# The detached cluster automatically becomes a standalone read/write cluster
```

### DynamoDB Global Table Replication Lag

```bash

# Check replication lag
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DynamoDB" \
    --metric-name "ReplicationLatency" \
    --dimensions Name=TableName,Value=my-global-table \
                 Name=ReceivingRegion,Value=us-west-2 \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Average \
    --region us-east-1
```

| Cause | Fix |
| ------- | ----- |
| High write throughput exceeding capacity | Increase WCU or switch to on-demand capacity |
| Large items (> 400 KB) | Optimize item size; store large data in S3 |
| Throttling | Check `ThrottledRequests` metric; increase capacity |

### RDS Read Replica Promotion Takes Too Long

Per [RDS documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html): promoting a cross-region read replica involves a reboot and can take several minutes.

```bash

# Promote read replica
aws rds promote-read-replica \
    --db-instance-identifier my-rds-dr-replica \
    --region us-west-2

# Monitor promotion status
watch -n 10 "aws rds describe-db-instances \
    --db-instance-identifier my-rds-dr-replica \
    --region us-west-2 \
    --query 'DBInstances[0].{Status:DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier:ReadReplicaSourceDBInstanceIdentifier}'"
```

!!! tip "Use Aurora Global Database Instead"
    Aurora Global Database failover is < 1 minute with managed planned failover. RDS read replica promotion can take 5–15 minutes. If RTO < 5 minutes is required, use Aurora.

### ElastiCache Global Datastore Failover Fails

```bash

# Check global datastore status
aws elasticache describe-global-replication-groups \
    --global-replication-group-id my-global-redis \
    --query "GlobalReplicationGroup.{
        Status:Status,
        Members:Members[].{
            Id:ReplicationGroupId,
            Region:ReplicationGroupRegion,
            Role:Role,
            Status:Status
        }
    }"
```

| Cause | Fix |
| ------- | ----- |
| Secondary not in `associated` status | Wait for association to complete |
| Insufficient node capacity in DR | Verify node type is available in us-west-2 |
| Global datastore in `modifying` state | Wait for current operation to complete |

---

## Storage Issues

### S3 Replication Not Working

```bash

# Check replication configuration
aws s3api get-bucket-replication \
    --bucket my-primary-bucket \
    --query "ReplicationConfiguration.Rules[].{
        Id:ID,
        Status:Status,
        Destination:Destination.Bucket
    }"

# Check replication metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/S3" \
    --metric-name "ReplicationLatency" \
    --dimensions Name=SourceBucket,Value=my-primary-bucket \
                 Name=DestinationBucket,Value=my-dr-bucket \
                 Name=RuleId,Value=my-replication-rule \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

| Cause | Fix |
| ------- | ----- |
| Versioning not enabled | Enable versioning on both source and destination buckets |
| IAM role missing permissions | Verify replication role has `s3:GetReplicationConfiguration`, `s3:ReplicateObject`, `s3:ReplicateDelete` |
| KMS key not accessible in DR region | Use multi-region KMS key or grant cross-region access |
| Replication rule status is `Disabled` | Enable the rule: `aws s3api put-bucket-replication` |
| Objects uploaded before replication was enabled | Replication only applies to new objects; use S3 Batch Replication for existing objects |

### EFS Replication Lag High

```bash

# Check replication status
aws efs describe-replication-configurations \
    --file-system-id fs-xxxx \
    --region us-east-1 \
    --query "Replications[0].Destinations[0].{
        Status:Status,
        LastReplicatedTimestamp:LastReplicatedTimestamp
    }"
```

| Cause | Fix |
| ------- | ----- |
| High write throughput on source | EFS replication RPO is ~15 minutes; this is expected |
| Replication status is `Error` | Check EFS service events; may need to delete and recreate replication |
| Large number of small files | EFS replication is optimized for throughput, not file count |

### AWS Backup Cross-Region Copy Fails

```bash

# Check backup job status
aws backup list-copy-jobs \
    --by-state FAILED \
    --region us-west-2 \
    --query "CopyJobs[].{
        ResourceArn:ResourceArn,
        Status:State,
        StatusMessage:StatusMessage,
        CreationDate:CreationDate
    }"
```

| Cause | Fix |
| ------- | ----- |
| Backup vault doesn't exist in DR region | Create vault: `aws backup create-backup-vault --backup-vault-name my-vault --region us-west-2` |
| KMS key not accessible in DR region | Use multi-region KMS key or create a key in DR region and specify in copy action |
| IAM role missing permissions | Verify backup role has `backup:CopyIntoBackupVault` permission |
| Service quota exceeded | Check backup vault limits in DR region |

---

## Compute Issues

### Auto Scaling Group Not Scaling Up in DR

```bash

# Check ASG status
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names my-asg-dr \
    --region us-west-2 \
    --query "AutoScalingGroups[0].{
        MinSize:MinSize,
        MaxSize:MaxSize,
        DesiredCapacity:DesiredCapacity,
        Instances:Instances[].{Id:InstanceId,State:LifecycleState}
    }"
```

| Cause | Fix |
| ------- | ----- |
| Desired capacity still at 0 | Update: `aws autoscaling update-auto-scaling-group --desired-capacity N` |
| Launch template AMI not available in DR | Copy AMI to us-west-2 before failover |
| Instance type not available in DR AZs | Use multiple instance types in launch template |
| Service quota insufficient | Request quota increase for DR region in advance |
| Subnet has no available IPs | Use larger subnets or add more subnets |

!!! warning "Service Quotas"
    Per [AWS DR whitepaper](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html): "Ensure that service quotas in your DR Region are set high enough so as to not limit you from scaling up to production capacity."

```bash

# Check EC2 instance quota in DR region
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-1216C47A \
    --region us-west-2 \
    --query "Quota.{Name:QuotaName,Value:Value}"
```

### ECR Images Not Available in DR

```bash

# Check ECR replication status
aws ecr describe-registry \
    --region us-east-1 \
    --query "ReplicationConfiguration.Rules[].Destinations"

# Verify image exists in DR
aws ecr describe-images \
    --repository-name my-app \
    --region us-west-2 \
    --query "imageDetails[0].{Tags:imageTags,PushedAt:imagePushedAt}"
```

| Cause | Fix |
| ------- | ----- |
| Replication not configured | `aws ecr put-replication-configuration` |
| Repository doesn't exist in DR | ECR replication auto-creates repos; verify replication rule |
| Image too large / timeout | Check ECR service limits; retry |

### ECS Service Won't Start in DR

| Cause | Fix |
| ------- | ----- |
| Task definition not registered in DR | Register task definition in us-west-2 |
| ECR image not available | Verify ECR replication (see above) |
| Secrets Manager secrets not replicated | Replicate secrets to us-west-2 |
| Security group / subnet misconfigured | Verify VPC, subnets, and SGs exist in DR |
| Service-linked role missing | First ECS use in a region requires role creation |

---

## Security Issues

### KMS Multi-Region Key Not Working in DR

```bash

# Verify replica key exists
aws kms describe-key \
    --key-id mrk-xxxx \
    --region us-west-2 \
    --query "KeyMetadata.{
        KeyId:KeyId,
        MultiRegion:MultiRegion,
        MultiRegionKeyType:MultiRegionConfiguration.MultiRegionKeyType,
        Enabled:Enabled
    }"
```

| Cause | Fix |
| ------- | ----- |
| Replica key not created | `aws kms replicate-key --key-id mrk-xxxx --replica-region us-west-2` |
| Key is disabled | `aws kms enable-key --key-id mrk-xxxx --region us-west-2` |
| Key policy doesn't allow DR region services | Update key policy to allow services in us-west-2 |

### Secrets Manager Secret Not Available in DR

```bash

# Check secret replication
aws secretsmanager describe-secret \
    --secret-id my-secret \
    --region us-east-1 \
    --query "ReplicationStatus[].{Region:Region,Status:Status}"
```

| Cause | Fix |
| ------- | ----- |
| Replication not configured | `aws secretsmanager replicate-secret-to-regions --secret-id my-secret --add-replica-regions '[{"Region":"us-west-2"}]'` |
| Replication status is `Failed` | Check KMS key availability in DR; delete and re-replicate |
| Secret value out of sync | Replication is automatic; check for replication errors |

### ACM Certificate Not Available in DR

ACM certificates are regional. They cannot be replicated.

```bash

# Request new certificate in DR region
aws acm request-certificate \
    --domain-name myapp.example.com \
    --subject-alternative-names "*.myapp.example.com" \
    --validation-method DNS \
    --region us-west-2
```

!!! warning "Certificate Validation"
    DNS validation records are the same across regions, so if you already validated in us-east-1, the us-west-2 certificate will auto-validate if using the same domain. However, you must request the certificate in advance — not during a DR event.

---

## Common Mistakes

| Mistake | Impact | Prevention |
| --------- | -------- | ------------ |
| Never testing DR | Failover fails when needed | Test quarterly minimum |
| DR region service quotas too low | Cannot scale up during failover | Request quota increases in advance |
| AMIs not copied to DR region | Cannot launch EC2 instances | Automate AMI copy with Image Builder |
| Secrets/certificates not in DR | Applications fail to start | Replicate secrets; request certs in both regions |
| No runbook documented | Slow, error-prone failover | Document and automate every step |
| Relying on control plane during failover | Control plane may be impaired during regional outage | Use data plane operations (Route 53 health checks, ARC) |
| Single-region IaC | Cannot redeploy in DR | Use CloudFormation StackSets or CDK with multi-region |
| Ignoring failback | Stuck in DR region indefinitely | Plan and test failback procedure |
| DNS TTL too high | Slow traffic switchover | Set TTL to 60s for failover records |
| Not monitoring replication lag | Data loss exceeds RPO during failover | Alert on replication lag metrics |
