# AWS DevOps Services

## Amazon Q Developer

Amazon Q Developer is an AI-powered assistant that accelerates software development and DevOps workflows.

### Key Features
- **Code Generation**: Generate code snippets, functions, and entire modules
- **Code Review**: Automated code analysis for security, quality, and best practices
- **Infrastructure as Code**: Generate and optimize CloudFormation, Terraform, and CDK templates
- **Troubleshooting**: Debug issues across AWS services and applications
- **Documentation**: Auto-generate technical documentation and API docs

### DevOps Integration
```bash
# Install Amazon Q CLI
aws configure set plugins.q awscli-plugin-q

# Generate CloudFormation template
q generate cloudformation --service ec2 --requirements "web server with auto scaling"

# Review infrastructure code
q review --file template.yaml --focus security
```

## AWS CodePipeline

Fully managed CI/CD service for automated release pipelines.

### Pipeline Structure
```yaml
# buildspec.yml
version: 0.2
phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Build started on `date`
      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
  post_build:
    commands:
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
```

## AWS CodeBuild

Managed build service that compiles source code and runs tests.

### Build Configuration
```json
{
  "name": "nginx-build-project",
  "source": {
    "type": "GITHUB",
    "location": "https://github.com/user/nginx-app"
  },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/amazonlinux2-x86_64-standard:3.0",
    "computeType": "BUILD_GENERAL1_MEDIUM"
  }
}
```

## AWS CodeDeploy

Automated deployment service for applications to EC2, Lambda, and on-premises servers.

### Deployment Configuration
```yaml
# appspec.yml
version: 0.0
os: linux
files:
  - source: /
    destination: /var/www/html
hooks:
  BeforeInstall:
    - location: scripts/install_dependencies.sh
      timeout: 300
  ApplicationStart:
    - location: scripts/start_server.sh
      timeout: 300
```

## AWS CloudFormation

Infrastructure as Code service for provisioning AWS resources.

### NGINX Stack Template
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  NginxInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-0abcdef1234567890
      InstanceType: t3.micro
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          yum update -y
          amazon-linux-extras install nginx1 -y
          systemctl start nginx
          systemctl enable nginx
  
  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Type: application
      Subnets: [subnet-12345, subnet-67890]
```

## AWS Systems Manager

Operational hub for managing AWS resources and on-premises systems.

### Parameter Store
```bash
# Store configuration
aws ssm put-parameter --name "/nginx/config/server-name" --value "example.com" --type "String"

# Retrieve in application
SERVER_NAME=$(aws ssm get-parameter --name "/nginx/config/server-name" --query "Parameter.Value" --output text)
```

## Amazon CloudWatch

Monitoring and observability service for AWS resources and applications.

### Custom Metrics
```bash
# Send custom metric
aws cloudwatch put-metric-data --namespace "NGINX/Performance" --metric-data MetricName=RequestCount,Value=100,Unit=Count
```

### Log Insights Queries
```sql
-- Analyze NGINX access logs
fields @timestamp, remote_addr, request, status, body_bytes_sent
| filter status >= 400
| stats count() by status
| sort count desc
```

## Best Practices

### Security
- Use IAM roles instead of access keys
- Enable CloudTrail for audit logging
- Implement least privilege access
- Use AWS Secrets Manager for sensitive data

### Automation
- Implement GitOps workflows
- Use Amazon Q for code generation and review
- Automate infrastructure provisioning
- Set up comprehensive monitoring and alerting

### Cost Optimization
- Use AWS Cost Explorer for analysis
- Implement auto-scaling policies
- Leverage spot instances for non-critical workloads
- Regular resource cleanup and optimization