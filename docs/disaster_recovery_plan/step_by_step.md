# Step-by-Step DR Setup Guide

This guide provides concrete AWS CLI commands to set up disaster recovery between us-east-1 (primary) and us-west-2 (DR) regions.

!!! info "Prerequisites"

    - AWS CLI configured with appropriate permissions
    - Primary infrastructure already deployed in us-east-1
    - Replace placeholder values like `<vpc-id>`, `<account-id>` with actual values

## Step 1: Network Foundation

### 1.1 Create DR VPC in us-west-2

```bash

# Create VPC
aws ec2 create-vpc --region us-west-2 --cidr-block 10.1.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=dr-vpc}]'

# Create subnets in multiple AZs
aws ec2 create-subnet --region us-west-2 --vpc-id <dr-vpc-id> --cidr-block 10.1.1.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-public-subnet-1}]'
aws ec2 create-subnet --region us-west-2 --vpc-id <dr-vpc-id> --cidr-block 10.1.2.0/24 --availability-zone us-west-2b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-public-subnet-2}]'
aws ec2 create-subnet --region us-west-2 --vpc-id <dr-vpc-id> --cidr-block 10.1.3.0/24 --availability-zone us-west-2a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-subnet-1}]'
aws ec2 create-subnet --region us-west-2 --vpc-id <dr-vpc-id> --cidr-block 10.1.4.0/24 --availability-zone us-west-2b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-subnet-2}]'

# Create internet gateway
aws ec2 create-internet-gateway --region us-west-2 --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=dr-igw}]'
aws ec2 attach-internet-gateway --region us-west-2 --vpc-id <dr-vpc-id> --internet-gateway-id <dr-igw-id>

# Create NAT gateway
aws ec2 allocate-address --region us-west-2 --domain vpc --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=dr-nat-eip}]'
aws ec2 create-nat-gateway --region us-west-2 --subnet-id <dr-public-subnet-1-id> --allocation-id <dr-eip-allocation-id> --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=dr-nat-gw}]'

# Create route tables
aws ec2 create-route-table --region us-west-2 --vpc-id <dr-vpc-id> --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=dr-public-rt}]'
aws ec2 create-route-table --region us-west-2 --vpc-id <dr-vpc-id> --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=dr-private-rt}]'

# Add routes
aws ec2 create-route --region us-west-2 --route-table-id <dr-public-rt-id> --destination-cidr-block 0.0.0.0/0 --gateway-id <dr-igw-id>
aws ec2 create-route --region us-west-2 --route-table-id <dr-private-rt-id> --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <dr-nat-gw-id>

# Associate subnets with route tables
aws ec2 associate-route-table --region us-west-2 --subnet-id <dr-public-subnet-1-id> --route-table-id <dr-public-rt-id>
aws ec2 associate-route-table --region us-west-2 --subnet-id <dr-public-subnet-2-id> --route-table-id <dr-public-rt-id>
aws ec2 associate-route-table --region us-west-2 --subnet-id <dr-private-subnet-1-id> --route-table-id <dr-private-rt-id>
aws ec2 associate-route-table --region us-west-2 --subnet-id <dr-private-subnet-2-id> --route-table-id <dr-private-rt-id>
```

### 1.2 Set Up Inter-Region VPC Peering

```bash

# Create VPC peering connection from us-east-1 to us-west-2
aws ec2 create-vpc-peering-connection --region us-east-1 --vpc-id <primary-vpc-id> --peer-vpc-id <dr-vpc-id> --peer-region us-west-2

# Accept peering connection in us-west-2
aws ec2 accept-vpc-peering-connection --region us-west-2 --vpc-peering-connection-id <peering-connection-id>

# Update route tables to allow cross-region traffic
aws ec2 create-route --region us-east-1 --route-table-id <primary-private-rt-id> --destination-cidr-block 10.1.0.0/16 --vpc-peering-connection-id <peering-connection-id>
aws ec2 create-route --region us-west-2 --route-table-id <dr-private-rt-id> --destination-cidr-block 10.0.0.0/16 --vpc-peering-connection-id <peering-connection-id>
```

