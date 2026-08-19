# This is a summary

* Lambda + SQS is a good pattern to use an adapter before to push the information to a legacy system

* The first and second partition in a DynamoDB is a good way to keep the `transaction_id` as primary and `item_id` as second partition.

* `ACID` is necessary to guarantee a correct operation

* Middleware can hide Database fields and weird naming conventions

* Service in front of the DynamoDB

* Evenbridge can share as Broadcaster the updates made.

* Remember that the instances have not to handled any data that can be lost during the process (remember the Fargate instance used in SofIA)

* ElasticCache (redis) to save temporal information like a SofIA process

* DynamoDB global states to save the information as regional information

* DynamoDB proxy to handle Tables events

* Save the information as Parameter Store or Secret Manager to keep the systems decoupled

* Use centralized API. For email service in three different teams you can start adapting the credentials and, eventually centralized the application (if you have to modernize it)

* Use API versioning

* Big Lambda Monolith using Magnum in Python

* Sometime the short path is the best.

* Use S3 as a junk drawer for images, logs and temporary files

* Database per rule or context

* Web Browser is a good way to share SaaS

* Use CloudFront to cache static content

* Use CloudFront to cache API Gateway responses

* Use WAF to protect APIs

*
