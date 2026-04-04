# AWS Service Catalog

AWS Service Catalog enables organizations to create and manage catalogs of IT services approved for use on AWS.

## Core Concepts

### Products
Pre-configured CloudFormation templates that define AWS resources.

```yaml
# nginx-product.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'NGINX Web Server Product'

Parameters:
  InstanceType:
    Type: String
    Default: t3.micro
    AllowedValues: [t3.micro, t3.small, t3.medium]
  
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]

Resources:
  NginxInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-0abcdef1234567890
      InstanceType: !Ref InstanceType
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          yum update -y
          amazon-linux-extras install nginx1 -y
          systemctl start nginx
          systemctl enable nginx
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Product
          Value: NGINX-WebServer

Outputs:
  InstanceId:
    Description: EC2 Instance ID
    Value: !Ref NginxInstance
  PublicIP:
    Description: Public IP Address
    Value: !GetAtt NginxInstance.PublicIp
```

### Portfolios
Collections of products organized by business unit or use case.

```bash
# Create portfolio
aws servicecatalog create-portfolio \
    --display-name "Web Infrastructure" \
    --description "Pre-approved web server configurations" \
    --provider-name "DevOps Team"
```

### Constraints
Rules that control how products can be launched.

```json
{
  "Rules": {
    "InstanceTypeRule": {
      "Assertions": [
        {
          "Assert": {
            "Fn::Contains": [
              ["t3.micro", "t3.small"],
              {"Ref": "InstanceType"}
            ]
          },
          "AssertDescription": "Only t3.micro and t3.small allowed for dev environment"
        }
      ]
    }
  }
}
```

## Setting Up Service Catalog

### Create Product
```bash
# Upload template to S3
aws s3 cp nginx-product.yaml s3://service-catalog-templates/

# Create product
aws servicecatalog create-product \
    --name "NGINX Web Server" \
    --description "Managed NGINX web server instance" \
    --owner "DevOps Team" \
    --product-type CLOUD_FORMATION_TEMPLATE \
    --provisioning-artifact-parameters Name="v1.0",Description="Initial version",Info='{"LoadTemplateFromURL":"https://s3.amazonaws.com/service-catalog-templates/nginx-product.yaml"}'
```

### Associate with Portfolio
```bash
# Get product and portfolio IDs
PRODUCT_ID=$(aws servicecatalog search-products --filters FullTextSearch="NGINX" --query 'ProductViewSummaries[0].ProductId' --output text)
PORTFOLIO_ID=$(aws servicecatalog list-portfolios --query 'PortfolioDetails[?DisplayName==`Web Infrastructure`].Id' --output text)

# Associate product with portfolio
aws servicecatalog associate-product-with-portfolio \
    --product-id $PRODUCT_ID \
    --portfolio-id $PORTFOLIO_ID
```

### Grant Access
```bash
# Grant access to IAM group
aws servicecatalog associate-principal-with-portfolio \
    --portfolio-id $PORTFOLIO_ID \
    --principal-arn "arn:aws:iam::account:group/developers" \
    --principal-type IAM
```

## End User Experience

### Launch Product (CLI)
```bash
# Search available products
aws servicecatalog search-products --query 'ProductViewSummaries[*].[Name,ProductId]' --output table

# Launch product
aws servicecatalog provision-product \
    --product-id $PRODUCT_ID \
    --provisioning-artifact-id $ARTIFACT_ID \
    --provisioned-product-name "nginx-dev-001" \
    --provisioning-parameters Key=InstanceType,Value=t3.micro Key=Environment,Value=dev
```

### Launch Product (Python SDK)
```python
import boto3

servicecatalog = boto3.client('servicecatalog')

# Search products
response = servicecatalog.search_products()
for product in response['ProductViewSummaries']:
    print(f"Product: {product['Name']} - ID: {product['ProductId']}")

# Launch product
response = servicecatalog.provision_product(
    ProductId='prod-abcdef123456',
    ProvisioningArtifactId='pa-123456789',
    ProvisionedProductName='nginx-staging-001',
    ProvisioningParameters=[
        {
            'Key': 'InstanceType',
            'Value': 't3.small'
        },
        {
            'Key': 'Environment',
            'Value': 'staging'
        }
    ],
    Tags=[
        {
            'Key': 'Owner',
            'Value': 'development-team'
        }
    ]
)

print(f"Provisioned Product ID: {response['RecordDetail']['ProvisionedProductId']}")
```

## Advanced Product Templates

### Multi-Tier NGINX Application
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Multi-tier NGINX application with RDS backend'

Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC for deployment
  
  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>
    Description: Subnets for load balancer
  
  DBPassword:
    Type: String
    NoEcho: true
    MinLength: 8

