# Amazon MQ

Amazon MQ is a managed message broker service for Apache ActiveMQ and RabbitMQ that makes it easy to migrate to the cloud.

## Supported Engines

### Apache ActiveMQ

- JMS-compliant message broker
- Supports multiple protocols (OpenWire, STOMP, AMQP, MQTT, WebSocket)
- Enterprise messaging patterns

### RabbitMQ

- AMQP 0-9-1 protocol
- High-performance message routing
- Flexible routing capabilities

## Core Concepts

### Broker Types

- **Single-instance**: Cost-effective for development
- **Active/standby**: High availability with automatic failover
- **Cluster**: RabbitMQ clusters for scalability

### Key Features

- **Managed Service**: AWS handles maintenance and updates
- **Security**: VPC integration, encryption, authentication
- **Monitoring**: CloudWatch integration
- **Backup**: Automated backups and point-in-time recovery

## Quick Start

### Creating a Broker

```bash

# ActiveMQ broker
aws mq create-broker \
    --broker-name my-activemq-broker \
    --engine-type ActiveMQ \
    --engine-version 5.17.6 \
    --host-instance-type mq.t3.micro \
    --deployment-mode SINGLE_INSTANCE \
    --users Username=admin,Password=password123

# RabbitMQ broker
aws mq create-broker \
    --broker-name my-rabbitmq-broker \
    --engine-type RabbitMQ \
    --engine-version 3.11.20 \
    --host-instance-type mq.t3.micro \
    --deployment-mode SINGLE_INSTANCE
```

### ActiveMQ Client Example

```python
import stomp
import json

class MessageListener(stomp.ConnectionListener):
    def on_message(self, frame):
        print(f"Received: {frame.body}")

# Connect to ActiveMQ
conn = stomp.Connection([('broker-endpoint', 61614)])
conn.set_listener('', MessageListener())
conn.connect('admin', 'password123', wait=True)

# Subscribe to queue
conn.subscribe(destination='/queue/test', id=1, ack='auto')

# Send message
conn.send(body=json.dumps({'message': 'Hello ActiveMQ'}),
          destination='/queue/test')
```

### RabbitMQ Client Example

```python
import pika
import json

# Connect to RabbitMQ
credentials = pika.PlainCredentials('admin', 'password123')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('broker-endpoint', 5671, '/', credentials, ssl=True)
)
channel = connection.channel()

# Declare queue
channel.queue_declare(queue='task_queue', durable=True)

# Publish message
message = json.dumps({'task': 'process_data'})
channel.basic_publish(
    exchange='',
    routing_key='task_queue',
    body=message,
    properties=pika.BasicProperties(delivery_mode=2)  # Make message persistent
)

# Consume messages
def callback(ch, method, properties, body):
    data = json.loads(body)
    print(f"Processing: {data}")
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue='task_queue', on_message_callback=callback)
channel.start_consuming()
```

## Integration with NGINX

### Message Producer Service

```python

# producer.py - Flask service behind NGINX
from flask import Flask, request, jsonify
import pika
import json

app = Flask(__name__)

def get_rabbitmq_connection():
    credentials = pika.PlainCredentials('admin', 'password123')
    return pika.BlockingConnection(
        pika.ConnectionParameters('broker-endpoint', 5671, '/', credentials, ssl=True)
    )

@app.route('/publish', methods=['POST'])
def publish_message():
    data = request.json

    connection = get_rabbitmq_connection()
    channel = connection.channel()

    channel.queue_declare(queue='nginx_tasks', durable=True)
    channel.basic_publish(
        exchange='',
        routing_key='nginx_tasks',
        body=json.dumps(data),
        properties=pika.BasicProperties(delivery_mode=2)
    )

    connection.close()
    return jsonify({'status': 'published'})
```

### NGINX Load Balancer Configuration

```nginx
upstream message_producers {
    server 10.0.1.10:5000;
    server 10.0.1.11:5000;
    server 10.0.1.12:5000;
}

server {
    listen 80;
    server_name messaging.example.com;

    location /api/publish {
        proxy_pass http://message_producers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Handle connection timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }

    location /health {
        proxy_pass http://message_producers/health;
    }
}
```

## Advanced Patterns

### Message Routing (RabbitMQ)

```python

# Topic exchange routing
channel.exchange_declare(exchange='logs', exchange_type='topic')

# Publish with routing key
channel.basic_publish(
    exchange='logs',
    routing_key='nginx.error',
    body='Error message from NGINX'
)

# Subscribe to specific patterns
channel.queue_bind(exchange='logs', queue='error_queue', routing_key='*.error')
```

### Request-Reply Pattern

```python
import uuid

class RPCClient:
    def __init__(self):
        self.connection = get_rabbitmq_connection()
        self.channel = self.connection.channel()

        result = self.channel.queue_declare(queue='', exclusive=True)
        self.callback_queue = result.method.queue

        self.channel.basic_consume(
            queue=self.callback_queue,
            on_message_callback=self.on_response,
            auto_ack=True
        )

    def on_response(self, ch, method, props, body):
        if self.corr_id == props.correlation_id:
            self.response = body

    def call(self, message):
        self.response = None
        self.corr_id = str(uuid.uuid4())

        self.channel.basic_publish(
            exchange='',
            routing_key='rpc_queue',
            properties=pika.BasicProperties(
                reply_to=self.callback_queue,
                correlation_id=self.corr_id,
            ),
            body=message
        )

        while self.response is None:
            self.connection.process_data_events()

        return self.response
```

## Monitoring and Management

### CloudWatch Metrics

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

# Custom metrics
cloudwatch.put_metric_data(
    Namespace='AmazonMQ/Custom',
    MetricData=[
        {
            'MetricName': 'MessagesProcessed',
            'Dimensions': [
                {
                    'Name': 'BrokerName',
                    'Value': 'my-broker'
                }
            ],
            'Value': 1,
            'Unit': 'Count'
        }
    ]
)
```

### Health Checks

```python
@app.route('/health')
def health_check():
    try:
        connection = get_rabbitmq_connection()
        connection.close()
        return jsonify({'status': 'healthy', 'broker': 'connected'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503
```

## Best Practices

### Security

- Use VPC for network isolation
- Enable encryption in transit and at rest
- Implement proper authentication and authorization
- Regular security updates through managed service

### Performance

- Choose appropriate instance types
- Monitor queue depths and processing rates
- Implement connection pooling
- Use persistent connections

### High Availability

- Deploy in multiple AZs
- Use active/standby for ActiveMQ
- Implement proper error handling and retries
- Set up monitoring and alerting