### 1.3 Configure Route 53 Health Checks and Failover

```bash

# Create health check for primary ALB
aws route53 create-health-check --caller-reference "primary-alb-$(date +%s)" --health-check-config Type=HTTPS,ResourcePath=/health,FullyQualifiedDomainName=<primary-alb-dns>,Port=443,RequestInterval=30,FailureThreshold=3

# Create hosted zone record with failover routing
aws route53 change-resource-record-sets --hosted-zone-id <hosted-zone-id> --change-batch '{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "SetIdentifier": "primary",
        "Failover": "PRIMARY",
        "AliasTarget": {
          "DNSName": "<primary-alb-dns>",
          "EvaluateTargetHealth": true,
          "HostedZoneId": "<primary-alb-zone-id>"
        },
        "HealthCheckId": "<health-check-id>"
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "SetIdentifier": "secondary",
        "Failover": "SECONDARY",
        "AliasTarget": {
          "DNSName": "<dr-alb-dns>",
          "EvaluateTargetHealth": true,
          "HostedZoneId": "<dr-alb-zone-id>"
        }
      }
    }
  ]
}'
```

## Step 2: Database DR

### 2.1 Aurora Global Database

```bash

# Create global cluster
aws rds create-global-cluster --region us-east-1 --global-cluster-identifier myapp-global --source-db-cluster-identifier <primary-cluster-id>

# Create secondary cluster in us-west-2
aws rds create-db-cluster --region us-west-2 --db-cluster-identifier myapp-dr-cluster --engine aurora-mysql --global-cluster-identifier myapp-global --db-subnet-group-name <dr-subnet-group> --vpc-security-group-ids <dr-security-group-id>

# Create reader instance in DR region
aws rds create-db-instance --region us-west-2 --db-instance-identifier myapp-dr-reader --db-instance-class db.r5.large --engine aurora-mysql --db-cluster-identifier myapp-dr-cluster

# Monitor replication lag
aws rds describe-db-clusters --region us-west-2 --db-cluster-identifier myapp-dr-cluster --query 'DBClusters[0].GlobalWriteForwardingStatus'

# Failover command (when needed)
aws rds failover-global-cluster --region us-west-2 --global-cluster-identifier myapp-global --target-db-cluster-identifier myapp-dr-cluster
```

### 2.2 DynamoDB Global Tables

```bash

# Create table in primary region
aws dynamodb create-table --region us-east-1 --table-name MyAppTable --attribute-definitions AttributeName=id,AttributeType=S --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES

# Add replica in DR region
aws dynamodb update-table --region us-east-1 --table-name MyAppTable --replica-updates Create={RegionName=us-west-2}
```

### 2.3 ElastiCache Global Datastore

```bash

# Create global replication group
aws elasticache create-global-replication-group --region us-east-1 --global-replication-group-id-suffix myapp-global --primary-replication-group-id <primary-replication-group-id>

# Create secondary replication group
aws elasticache create-replication-group --region us-west-2 --replication-group-id myapp-dr-redis --description "DR Redis cluster" --global-replication-group-id myapp-global-<random-suffix> --num-cache-clusters 2 --cache-node-type cache.r5.large --cache-subnet-group-name <dr-cache-subnet-group> --security-group-ids <dr-cache-security-group-id>
```

### 2.4 RDS Cross-Region Read Replica

```bash

# Create cross-region read replica
aws rds create-db-instance-read-replica --region us-west-2 --db-instance-identifier myapp-dr-replica --source-db-instance-identifier arn:aws:rds:us-east-1:<account-id>:db:<primary-db-instance-id> --db-instance-class db.t3.medium --db-subnet-group-name <dr-subnet-group> --vpc-security-group-ids <dr-security-group-id>
```

## Step 3: Storage DR

### 3.1 S3 Cross-Region Replication

