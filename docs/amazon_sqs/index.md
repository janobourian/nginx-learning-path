# Amazon Simple Queue Service (SQS)

Amazon SQS is a fully managed message queuing service for decoupling and scaling microservices, distributed systems, and serverless applications.

## Core Concepts

### Queue Types
- **Standard Queues**: Nearly unlimited throughput, at-least-once delivery
- **FIFO Queues**: Exactly-once processing, message ordering preserved

### Key Features
- **Scalability**: Handle millions of messages per second
- **Reliability**: Messages stored redundantly across multiple AZs
- **Security**: Encryption in transit and at rest
- **Cost-effective**: Pay only for what you use

## Quick Start

### Creating a Queue
```bash
# Standard queue
aws sqs create-queue --queue-name my-standard-queue

# FIFO queue
aws sqs create-queue --queue-name my-fifo-queue.fifo --attributes FifoQueue=true
```

### Sending Messages
```python
import boto3

sqs = boto3.client('sqs')
queue_url = 'https://sqs.region.amazonaws.com/account/queue-name'

# Send message
response = sqs.send_message(
    QueueUrl=queue_url,
    MessageBody='Hello from SQS!'
)
```

### Receiving Messages
```python
# Receive messages
response = sqs.receive_message(
    QueueUrl=queue_url,
    MaxNumberOfMessages=10,
    WaitTimeSeconds=20
)

for message in response.get('Messages', []):
    print(f"Message: {message['Body']}")
    
    # Delete message after processing
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=message['ReceiptHandle']
    )
```

## Integration with NGINX

### Message Processing Backend
```python
# app.py - Flask backend for NGINX
from flask import Flask, request, jsonify
import boto3

app = Flask(__name__)
sqs = boto3.client('sqs')
QUEUE_URL = 'https://sqs.region.amazonaws.com/account/nginx-tasks'

@app.route('/submit-task', methods=['POST'])
def submit_task():
    task_data = request.json
    
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(task_data)
    )
    
    return jsonify({'status': 'queued'})

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})
```

### NGINX Configuration
```nginx
upstream backend {
    server 127.0.0.1:5000;
}

server {
    listen 80;
    
    location /api/ {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location /health {
        proxy_pass http://backend/health;
    }
}
```

## Best Practices

### Message Design
- Keep messages under 256KB
- Use message attributes for metadata
- Implement idempotent processing

### Error Handling
```python
# Dead Letter Queue configuration
dlq_attributes = {
    'reddrivePolicy': json.dumps({
        'deadLetterTargetArn': dlq_arn,
        'maxReceiveCount': 3
    })
}

sqs.set_queue_attributes(
    QueueUrl=queue_url,
    Attributes=dlq_attributes
)
```

### Monitoring
```python
# CloudWatch metrics
cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='SQS/Custom',
    MetricData=[
        {
            'MetricName': 'MessagesProcessed',
            'Value': 1,
            'Unit': 'Count'
        }
    ]
)
```

## Common Use Cases

### Microservices Communication
- Decouple service dependencies
- Handle traffic spikes
- Ensure message delivery

### Batch Processing
- Queue large datasets for processing
- Distribute workload across workers
- Handle failures gracefully

### Event-Driven Architecture
- Trigger Lambda functions
- Process user actions asynchronously
- Integrate with other AWS services