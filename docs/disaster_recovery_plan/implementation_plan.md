# Implementation Plan

!!! info "Overview"
    Detailed technical implementation plan for disaster recovery across us-east-1 (primary) and us-west-2 (secondary) regions.

## 1. Networking Foundation

### VPC Peering / Transit Gateway

!!! warning "CIDR Planning"
    Use non-overlapping CIDR blocks for VPC peering or same blocks for Transit Gateway.

```bash

# Create DR VPC in us-west-2
aws ec2 create-vpc --cidr-block 10.1.0.0/16 --region us-west-2

# Create VPC peering connection
aws ec2 create-vpc-peering-connection \
    --vpc-id vpc-12345678 \
    --peer-vpc-id vpc-87654321 \
    --peer-region us-west-2 \
    --region us-east-1

# Accept peering connection in us-west-2
aws ec2 accept-vpc-peering-connection \
    --vpc-peering-connection-id pcx-1234567890abcdef0 \
    --region us-west-2
```

### Route 53

!!! tip "TTL Configuration"
    Set TTL to 60 seconds for failover records to enable faster DNS propagation.

```bash

# Create health check
aws route53 create-health-check \
    --caller-reference $(date +%s) \
    --health-check-config Type=HTTPS,ResourcePath=/health,FullyQualifiedDomainName=api.example.com,Port=443,RequestInterval=30,FailureThreshold=3

# Create failover record set
aws route53 change-resource-record-sets \
    --hosted-zone-id Z123456789 \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "api.example.com",
                "Type": "A",
                "SetIdentifier": "primary",
                "Failover": "PRIMARY",
                "TTL": 60,
                "ResourceRecords": [{"Value": "1.2.3.4"}],
                "HealthCheckId": "12345678-1234-1234-1234-123456789012"
            }
        }]
    }'
```

**Reference**: [Route 53 DNS Failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)

### Global Accelerator

```bash

# Create accelerator
aws globalaccelerator create-accelerator \
    --name "nginx-dr-accelerator" \
    --ip-address-type IPV4 \
    --enabled

# Create listener
aws globalaccelerator create-listener \
    --accelerator-arn arn:aws:globalaccelerator::123456789012:accelerator/1234abcd-abcd-1234-abcd-1234abcdefgh \
    --port-ranges FromPort=80,ToPort=80,Protocol=TCP FromPort=443,ToPort=443,Protocol=TCP

# Add endpoint groups
aws globalaccelerator create-endpoint-group \
    --listener-arn arn:aws:globalaccelerator::123456789012:listener/0123vxyz/0123vxyz \
    --endpoint-group-region us-east-1 \
    --traffic-dial-percentage 100
```