```bash

# Enable versioning on source bucket
aws s3api put-bucket-versioning --region us-east-1 --bucket <source-bucket> --versioning-configuration Status=Enabled

# Enable versioning on destination bucket
aws s3api put-bucket-versioning --region us-west-2 --bucket <destination-bucket> --versioning-configuration Status=Enabled

# Create replication IAM role
aws iam create-role --role-name S3ReplicationRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "s3.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Attach replication policy
aws iam attach-role-policy --role-name S3ReplicationRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSS3ReplicationServiceRolePolicy

# Configure replication
aws s3api put-bucket-replication --region us-east-1 --bucket <source-bucket> --replication-configuration '{
  "Role": "arn:aws:iam::<account-id>:role/S3ReplicationRole",
  "Rules": [
    {
      "ID": "ReplicateToWest",
      "Status": "Enabled",
      "Prefix": "",
      "Destination": {
        "Bucket": "arn:aws:s3:::<destination-bucket>",
        "StorageClass": "STANDARD_IA"
      }
    }
  ]
}'
```

### 3.2 EFS Replication

```bash

# Create replication configuration
aws efs create-replication-configuration --region us-east-1 --source-file-system-id <source-efs-id> --destinations Region=us-west-2,KmsKeyId=<kms-key-id>
```

### 3.3 EBS Snapshots via AWS Backup

```bash

# Create backup vault in DR region
aws backup create-backup-vault --region us-west-2 --backup-vault-name MyAppDRVault --encryption-key-id <kms-key-id>

# Create backup plan with cross-region copy
aws backup create-backup-plan --region us-east-1 --backup-plan '{
  "BackupPlanName": "MyAppBackupPlan",
  "Rules": [
    {
      "RuleName": "DailyBackups",
      "TargetBackupVaultName": "MyAppVault",
      "ScheduleExpression": "cron(0 2 ? * * *)",
      "StartWindowMinutes": 60,
      "CompletionWindowMinutes": 120,
      "Lifecycle": {
        "DeleteAfterDays": 30
      },
      "CopyActions": [
        {
          "DestinationBackupVaultArn": "arn:aws:backup:us-west-2:<account-id>:backup-vault:MyAppDRVault",
          "Lifecycle": {
            "DeleteAfterDays": 30
          }
        }
      ]
    }
  ]
}'

# Create backup selection
aws backup create-backup-selection --region us-east-1 --backup-plan-id <backup-plan-id> --backup-selection '{
  "SelectionName": "MyAppResources",
  "IamRoleArn": "arn:aws:iam::<account-id>:role/AWSBackupDefaultServiceRole",
  "Resources": ["arn:aws:ec2:us-east-1:<account-id>:volume/*"]
}'
```

## Step 4: Compute DR

### 4.1 AMI Cross-Region Copy

```bash

# Copy AMI to DR region
aws ec2 copy-image --region us-west-2 --source-region us-east-1 --source-image-id <source-ami-id> --name "MyApp-DR-AMI" --description "DR copy of MyApp AMI"
```

### 4.2 Auto Scaling Group in DR

```bash

# Create launch template in DR region
aws ec2 create-launch-template --region us-west-2 --launch-template-name MyApp-DR-Template --launch-template-data '{
  "ImageId": "<dr-ami-id>",
  "InstanceType": "t3.medium",
  "SecurityGroupIds": ["<dr-security-group-id>"],
  "IamInstanceProfile": {"Name": "<instance-profile-name>"},
  "UserData": "<base64-encoded-user-data>"
}'

# Create Auto Scaling Group (pilot light - min=0)
aws autoscaling create-auto-scaling-group --region us-west-2 --auto-scaling-group-name MyApp-DR-ASG --launch-template LaunchTemplateName=MyApp-DR-Template,Version=1 --min-size 0 --max-size 10 --desired-capacity 0 --vpc-zone-identifier "<dr-private-subnet-1-id>,<dr-private-subnet-2-id>" --target-group-arns <dr-target-group-arn>
```

### 4.3 ECR Cross-Region Replication