Resources:
  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Type: application
      Subnets: !Ref SubnetIds
      SecurityGroups: [!Ref ALBSecurityGroup]
  
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateName: nginx-template
      LaunchTemplateData:
        ImageId: ami-0abcdef1234567890
        InstanceType: t3.micro
        SecurityGroupIds: [!Ref WebSecurityGroup]
        UserData:
          Fn::Base64: !Sub |
            #!/bin/bash
            yum update -y
            amazon-linux-extras install nginx1 -y
            systemctl start nginx
            systemctl enable nginx
  
  AutoScalingGroup:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      LaunchTemplate:
        LaunchTemplateId: !Ref LaunchTemplate
        Version: !GetAtt LaunchTemplate.LatestVersionNumber
      MinSize: 2
      MaxSize: 6
      DesiredCapacity: 2
      VPCZoneIdentifier: !Ref SubnetIds
      TargetGroupARNs: [!Ref TargetGroup]
  
  Database:
    Type: AWS::RDS::DBInstance
    Properties:
      DBInstanceClass: db.t3.micro
      Engine: mysql
      MasterUsername: admin
      MasterUserPassword: !Ref DBPassword
      AllocatedStorage: 20
      VPCSecurityGroups: [!Ref DBSecurityGroup]

  # Security Groups
  ALBSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: ALB Security Group
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
  
  WebSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Web Server Security Group
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          SourceSecurityGroupId: !Ref ALBSecurityGroup
  
  DBSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Database Security Group
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 3306
          ToPort: 3306
          SourceSecurityGroupId: !Ref WebSecurityGroup

Outputs:
  LoadBalancerDNS:
    Description: Load Balancer DNS Name
    Value: !GetAtt LoadBalancer.DNSName
  DatabaseEndpoint:
    Description: RDS Endpoint
    Value: !GetAtt Database.Endpoint.Address
```

## Governance and Compliance

### Launch Constraints
```json
{
  "Type": "LAUNCH",
  "Description": "Restrict instance types for cost control",
  "Rules": {
    "InstanceTypeConstraint": {
      "Assertions": [
        {
          "Assert": {
            "Fn::Contains": [
              ["t3.micro", "t3.small", "t3.medium"],
              {"Ref": "InstanceType"}
            ]
          },
          "AssertDescription": "Only approved instance types allowed"
        }
      ]
    }
  }
}
```

### Tag Options
```bash
# Create tag option
aws servicecatalog create-tag-option \
    --key "CostCenter" \
    --value "Engineering"

# Associate with portfolio
aws servicecatalog associate-tag-option-with-resource \
    --resource-id $PORTFOLIO_ID \
    --tag-option-id $TAG_OPTION_ID
```

### Budget Constraints
```json
{
  "Type": "RESOURCE_UPDATE",
  "Description": "Prevent updates that exceed budget",
  "Rules": {
    "BudgetConstraint": {
      "Assertions": [
        {
          "Assert": {
            "Fn::Not": [
              {
                "Fn::Equals": [
                  {"Ref": "InstanceType"},
                  "m5.large"
                ]
              }
            ]
          },
          "AssertDescription": "m5.large instances exceed budget limits"
        }
      ]
    }
  }
}
```

## Monitoring and Management

### CloudTrail Integration
```python
import boto3

def track_service_catalog_usage():
    cloudtrail = boto3.client('cloudtrail')
    
    response = cloudtrail.lookup_events(
        LookupAttributes=[
            {
                'AttributeKey': 'EventSource',
                'AttributeValue': 'servicecatalog.amazonaws.com'
            }
        ],
        StartTime=datetime.now() - timedelta(days=7)
    )
    
    for event in response['Events']:
        print(f"Event: {event['EventName']}")
        print(f"User: {event['Username']}")
        print(f"Time: {event['EventTime']}")
```

### Cost Tracking
```python
import boto3

def get_provisioned_product_costs():
    servicecatalog = boto3.client('servicecatalog')
    ce = boto3.client('ce')
    
    # Get provisioned products
    response = servicecatalog.scan_provisioned_products()
    
    for product in response['ProvisionedProducts']:
        product_name = product['Name']
        
        # Get cost data
        cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': '2024-01-01',
                'End': '2024-01-31'
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'TAG',
                    'Key': 'aws:servicecatalog:provisionedProductName'
                }
            ]
        )
        
        print(f"Product: {product_name}")
        for result in cost_response['ResultsByTime']:
            for group in result['Groups']:
                if product_name in group['Keys'][0]:
                    cost = group['Metrics']['BlendedCost']['Amount']
                    print(f"  Cost: ${cost}")
```

## Self-Service Portal

### Custom Web Interface
```python
from flask import Flask, render_template, request, jsonify
import boto3

app = Flask(__name__)
servicecatalog = boto3.client('servicecatalog')

@app.route('/')
def catalog():
    response = servicecatalog.search_products()
    products = response['ProductViewSummaries']
    return render_template('catalog.html', products=products)

@app.route('/launch', methods=['POST'])
def launch_product():
    data = request.json
    
    try:
        response = servicecatalog.provision_product(
            ProductId=data['product_id'],
            ProvisioningArtifactId=data['artifact_id'],
            ProvisionedProductName=data['name'],
            ProvisioningParameters=data['parameters']
        )
        
        return jsonify({
            'status': 'success',
            'record_id': response['RecordDetail']['RecordId']
        })
    
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 400

@app.route('/status/<record_id>')
def check_status(record_id):
    response = servicecatalog.describe_record(Id=record_id)
    return jsonify({
        'status': response['RecordDetail']['Status'],
        'outputs': response['RecordOutputs']
    })
```

## Best Practices

### Template Design
- Use parameters for customization
- Implement proper resource tagging
- Include comprehensive outputs
- Add resource dependencies

### Portfolio Organization
- Group by business function
- Implement approval workflows
- Use descriptive naming conventions
- Regular template updates

### Access Control
- Principle of least privilege
- Role-based access patterns
- Regular access reviews
- Audit trail monitoring

### Cost Management
- Set budget constraints
- Monitor usage patterns
- Implement cost allocation tags
- Regular cost optimization reviews