**Reference**: [Global Accelerator Guide](https://docs.aws.amazon.com/global-accelerator/latest/dg/what-is-global-accelerator.html)

### CloudFront

```bash

# Create distribution with origin failover
aws cloudfront create-distribution \
    --distribution-config '{
        "CallerReference": "'$(date +%s)'",
        "Origins": {
            "Quantity": 2,
            "Items": [
                {
                    "Id": "primary-origin",
                    "DomainName": "primary.example.com",
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "https-only"
                    }
                },
                {
                    "Id": "secondary-origin",
                    "DomainName": "secondary.example.com",
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "https-only"
                    }
                }
            ]
        },
        "OriginGroups": {
            "Quantity": 1,
            "Items": [{
                "Id": "origin-group-1",
                "FailoverCriteria": {
                    "StatusCodes": {
                        "Quantity": 3,
                        "Items": [403, 404, 500]
                    }
                },
                "Members": {
                    "Quantity": 2,
                    "Items": [
                        {"OriginId": "primary-origin"},
                        {"OriginId": "secondary-origin"}
                    ]
                }
            }]
        }
    }'
```

## 2. Compute

### EC2

!!! note "AWS Elastic Disaster Recovery"
    Use AWS DRS for continuous replication of stateful instances with RPO of seconds and RTO of minutes.

```bash

# Copy AMI to DR region
aws ec2 copy-image \
    --source-image-id ami-12345678 \
    --source-region us-east-1 \
    --region us-west-2 \
    --name "nginx-server-dr"

# Create launch template in DR region
aws ec2 create-launch-template \
    --launch-template-name nginx-dr-template \
    --launch-template-data '{
        "ImageId": "ami-87654321",
        "InstanceType": "t3.medium",
        "SecurityGroupIds": ["sg-12345678"]
    }' \
    --region us-west-2

# Create Auto Scaling group (scaled to 0 for pilot light)
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name nginx-dr-asg \
    --launch-template LaunchTemplateName=nginx-dr-template,Version=1 \
    --min-size 0 \
    --max-size 3 \
    --desired-capacity 0 \
    --vpc-zone-identifier subnet-12345678,subnet-87654321 \
    --region us-west-2
```

**Reference**: [AWS Elastic Disaster Recovery](https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html)

### ECS/Fargate

```bash

# Enable ECR cross-region replication
aws ecr put-replication-configuration \
    --replication-configuration '{
        "rules": [{
            "destinations": [{
                "region": "us-west-2",
                "registryId": "123456789012"
            }]
        }]
    }'

# Create ECS service in DR region (desired count 0)
aws ecs create-service \
    --cluster nginx-dr-cluster \
    --service-name nginx-dr-service \
    --task-definition nginx-task:1 \
    --desired-count 0 \
    --region us-west-2
```

### Lambda

```bash

# Deploy function to both regions via CloudFormation StackSets
aws cloudformation create-stack-set \
    --stack-set-name nginx-lambda-functions \
    --template-body file://lambda-template.yaml \
    --capabilities CAPABILITY_IAM

aws cloudformation create-stack-instances \
    --stack-set-name nginx-lambda-functions \
    --accounts 123456789012 \
    --regions us-east-1 us-west-2
```

## 3. Database

### Amazon Aurora

!!! success "Global Database Benefits"
    RPO: < 1 second, RTO: < 1 minute with managed failover.

```bash

# Create Aurora Global Database
aws rds create-global-cluster \
    --global-cluster-identifier nginx-global-cluster \
    --source-db-cluster-identifier nginx-primary-cluster

# Add secondary region
aws rds create-db-cluster \
    --db-cluster-identifier nginx-secondary-cluster \
    --engine aurora-mysql \
    --global-cluster-identifier nginx-global-cluster \
    --region us-west-2

# Failover to secondary region
aws rds failover-global-cluster \
    --global-cluster-identifier nginx-global-cluster \
    --target-db-cluster-identifier nginx-secondary-cluster
```

**Reference**: [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)

### Amazon RDS (non-Aurora)

```bash

# Create cross-region read replica
aws rds create-db-instance-read-replica \
    --db-instance-identifier nginx-replica-west \
    --source-db-instance-identifier nginx-primary \
    --db-instance-class db.t3.medium \
    --region us-west-2

# Promote read replica (during failover)
aws rds promote-read-replica \
    --db-instance-identifier nginx-replica-west \
    --region us-west-2
```

**Reference**: [RDS Read Replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html)

### DynamoDB

```bash

# Create Global Table
aws dynamodb create-global-table \
    --global-table-name nginx-sessions \
    --replication-group RegionName=us-east-1 RegionName=us-west-2
```

**Reference**: [DynamoDB Global Tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)

### ElastiCache (Redis)

```bash

# Create Global Datastore
aws elasticache create-global-replication-group \
    --global-replication-group-id nginx-global-redis \
    --primary-replication-group-id nginx-primary-redis

# Add secondary region
aws elasticache create-replication-group \
    --replication-group-id nginx-secondary-redis \
    --global-replication-group-id nginx-global-redis \
    --region us-west-2
```

**Reference**: [ElastiCache Global Datastore](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/Redis-Global-Datastore.html)

## 4. Storage

### S3

!!! tip "Replication Time Control"
    Use S3 RTC for 15-minute replication SLA on critical data.

```bash

# Enable versioning (required for CRR)
aws s3api put-bucket-versioning \
    --bucket nginx-primary-bucket \
    --versioning-configuration Status=Enabled

# Create replication configuration
aws s3api put-bucket-replication \
    --bucket nginx-primary-bucket \
    --replication-configuration '{
        "Role": "arn:aws:iam::123456789012:role/replication-role",
        "Rules": [{
            "ID": "ReplicateToWest",
            "Status": "Enabled",
            "Prefix": "",
            "Destination": {
                "Bucket": "arn:aws:s3:::nginx-dr-bucket",
                "ReplicationTime": {
                    "Status": "Enabled",
                    "Time": {"Minutes": 15}
                },
                "Metrics": {
                    "Status": "Enabled",
                    "EventThreshold": {"Minutes": 15}
                }
            }
        }]
    }'
```

**Reference**: [S3 Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)

### EFS

```bash

# Create replication configuration
aws efs create-replication-configuration \
    --source-file-system-id fs-12345678 \
    --destinations Region=us-west-2,KmsKeyId=arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012
```

**Reference**: [EFS Replication](https://docs.aws.amazon.com/efs/latest/ug/efs-replication.html)

## 5. Application Integration

### SQS

!!! warning "No Native Replication"
    SQS doesn't support cross-region replication. Design applications for message loss during failover.

```bash

# Create matching queues in DR region
aws sqs create-queue \
    --queue-name nginx-processing-queue \
    --region us-west-2 \
    --attributes '{
        "VisibilityTimeoutSeconds": "300",
        "MessageRetentionPeriod": "1209600"
    }'
```

### EventBridge

```bash

# Create cross-region rule
aws events put-rule \
    --name nginx-cross-region-rule \
    --event-pattern '{
        "source": ["nginx.application"],
        "detail-type": ["User Action"]
    }' \
    --region us-east-1

aws events put-targets \
    --rule nginx-cross-region-rule \
    --targets Id=1,Arn=arn:aws:events:us-west-2:123456789012:event-bus/default \
    --region us-east-1
```

**Reference**: [EventBridge Cross-Region](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-region.html)

## 6. Security

### Secrets Manager

```bash

# Create multi-region secret
aws secretsmanager create-secret \
    --name nginx/database/credentials \
    --secret-string '{"username":"admin","password":"secret123"}' \
    --replica-regions Region=us-west-2,KmsKeyId=arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012
```

**Reference**: [Secrets Manager Multi-Region](https://docs.aws.amazon.com/secretsmanager/latest/userguide/create-manage-multi-region-secrets.html)

### KMS

```bash

# Create multi-region key
aws kms create-key \
    --multi-region \
    --description "NGINX DR encryption key"

# Replicate to us-west-2
aws kms replicate-key \
    --key-id 12345678-1234-1234-1234-123456789012 \
    --replica-region us-west-2
```

**Reference**: [KMS Multi-Region Keys](https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html)

## 7. Infrastructure as Code

### CloudFormation StackSets

```bash

# Create StackSet for multi-region deployment
aws cloudformation create-stack-set \
    --stack-set-name nginx-infrastructure \
    --template-body file://nginx-template.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Deploy to both regions
aws cloudformation create-stack-instances \
    --stack-set-name nginx-infrastructure \
    --accounts 123456789012 \
    --regions us-east-1 us-west-2 \
    --parameter-overrides ParameterKey=IsDRRegion,ParameterValue=false ParameterKey=IsDRRegion,ParameterValue=true
```

**Reference**: [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)

## 8. Monitoring & Alerting

### AWS Backup

```bash

# Create backup plan with cross-region copy
aws backup create-backup-plan \
    --backup-plan '{
        "BackupPlanName": "nginx-dr-backup-plan",
        "Rules": [{
            "RuleName": "DailyBackups",
            "TargetBackupVault": "nginx-backup-vault",
            "ScheduleExpression": "cron(0 2 ? * * *)",
            "Lifecycle": {
                "DeleteAfterDays": 30
            },
            "CopyActions": [{
                "DestinationBackupVault": "arn:aws:backup:us-west-2:123456789012:backup-vault:nginx-dr-vault",
                "Lifecycle": {
                    "DeleteAfterDays": 30
                }
            }]
        }]
    }'
```

**Reference**: [AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html)

### CloudWatch Cross-Region Dashboard

```bash

# Create cross-region dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "NGINX-DR-Overview" \
    --dashboard-body '{
        "widgets": [
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "nginx-alb", {"region": "us-east-1"}],
                        [".", ".", ".", "nginx-alb-dr", {"region": "us-west-2"}]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "us-east-1",
                    "title": "Response Time Comparison"
                }
            }
        ]
    }'
```

## Architecture Overview

```text
┌─────────────────┐    ┌─────────────────┐
│   us-east-1     │    │   us-west-2     │
│   (Primary)     │    │   (Secondary)   │
├─────────────────┤    ├─────────────────┤
│ Route 53        │◄──►│ Health Checks   │
│ Global Accel    │    │ Failover DNS    │
├─────────────────┤    ├─────────────────┤
│ Aurora Primary  │───►│ Aurora Secondary│
│ S3 CRR Source   │───►│ S3 CRR Dest     │
│ EFS Primary     │───►│ EFS Replica     │
├─────────────────┤    ├─────────────────┤
│ EC2 ASG (Active)│    │ EC2 ASG (Scaled)│
│ ECS (Active)    │    │ ECS (Standby)   │
│ Lambda (Active) │    │ Lambda (Active) │
└─────────────────┘    └─────────────────┘
```

!!! success "Implementation Complete"
    This plan provides comprehensive DR coverage with automated failover capabilities and minimal data loss.
