# AWS Identity and Access Management (IAM)

AWS IAM enables secure control of access to AWS services and resources for users and applications.

## Core Components

### Users
Individual people or applications that need AWS access.

```bash
# Create user
aws iam create-user --user-name nginx-app-user

# Create access key
aws iam create-access-key --user-name nginx-app-user
```

### Groups
Collections of users with similar permissions.

```bash
# Create group
aws iam create-group --group-name nginx-developers

# Add user to group
aws iam add-user-to-group --user-name nginx-app-user --group-name nginx-developers
```

### Roles
Temporary credentials for AWS services or cross-account access.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Policies
JSON documents defining permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::nginx-assets/*"
    }
  ]
}
```

## NGINX Application IAM Setup

### EC2 Instance Role
```bash
# Create role for EC2 instances
aws iam create-role --role-name nginx-ec2-role --assume-role-policy-document file://ec2-trust-policy.json

# Attach policies
aws iam attach-role-policy --role-name nginx-ec2-role --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create instance profile
aws iam create-instance-profile --instance-profile-name nginx-ec2-profile
aws iam add-role-to-instance-profile --instance-profile-name nginx-ec2-profile --role-name nginx-ec2-role
```

### Application-Specific Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::nginx-static-content/*",
        "arn:aws:s3:::nginx-logs/*"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/nginx/*"
    },
    {
      "Sid": "ParameterStore",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/nginx/*"
    }
  ]
}
```

## Security Best Practices

### Least Privilege Principle
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::nginx-config/production/*",
      "Condition": {
        "StringEquals": {
          "s3:ExistingObjectTag/Environment": "production"
        }
      }
    }
  ]
}
```

### MFA Requirements
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

### Cross-Account Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-B:role/nginx-cross-account-role"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id"
        }
      }
    }
  ]
}
```

## Service Integration

### Lambda Function Role
```python
import boto3
import json

def lambda_handler(event, context):
    # Lambda automatically uses the execution role
    s3 = boto3.client('s3')
    
    # Access S3 with role permissions
    response = s3.get_object(
        Bucket='nginx-config',
        Key='nginx.conf'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Configuration retrieved')
    }
```

### ECS Task Role
```json
{
  "family": "nginx-task",
  "taskRoleArn": "arn:aws:iam::account:role/nginx-ecs-task-role",
  "executionRoleArn": "arn:aws:iam::account:role/nginx-ecs-execution-role",
  "containerDefinitions": [
    {
      "name": "nginx",
      "image": "nginx:latest",
      "memory": 512,
      "essential": true
    }
  ]
}
```

## Programmatic Access

### SDK Configuration
```python
import boto3
from botocore.exceptions import ClientError

# Using IAM role (recommended)
session = boto3.Session()
s3_client = session.client('s3')

# Using temporary credentials
sts_client = boto3.client('sts')
assumed_role = sts_client.assume_role(
    RoleArn='arn:aws:iam::account:role/nginx-app-role',
    RoleSessionName='nginx-session'
)

credentials = assumed_role['Credentials']
s3_client = boto3.client(
    's3',
    aws_access_key_id=credentials['AccessKeyId'],
    aws_secret_access_key=credentials['SecretAccessKey'],
    aws_session_token=credentials['SessionToken']
)
```

### Error Handling
```python
try:
    response = s3_client.get_object(Bucket='nginx-assets', Key='index.html')
except ClientError as e:
    error_code = e.response['Error']['Code']
    
    if error_code == 'AccessDenied':
        print("Insufficient permissions to access S3 object")
    elif error_code == 'NoSuchKey':
        print("Object not found")
    else:
        print(f"Unexpected error: {error_code}")
```

## Monitoring and Auditing

### CloudTrail Integration
```json
{
  "eventVersion": "1.05",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AIDACKCEVSQ6C2EXAMPLE",
    "arn": "arn:aws:sts::account:assumed-role/nginx-ec2-role/i-1234567890abcdef0",
    "accountId": "123456789012"
  },
  "eventTime": "2024-01-15T12:00:00Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "GetObject",
  "resources": [
    {
      "ARN": "arn:aws:s3:::nginx-assets/index.html"
    }
  ]
}
```

### Access Analyzer
```bash
# Create analyzer
aws accessanalyzer create-analyzer --analyzer-name nginx-access-analyzer --type ACCOUNT

# List findings
aws accessanalyzer list-findings --analyzer-arn arn:aws:access-analyzer:region:account:analyzer/nginx-access-analyzer
```

## Policy Testing

### Policy Simulator
```bash
# Test policy permissions
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::account:role/nginx-ec2-role \
    --action-names s3:GetObject \
    --resource-arns arn:aws:s3:::nginx-assets/index.html
```

### Dry Run Testing
```python
import boto3

ec2 = boto3.client('ec2')

try:
    # Test with DryRun to check permissions
    response = ec2.run_instances(
        ImageId='ami-12345678',
        MinCount=1,
        MaxCount=1,
        InstanceType='t3.micro',
        DryRun=True
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'DryRunOperation':
        print("Permission check passed")
    else:
        print(f"Permission denied: {e.response['Error']['Code']}")
```

## Common Patterns

### Environment-Based Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::nginx-${aws:PrincipalTag/Environment}/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/Environment": ["dev", "staging", "prod"]
        }
      }
    }
  ]
}
```

### Time-Based Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*",
      "Condition": {
        "DateGreaterThan": {
          "aws:CurrentTime": "2024-01-01T00:00:00Z"
        },
        "DateLessThan": {
          "aws:CurrentTime": "2024-12-31T23:59:59Z"
        }
      }
    }
  ]
}
```

### IP-Based Restrictions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": [
            "203.0.113.0/24",
            "198.51.100.0/24"
          ]
        }
      }
    }
  ]
}
```

## Troubleshooting

### Common Issues
- **Access Denied**: Check policy permissions and resource ARNs
- **Invalid Principal**: Verify role trust relationships
- **Token Expired**: Refresh temporary credentials
- **Policy Too Large**: Split into multiple managed policies

### Debug Tools
```bash
# Check user permissions
aws iam get-user-policy --user-name nginx-app-user --policy-name nginx-policy

# List attached policies
aws iam list-attached-user-policies --user-name nginx-app-user

# Decode authorization message
aws sts decode-authorization-message --encoded-message <encoded-message>
```