```bash

# Configure ECR replication
aws ecr put-replication-configuration --region us-east-1 --replication-configuration '{
  "rules": [
    {
      "destinations": [
        {
          "region": "us-west-2",
          "registryId": "<account-id>"
        }
      ]
    }
  ]
}'
```

### 4.4 ECS Service in DR

```bash

# Register task definition in DR region
aws ecs register-task-definition --region us-west-2 --family myapp-task --task-role-arn <task-role-arn> --execution-role-arn <execution-role-arn> --network-mode awsvpc --requires-compatibilities FARGATE --cpu 256 --memory 512 --container-definitions '[{
  "name": "myapp",
  "image": "<account-id>.dkr.ecr.us-west-2.amazonaws.com/myapp:latest",
  "portMappings": [{"containerPort": 80}],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/myapp",
      "awslogs-region": "us-west-2",
      "awslogs-stream-prefix": "ecs"
    }
  }
}]'

# Create ECS service with desired count 0
aws ecs create-service --region us-west-2 --cluster <dr-cluster-name> --service-name myapp-dr-service --task-definition myapp-task --desired-count 0 --launch-type FARGATE --network-configuration 'awsvpcConfiguration={subnets=[<dr-private-subnet-1-id>,<dr-private-subnet-2-id>],securityGroups=[<dr-security-group-id>]}'
```

### 4.5 Lambda

```bash

# Deploy via CloudFormation StackSets
aws cloudformation create-stack-set --region us-east-1 --stack-set-name MyAppLambdaStackSet --template-body file://lambda-template.yaml --capabilities CAPABILITY_IAM

# Deploy to both regions
aws cloudformation create-stack-instances --region us-east-1 --stack-set-name MyAppLambdaStackSet --accounts <account-id> --regions us-east-1,us-west-2
```

## Step 5: Security DR

### 5.1 Secrets Manager Replication

```bash

# Replicate secrets to DR region
aws secretsmanager replicate-secret-to-regions --region us-east-1 --secret-id <secret-name> --add-replica-regions Region=us-west-2,KmsKeyId=<kms-key-id>
```

### 5.2 KMS Multi-Region Keys

```bash

# Create multi-region key
aws kms create-key --region us-east-1 --multi-region --description "MyApp multi-region key"

# Replicate key to DR region
aws kms replicate-key --region us-west-2 --key-id <primary-key-id> --replica-region us-west-2 --description "MyApp DR key replica"
```

### 5.3 ACM Certificates

```bash

# Request certificate in DR region
aws acm request-certificate --region us-west-2 --domain-name app.example.com --subject-alternative-names "*.app.example.com" --validation-method DNS
```

## Step 6: Application Integration DR

### 6.1 SQS Queues in DR

```bash

# Create SQS queue in DR region
aws sqs create-queue --region us-west-2 --queue-name MyAppQueue --attributes VisibilityTimeoutSeconds=300,MessageRetentionPeriod=1209600
```

### 6.2 SNS Topics in DR

```bash

# Create SNS topic in DR region
aws sns create-topic --region us-west-2 --name MyAppTopic
```

### 6.3 EventBridge Cross-Region

```bash

# Create rule with cross-region target
aws events put-rule --region us-east-1 --name MyAppCrossRegionRule --event-pattern '{"source":["myapp"]}'
aws events put-targets --region us-east-1 --rule MyAppCrossRegionRule --targets Id=1,Arn=arn:aws:events:us-west-2:<account-id>:event-bus/default,RoleArn=<cross-region-role-arn>
```

## Step 7: Monitoring & Backup

### 7.1 CloudWatch Cross-Region Dashboard

```bash

# Create dashboard with metrics from both regions
aws cloudwatch put-dashboard --region us-east-1 --dashboard-name MyAppDRDashboard --dashboard-body '{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "<primary-alb-name>", {"region": "us-east-1"}],
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "<dr-alb-name>", {"region": "us-west-2"}]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Request Count - Both Regions"
      }
    }
  ]
}'
```

### 7.2 AWS Backup Cross-Region

```bash

# Already configured in Step 3.3 with cross-region copy actions
```

## Step 8: Failover Procedure

!!! warning "Emergency Procedure"
    Execute these steps only during an actual disaster scenario.

### 8.1 Confirm Disaster

- Verify primary region is unavailable
- Check CloudWatch dashboards and Route 53 health checks
- Confirm with team before proceeding

### 8.2 Initiate Route 53 Failover

```bash

# Route 53 will automatically failover based on health checks

# Or manually switch if using Application Recovery Controller
aws route53-recovery-control-config update-routing-control --routing-control-arn <routing-control-arn> --routing-control-state Off
```

### 8.3 Promote Aurora Secondary

```bash

# Promote Aurora DR cluster to primary
aws rds failover-global-cluster --region us-west-2 --global-cluster-identifier myapp-global --target-db-cluster-identifier myapp-dr-cluster
```

### 8.4 Scale Up Compute in DR

```bash

# Scale up Auto Scaling Group
aws autoscaling update-auto-scaling-group --region us-west-2 --auto-scaling-group-name MyApp-DR-ASG --desired-capacity 3

# Scale up ECS service
aws ecs update-service --region us-west-2 --cluster <dr-cluster-name> --service myapp-dr-service --desired-count 3
```

### 8.5 Verify Services

- Check application health endpoints
- Verify database connectivity
- Test critical user flows
- Monitor CloudWatch metrics

### 8.6 Monitor

- Set up alerts for DR region
- Monitor application performance
- Track costs in DR region

## Step 9: Failback Procedure

!!! info "Recovery Procedure"
    Execute when primary region is restored and stable.

### 9.1 Verify Primary is Healthy

- Confirm all primary region services are operational
- Run health checks and smoke tests
- Ensure network connectivity is restored

### 9.2 Re-create Aurora Global Database

```bash

# Create new global cluster with us-east-1 as primary
aws rds create-global-cluster --region us-east-1 --global-cluster-identifier myapp-global-new --source-db-cluster-identifier <restored-primary-cluster-id>

# Add us-west-2 as secondary
aws rds create-db-cluster --region us-west-2 --db-cluster-identifier myapp-failback-cluster --engine aurora-mysql --global-cluster-identifier myapp-global-new --db-subnet-group-name <dr-subnet-group> --vpc-security-group-ids <dr-security-group-id>
```

### 9.3 Wait for Replication Sync

```bash

# Monitor replication lag
aws rds describe-db-clusters --region us-west-2 --db-cluster-identifier myapp-failback-cluster --query 'DBClusters[0].GlobalWriteForwardingStatus'
```

### 9.4 Switch Route 53 Back

```bash

# Update Route 53 to point back to primary
aws route53 change-resource-record-sets --hosted-zone-id <hosted-zone-id> --change-batch '{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "SetIdentifier": "primary",
        "Failover": "PRIMARY",
        "AliasTarget": {
          "DNSName": "<primary-alb-dns>",
          "EvaluateTargetHealth": true,
          "HostedZoneId": "<primary-alb-zone-id>"
        },
        "HealthCheckId": "<health-check-id>"
      }
    }
  ]
}'
```

### 9.5 Scale Down DR Compute

```bash

# Scale down Auto Scaling Group
aws autoscaling update-auto-scaling-group --region us-west-2 --auto-scaling-group-name MyApp-DR-ASG --desired-capacity 0

# Scale down ECS service
aws ecs update-service --region us-west-2 --cluster <dr-cluster-name> --service myapp-dr-service --desired-count 0
```

### 9.6 Verify

- Confirm traffic is flowing to primary region
- Verify all services are operational
- Monitor for any issues
- Update runbooks based on lessons learned

!!! tip "Best Practices"

    - Test failover procedures regularly
    - Automate as much as possible using AWS Systems Manager or custom scripts
    - Document all placeholder values and keep them updated
    - Monitor costs during DR scenarios
    - Practice failback procedures in non-production environments
