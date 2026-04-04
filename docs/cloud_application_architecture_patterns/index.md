# Cloud Application Architecture Patterns

##  **Adapter Microservices**: 

How can the application take advantage of existing functionality without abandoning the microservices approach?. Essentially, the Adapter acts as a translator. It allows your new, shiny microservices to talk to "messy" existing systems using a clean, modern interface that fits your new architecture.

## Real-World Applications: The E-commerce Migration

Imagine you are building a modern mobile shopping app using microservices, but your company’s core Inventory Management still runs on an on-premise mainframe that only accepts SOAP/XML requests via a VPN.

Instead of making every new microservice learn how to talk to that old mainframe, you build an Adapter Microservice.
* The New Service: Requests data via a clean REST/JSON API.
* The Adapter: Receives the JSON, transforms it into XML, handles the mainframe's specific authentication, and returns a simplified JSON response to the caller.

## AWS Implementation Strategy

To keep this pattern cloud-native and scalable, you can implement it using several different "flavors" depending on your needs:

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **API Interface** | **Amazon API Gateway** | Provides the REST/GraphQL endpoint for your modern services to call. |
| **Translation Logic** | **AWS Lambda** | The "brain." It converts data formats (e.g., JSON to XML) and maps fields between systems. |
| **Connectivity** | **AWS PrivateLink / VPN** | Securely connects the Adapter in the cloud to the existing functionality (on-prem or another VPC). |
| **Resiliency** | **Amazon SQS** | Acts as a buffer to protect the legacy system from being overwhelmed by modern traffic spikes. |
| **Secrets Management** | **AWS Secrets Manager** | Stores legacy credentials or API keys so the Adapter can authenticate securely. |

### How to Apply It in AWS

**1. The Serverless Adapter (Most Common)**

Use AWS Lambda as your adapter. It's cost-effective because you only pay when a translation happens.

* Flow: Service A → API Gateway → Lambda (Adapter) → Legacy System.

* Benefit: You don't have to manage servers for a simple translation layer. 

**2. The Containerized Adapter**

If the transformation logic is heavy (e.g., using a specific Java library that requires a lot of memory), use AWS Fargate.

* Flow: Run the adapter as a small Docker container.

* Benefit: Provides a persistent connection if the legacy system requires long-lived sessions.

**3. Protecting the New "Domain"**

Ensure the Adapter is the only thing that knows about the legacy system's quirks. If the legacy system uses weird naming conventions (e.g., CUST_ID_01_VAL), the Adapter should map that to customerId before any other service sees it.

### **Pro-Tip: The "Strangler Fig" Connection**

The Adapter Pattern is often the first step in a Strangler Fig migration. Once the Adapter is in place, you can eventually replace the "existing functionality" behind it with a new microservice without ever changing the code in your mobile app or other services. They won't even know the backend changed!


<hr>

## **Aggregate**: 

How do you tie together the groups of tightly related concepts and the values that belong within them in a subdomain? In microservices, an Aggregate is a cluster of domain objects that can be treated as a single unit. It ensures data consistency and defines clear boundaries, where one specific entity (the **Aggregate Root**) acts as the sole gatekeeper for all changes within that group.

### Real-World Applications: The Order Processing System

Imagine an e-commerce system with an **Order** entity. An "Order" isn't just one row; it consists of OrderItems, ShippingAddress, and Discounts. 

If you let a microservice change an OrderItem price without checking the total Order value, you break business rules. By using the Aggregate pattern:
* The Aggregate Root: The Order entity.
* The Rule: No outside service can talk directly to OrderItem. They must talk to Order.
* The Result: The Order ensures that the total sum is always correct and that items aren't added if the order is already "Shipped."

### AWS Implementation Strategy

Managing aggregates in the cloud requires databases that support ACID transactions or strong consistency models to ensure the "cluster" of data stays valid.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Data Storage** | **Amazon DynamoDB** | Uses a "Single-Table Design" to store the entire Aggregate (Root + Children) in one partition for atomic updates. |
| **Transactional Integrity** | **DynamoDB Transactions** | Ensures that updates to multiple items within the Aggregate succeed or fail together (All-or-Nothing). |
| **Relational Storage** | **Amazon Aurora** | Ideal if your Aggregate has complex relationships; uses Row-Level locking to maintain the Root's integrity. |
| **Eventual Consistency** | **Amazon EventBridge** | Once an Aggregate is updated, this service broadcasts the change to other subdomains/microservices. |
| **State Management** | **AWS Step Functions** | Orchestrates complex logic that might span across the boundaries of the Aggregate Root. |

### How to Apply It in AWS

**1. Single-Table Design (DynamoDB)**

In AWS, the most efficient way to handle an Aggregate is to store the Root and all its child entities in a single DynamoDB partition using the same Partition Key (PK).

* Flow: When you need to update an OrderItem, you fetch the entire partition (the whole Aggregate), apply business logic in your Lambda, and save it back.
* Benefit: You get the speed of NoSQL while maintaining the strict boundaries of the Aggregate.

**2. Enforcing Boundaries with Lambda**

The Lambda function representing the "Order Service" should be the only piece of code with the IAM permissions to write to that specific DynamoDB table.

* Flow: Other services (like Inventory) never touch the Order table. They send a message to the Order Service.
* Benefit: Prevents "Data Silo Leaking" where external services accidentally corrupt the internal logic of your Aggregate.

**3. Versioning for Concurrency (Optimistic Locking)**

Use a version attribute in your DynamoDB items. When the Aggregate Root is updated, the version must match.

* Flow: If two processes try to update the Order at once, the second one will fail because the version number changed.
* Benefit: Ensures that the Aggregate Root always stays in a consistent state even under high load.

### **Pro-Tip: Keep Aggregates Small**

A common mistake is making Aggregates too large (e.g., putting every "User" action into one Aggregate). In AWS, large Aggregates lead to "hot partitions" in DynamoDB and slower Lambda execution times. Aim for the smallest possible boundary that still satisfies your business's consistency rules.

<hr>

## **Anti-Corruption Layer (ACL)**: 

How can we design the system so that the Bounded Contexts (BCs) can interact without being tightly coupled together? The Anti-Corruption Layer (ACL) is a specialized architectural component that translates between two different domain models. It prevents "corrupting" a clean, modern Bounded Context with the technical debt, confusing naming conventions, or outdated logic of a legacy system or external API.

### Real-World Applications: Legacy Mainframe Integration

Imagine your company is launching a modern "Customer Loyalty" microservice. This service has a clean model where a customer has a `loyaltyTier` and `pointsBalance`. However, the only way to get customer data is from a 20-year-old Mainframe system where customers are identified by `REC_TYPE_A_09` and tiers are stored as numeric codes like `001, 002`.

Instead of letting those "001" codes leak into your Loyalty service logic, you build an ACL:
* The Modern Service: Only knows about `Gold`, `Silver`, and `Platinum` tiers.
* The ACL: Intercepts calls to the Mainframe, maps `001` to `Gold`, and renames the fields to match the modern domain.
* The Result: If the Mainframe is eventually replaced, you only change the ACL code; the Loyalty service remains untouched.

### AWS Implementation Strategy

In AWS, the ACL is usually a standalone set of components that acts as a gateway or a "transformer" between services.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Logic Layer** | **AWS Lambda** | Performs the heavy lifting of mapping "Legacy-Speak" to "Modern-Speak." |
| **Interface** | **Amazon API Gateway** | Exposes a clean, RESTful interface for the modern BC to consume. |
| **Decoupling** | **Amazon EventBridge** | Translates legacy events into clean, domain-specific events for the new system. |
| **Protocol Translation** | **AWS App Mesh** | Can facilitate the routing and translation between services in a complex microservices mesh. |
| **Data Translation** | **AWS Glue / AppFlow** | If the "corruption" is at the data layer, these tools transform data formats between systems. |



### How to Apply It in AWS

**1. The "Facade" Lambda**

Create a Lambda function that sits in front of the legacy API. The modern microservice calls this Lambda as if it were a native part of its own domain.

* Flow: New Service → Lambda (ACL) → Legacy API.
* Benefit: The New Service code stays "pure." It never contains logic to handle legacy errors or weird data structures.

**2. Event Transformation (EventBridge Pipes)**

If the legacy system emits messy events, use **Amazon EventBridge Pipes**. You can use the "Enrichment" or "Input Transformation" step to clean up the event payload before it reaches your new Bounded Context.

* Flow: Legacy Event → EventBridge Pipe (Transform) → New Microservice.
* Benefit: Your new service's event handlers don't need "if/else" logic to handle legacy data formats.

**3. Separate VPCs for Isolation**

To ensure strict decoupling, host the ACL in its own network space or as part of the "Adapter" layer. Use **AWS PrivateLink** to allow the modern BC to talk to the ACL without exposing the legacy system to the wider network.

* Benefit: Provides both architectural and security isolation.

### **Pro-Tip: ACL vs. Adapter**

While they look similar, the **Adapter** (which you learned previously) focuses on **technical** translation (REST to SOAP, JSON to XML). The **Anti-Corruption Layer** focuses on **semantic** translation (changing the meaning and structure of the data to match the new business logic). Often, you will use them together!

<hr>


## **Application Database**: 

How should a cloud-native application store the data it uses so that it can run as a stateless application? In cloud-native architecture, "statelessness" means the application tier does not store any client data or session info on its local disk or memory. Instead, all persistent information is offloaded to an external **Application Database**, allowing the application instances to be destroyed, replaced, or scaled horizontally at any moment without data loss.

### Real-World Applications: The Scaling Web Portal

Imagine a news website during a major breaking event. Traffic spikes from 1,000 to 1,000,000 users in minutes. 

If the application stored user sessions or draft articles on the local server's hard drive:
* Scaling would be impossible because "Server A" wouldn't know what "Server B" is doing.
* If a server crashed, all users connected to it would lose their work.

By using an external Application Database:
* Any web server can handle any request because they all fetch the "state" (user profile, preferences, cart) from a central, managed database.
* You can add 100 new servers instantly to handle the load.

### AWS Implementation Strategy

The key in AWS is choosing a database that matches the access pattern and offers high availability so the "stateless" app can always reach its "state."

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **NoSQL / High Scale** | **Amazon DynamoDB** | A serverless KV store that provides millisecond latency at any scale. Perfect for session state and user profiles. |
| **Relational (SQL)** | **Amazon Aurora** | A cloud-native MySQL/PostgreSQL compatible database that handles complex queries while managing backups and scaling automatically. |
| **In-Memory Cache** | **Amazon ElastiCache** | Uses Redis or Memcached to store "ephemeral" state (like login sessions) for ultra-fast access. |
| **Global State** | **DynamoDB Global Tables** | Synchronizes data across AWS Regions so your app remains stateless even if a whole region goes down. |
| **Connection Pooling** | **Amazon RDS Proxy** | Sits between your stateless Lambda functions and your database to manage thousands of simultaneous connections efficiently. |



### How to Apply It in AWS

**1. Offloading Sessions to ElastiCache (Redis)**

Instead of storing a user's login session in the application memory (sticky sessions), write the session data to **Amazon ElastiCache**.

* Flow: User → Load Balancer → Any App Instance → ElastiCache.
* Benefit: You can terminate any application instance without logging the user out.

**2. Utilizing DynamoDB for "Eventual" Persistence**

For cloud-native apps that need to scale rapidly, DynamoDB is the gold standard. Because it is accessed via an HTTP API (rather than a persistent TCP connection), it is perfect for "stateless" compute like AWS Lambda.

* Flow: Lambda Function → AWS SDK → DynamoDB.
* Benefit: No connection management overhead, allowing for thousands of concurrent executions.

**3. Handling Relational Data with Aurora Serverless**

If your application requires SQL, use **Aurora Serverless v2**. It scales its capacity up and down based on the application's demand.

* Benefit: Matches the "cloud-native" philosophy where you don't manage the underlying database hardware, only the data.

### **Pro-Tip: The "12-Factor App" Rule**

A core tenet of the "12-Factor App" methodology is treating backing services (databases) as **attached resources**. In AWS, this means your application should never "know" the IP address of the database. Instead, use environment variables to store the **Endpoint URL** (provided by Route 53 or RDS). This makes the app truly portable and stateless.

<hr>


## **Application Package**: 

What features of a computer language ecosystem are required to implement a Cloud Application? The Application Package refers to the standardized way an application's code, runtime, libraries, and configurations are bundled together. To thrive in the cloud, a language ecosystem must support "Immutability" and "Portability"—ensuring that the same package runs identically in development, testing, and production environments.

### Real-World Applications: The "It Works on My Machine" Problem

Imagine a developer writes a Python script that requires Python 3.11 and a specific version of a library like Pandas. They deploy it to a server that only has Python 3.8. The application crashes instantly.

With the Application Package pattern (specifically using Containers):
* The Developer: Creates a "Manifest" (like a Dockerfile) that lists the exact OS, Python version, and libraries needed.
* The Package: A single, read-only "Image" is built.
* The Result: That exact image is moved from the developer's laptop to an AWS cluster. Because the package includes the entire environment, it is guaranteed to run without "missing dependency" errors.

### AWS Implementation Strategy

In AWS, packaging moves away from simple "zip files" toward container images and serverless deployment bundles that integrate with automated pipelines.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Artifact Storage** | **Amazon ECR** | A managed Docker registry to store, version, and scan your application packages (images). |
| **Serverless Packaging** | **AWS SAM / Zip** | Bundles Lambda code and dependencies into a single deployment package. |
| **Orchestration** | **Amazon ECS / EKS** | Pulls the Application Package from ECR and runs it across a cluster of servers. |
| **Automated Building** | **AWS CodeBuild** | Compiles code and "packages" it into a container image or zip file automatically. |
| **Environment Config** | **AWS AppConfig** | Manages the configurations that sit inside the package but change between environments. |



### How to Apply It in AWS

**1. Containerization (Docker + Amazon ECR)**

Standardize your application by wrapping it in a Docker container. This is the ultimate "Application Package."

* Flow: Build Image -> Tag Image -> Push to Amazon ECR.
* Benefit: Total isolation. Your application doesn't care if the underlying AWS server is running Amazon Linux, Ubuntu, or Windows; it only sees its own internal package environment.

**2. AWS SAM (Serverless Application Model)**

For serverless apps, use AWS SAM to define your package. It treats your code, its dependencies, and the required AWS infrastructure (like an S3 bucket or DynamoDB table) as a single deployable unit.

* Flow: sam build -> sam deploy.
* Benefit: Simplifies the "packaging" of complex serverless architectures into a single CloudFormation stack.

**3. Infrastructure as Code (CDK)**

Use the AWS Cloud Development Kit (CDK) to package your application and its environment using familiar languages (Python, TS, Java).

* Benefit: The "Package" now includes not just the code, but the network, security groups, and database definitions required for it to run.

### **Pro-Tip: The "Golden Image" vs. Lean Containers**

In a cloud-native ecosystem, you want your Application Package to be as small as possible. Use "Distroless" or "Alpine" base images. Smaller packages result in faster "cold starts" for Lambdas and quicker scaling for ECS tasks, which directly reduces your AWS costs and improves user experience during traffic spikes.

<hr>


## **Backend Service**: 

How can multiple applications share the same reusable functionality? A Backend Service is a discrete, server-side component that provides specific business logic or data processing capabilities to multiple "frontends" or other services. By centralizing common tasks—such as payment processing, authentication, or notification delivery—you eliminate code duplication and ensure that business rules are enforced consistently across the entire organization.

### Real-World Applications: The Universal Notification Engine

Imagine a large company with a web store, a mobile app, and an internal admin portal. All three need to send SMS and Email alerts to users.

Without a shared Backend Service:
* Each team writes its own code to integrate with Twilio or SendGrid.
* Security credentials for these providers are scattered across three different codebases.
* If the company decides to switch providers, all three applications must be updated and redeployed.

With a shared **Notification Backend Service**:
* All applications send a standardized JSON request (e.g., `{"userId": "123", "message": "Your order is ready"}`) to one central API.
* The Backend Service handles the routing, retry logic, and provider credentials.
* The Result: One team manages notifications for the whole company, and adding a new app (like an Apple Watch app) takes minutes instead of days.

### AWS Implementation Strategy

Shared services in AWS are typically built to be "multi-tenant" (serving multiple callers) and are often hidden behind a central entry point for security and monitoring.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **API Entry Point** | **Amazon API Gateway** | Provides a single URL for all applications to call, handling rate limiting and API keys for each "client" app. |
| **Compute** | **AWS Lambda / ECS** | Hosts the reusable logic. Lambda is great for event-driven tasks; ECS/Fargate is better for long-running processes. |
| **Service Discovery** | **AWS Cloud Map** | Allows applications to find the shared service's location dynamically without hardcoding IP addresses. |
| **Authentication** | **Amazon Cognito** | Centralizes user identity so multiple apps can share the same login session and permissions. |
| **Monitoring** | **AWS X-Ray** | Traces requests as they travel from the "caller" application into the shared Backend Service for debugging. |



### How to Apply It in AWS

**1. Centralized API with API Gateway**

Expose your shared functionality as a REST or HTTP API. Use **Usage Plans** in API Gateway to track how much the "Mobile App" vs. the "Web App" is using the service.

* Flow: Client App → API Gateway (Auth Check) → Shared Lambda Function.
* Benefit: You can throttle a specific app if it starts sending too many requests, protecting the backend for everyone else.

**2. The Microservice Chassis**

If you have many backend services, create a "Chassis"—a reusable template or library that includes common AWS integrations like logging to CloudWatch and security headers.

* Benefit: Every new backend service you build automatically follows your company's AWS best practices.

**3. Internal Service Mesh (AWS App Mesh)**

For complex internal sharing, use **AWS App Mesh**. It manages the communication between your "Consumer" apps and your "Provider" backend services automatically.

* Flow: App A talks to "NotificationService" (a virtual name). App Mesh routes the traffic to the healthiest container.
* Benefit: Provides advanced traffic splitting (e.g., sending 10% of traffic to a "Beta" version of the shared service).

### **Pro-Tip: Version Your Shared API**

When a service is shared, changing it is dangerous. Always version your API (e.g., `api.example.com/v1/notify` vs. `/v2/notify`). This allows the "Web Team" to upgrade to the new features while the "Mobile Team" continues using the old version until they are ready to update their app.

<hr>


## **Big Ball of Mud**: 

What is the simplest possible architecture for an application that helps get something working quickly to get needed feedback? While often used as a pejorative for messy code, the **Big Ball of Mud** is an actual architectural pattern defined by expediency. It prioritizes "working software" over "perfect structure." It is the natural result of high-pressure deadlines and evolving requirements where the goal is to ship a prototype or MVP (Minimum Viable Product) as fast as possible to validate a business idea.

### Real-World Applications: The Viral Startup MVP

Imagine a small team building a new social media app. They don't know if people will actually use the "Photo Filter" feature. 
* The "Clean" Approach: They spend 3 months designing microservices, setting up Kubernetes, and defining strict API contracts. By the time they launch, a competitor has already captured the market.
* The Big Ball of Mud Approach: They write one big monolithic script. The database queries are mixed with the UI logic, and there are no unit tests. They ship in 2 weeks. 
* The Result: Users love the app! Now that they have "needed feedback" and actual revenue, they can afford to hire more developers to "clean up the mud" and migrate to a better architecture.

### AWS Implementation Strategy

In AWS, the "Big Ball of Mud" is best implemented using services that require the least amount of "plumbing" and allow you to mix logic freely.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Compute** | **AWS Amplify** | The fastest way to "throw together" a full-stack app. It automates the backend, auth, and hosting. |
| **Database** | **Amazon DynamoDB** | Use a single table with no strict schema. Just dump your JSON data there and worry about the structure later. |
| **Backend Logic** | **AWS Lambda** | Write one or two "fat" Lambda functions that handle everything (monolithic Lambda) instead of 50 small ones. |
| **Storage** | **Amazon S3** | Use S3 as a "junk drawer" for images, logs, and temporary files without setting up complex file systems. |
| **Rapid Prototyping** | **AWS App Runner** | Deploy a single containerized "monolith" directly from your code with zero infrastructure management. |

### How to Apply It in AWS

**1. The "Fat Lambda" (Lambda-lith)**

Instead of creating a separate Lambda for every API endpoint, put all your code in one function. Use a simple routing library (like express for Node.js or Mangum for Python) inside that single Lambda.

* Flow: API Gateway -> One Single Lambda -> DynamoDB.
* Benefit: Extremely fast to deploy and debug in the beginning. You don't have to manage dozens of IAM roles or CloudFormation resources.

**2. AWS Amplify Gen 2**

Use Amplify to "generate" your backend. It allows you to define your data model and authentication in TypeScript code and handles the AWS infrastructure for you.

* Flow: Local Code -> npx ampx sandbox -> Immediate Cloud Resources.
* Benefit: You get a working app in minutes, which is the core goal of the Big Ball of Mud pattern.

**3. Single-Table "Messy" Design**

Don't spend weeks on database normalization. Use DynamoDB as a document store. If a user record needs a new field like favoriteColor tomorrow, just start saving it.

* Benefit: Zero downtime for "schema migrations" because there is no schema.

### **Pro-Tip: When to "Clean the Mud"**

The Big Ball of Mud is a starting point, not a destination. The moment your "quick prototype" becomes "production software" that people rely on, you must start applying patterns like the Strangler Fig or Anti-Corruption Layer to prevent the mud from becoming a permanent disaster. If you wait too long, the cost of change will become higher than the value of the software.

<hr>


## **Bounded Context**: 

How do you clearly define the logical boundaries (edges) of a domain and subdomain(s) where particular terms and rules apply? A Bounded Context is a central pattern in Domain-Driven Design (DDD). It acts as a linguistic and conceptual boundary where a specific model and its language (Ubiquitous Language) are strictly valid. In microservices, a Bounded Context often maps to a single microservice or a logical group of services, ensuring that "Customer" in the Sales context doesn't get confused with "Customer" in the Support context.

### Real-World Applications: The Multi-Faceted "Product"

Imagine a large retail company. The word "Product" means different things to different departments:
* **Sales Context**: A Product has a price, a discount code, and a marketing description.
* **Inventory Context**: A Product has a weight, dimensions, a bin location in the warehouse, and a stock count.
* **Shipping Context**: A Product has a tracking number, a shipping class, and a delivery status.

If you try to build one giant "Product" database table for the whole company, it becomes a nightmare to maintain. By using Bounded Contexts:
* You create three separate services (Sales, Inventory, Shipping).
* Each service has its own "Product" model that only contains the fields it cares about.
* They communicate via well-defined APIs or events when something changes (e.g., "Product Sold" in Sales triggers "Decrement Stock" in Inventory).

### AWS Implementation Strategy

In AWS, Bounded Contexts are best enforced through physical isolation and strict communication patterns.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Isolation** | **AWS Accounts / VPCs** | For large organizations, each Bounded Context lives in its own AWS account to ensure total resource isolation. |
| **Service Boundary** | **Amazon ECS / Lambda** | Each Bounded Context is deployed as its own independent compute unit with its own IAM roles. |
| **Data Sovereignty** | **Amazon DynamoDB / RDS** | Each Bounded Context **must** have its own database. No "sharing" tables between contexts. |
| **Communication** | **Amazon EventBridge** | Used to pass information between contexts without them needing to know about each other's internal models. |
| **Governance** | **AWS Organizations** | Manages the different accounts belonging to different Bounded Contexts under one billing umbrella. |



### How to Apply It in AWS

**1. Database-per-Service (The Golden Rule)**

To enforce a Bounded Context in AWS, ensure that the Sales Lambda cannot talk to the Inventory Database.

* **Flow**: Sales Lambda → Sales DynamoDB. To update Inventory, Sales Lambda → EventBridge → Inventory Lambda → Inventory DynamoDB.
* **Benefit**: You can change the Inventory database schema without breaking the Sales service.

**2. Ubiquitous Language in Code (IAM and Tags)**

Use the language of the Bounded Context in your AWS Resource tags and IAM Role names.

* **Example**: Use `Sales-Admin-Role` vs `Inventory-Admin-Role`.
* **Benefit**: It becomes immediately clear which "domain" an AWS resource belongs to during an audit or when looking at a billing report.

**3. Event-Driven Decoupling**

When a "Customer" is created in the Identity context, don't have that service call the "Marketing" service directly. Instead, publish a `CustomerCreated` event to EventBridge.

* **Benefit**: The Identity context doesn't need to know that a Marketing context even exists. This preserves the "logical boundary" of the domain.

### **Pro-Tip: Beware of the "Shared Kernel"**

Sometimes teams try to share a "Common" library across Bounded Contexts (like a shared `User` class). In AWS, this often leads to a "Deployment Monolith" where changing the library requires redeploying every service. Instead, allow for a little bit of code duplication—let each Bounded Context define its own version of the object so they can evolve independently.

<hr>

## **Browser Application**: 

What is the easiest, most universal Client Application for any user that does not assume specific hardware or software configuration? The Browser Application pattern (often implemented as a Single Page Application or SPA) offloads the user interface logic to the client's web browser. By using standard web technologies (HTML, CSS, JavaScript), the application becomes platform-agnostic, running on any device with a modern browser—from a high-end desktop to a low-cost smartphone—without requiring an installation process.

### Real-World Applications: The "Zero-Install" SaaS

Imagine a collaborative project management tool like Trello or Jira. 
* **The Traditional Approach**: You would have to download a .exe for Windows, a .dmg for Mac, and an .app for mobile. Every time there is a bug fix, you have to download an update.
* **The Browser Application Approach**: The user simply navigates to a URL. the browser downloads the "Client Application" (JavaScript) on the fly. 
* **The Result**: The user always has the latest version. The company doesn't have to manage different codebases for different operating systems, and users can access their data from any device instantly.

### AWS Implementation Strategy

In a cloud-native AWS environment, the Browser Application pattern allows you to host the frontend at a extremely low cost because the "computing" happens on the user's device, not on your servers.

| Layer | AWS Service | Role |
| :--- | :--- | :--- |
| **Storage (Hosting)** | **Amazon S3** | Stores the static files (HTML, JS, CSS, Images). S3 is virtually indestructible and incredibly cheap for hosting. |
| **Global Delivery** | **Amazon CloudFront** | A Content Delivery Network (CDN) that caches your browser app at "Edge Locations" close to your users for fast loading. |
| **Security (SSL/TLS)** | **AWS Certificate Manager** | Provides the "HTTPS" padlock for your site for free, ensuring data sent between the browser and AWS is encrypted. |
| **Authentication** | **Amazon Cognito** | Allows the browser app to sign users in directly using social logins (Google, Amazon) or email/password. |
| **Domain Management** | **Amazon Route 53** | Connects your user-friendly URL (e.g., www.myapp.com) to your CloudFront distribution. |



### How to Apply It in AWS

**1. The "Static Website Hosting" Combo**

The gold standard for Browser Apps in AWS is S3 + CloudFront. 

* Flow: User Browser -> CloudFront -> S3 Bucket.
* Benefit: Your "server" can never "crash" because there is no server running the frontend—just files being served globally. It can handle millions of users for pennies.

**2. Decoupled API Communication**

Because the Browser App runs on the user's machine, it needs to talk to your backend via the internet. Use **CORS (Cross-Origin Resource Sharing)** settings in **Amazon API Gateway** to allow the browser to securely call your microservices.

* Flow: Browser JS -> AJAX/Fetch Call -> API Gateway -> Lambda.
* Benefit: The frontend and backend can be developed and deployed by separate teams.

**3. Single Page Application (SPA) Routing**

When using frameworks like React or Vue, the browser handles the "navigation" between pages. You must configure CloudFront to redirect "404 Not Found" errors back to `index.html` so the browser app can handle the routing logic.

* Benefit: Provides a smooth, app-like experience without the screen flickering or reloading.

### **Pro-Tip: Progressive Web Apps (PWA)**

You can enhance the Browser Application pattern by making it a **PWA**. By adding a small "Service Worker" file and a manifest, you can allow users to "Install" your web app to their home screen and even use parts of it offline. In AWS, you can use **AWS Amplify** to automate the creation of PWAs, giving you the reach of the web with the feel of a native app.

<hr>

<hr>

- **Client Application**: How can I build applications to take advantage of the services provided by an application running in the cloud?
- **Cloud Application**: How can I build applications to take the maximum advantage of all the features of the cloud for best future proofing and agility?
- **Cloud Database**: How should a cloud-native application store data persistently in a cloud environment?
- **Cloud-Native Architecture**: How can I architect an application to take maximum advantage of the cloud platform it will run on?
- **Columnar Database**: How can an application most efficiently store data for performing analytics, such as in a data warehouse?
- **Command-line Interface**: How can an end user automate activities like bulk loads, bulks changes, or schedukle execution of activities using the services provided by an application running in the cloud?
- **Command Query Responsibility Segregation (CQRS)**: How do you optimize throughput for query and updates by multiple clients that have numerous cross-cutting views of the data?
- **Configuration Database**: How can a cloud service store its service state such that all of the nodes in the services can share and access state?
- **Containerize the Application**: How can an application be packaged to facilitate greater deployment density and platform portability?
- **Data Module**: How can I align my data model with my application model so that both are easier to maintain and can evolve quickly?
- **Databse-as-a-Service**: How does an application have access to an Application Database?
- **Dispatcher**: How can a client access a microservices application through a channel-specific service interface when the business functionality is spread across an evolving set of domain-specific APIs?
- **Distributed Architecture**: How can I architect my application so that parts of it can be developed, deployed, and run independently?
- **Document Database**: How can and application most efficiently store and retrieve data when the future structure of the data is not well known?
- **Domain Event**: How do you model those aspects of a design that correspond to things that happen during the various scenario encountered by the system?
- **Domain Microservice**: How should a set of microservices in an architecture provide the business functionality for an application?
- **Domain Service**: How do you model those operations within a subdomain that do not belong to a specific Entity or Aggregate?
- **Event**: How do you represent a change in one component to be communicated to other components?
- **Event API**: How can the reactive components in an event-driven architecture know what events to expect?
- **Event Backbone**: How can reactive components receive the event they are interested in without being coupled directly to the event notifiers that generate the events?
- **Event Choreography**: When a change ocurrs in one component, how can a variable number of other components react according?
- **Event Notifier**: How and when should a component announce changes to other components?
- **Event Sourcing**: As an application's state changes constantly and unpredictably due to evolving conditions, how can you audit the history that created the current state?
- **Event Storming**: How do you get the stakeholders to understand and describe the elements and event around the domain and subdomain?
- **External Configuration**: How can I build my application once and yet be able to deploy it to multiple environments that are configured differently?
- **Extract Component**: How do you separate loosely related parts of the code in our monolith into distinct deployable units?
- **Graph Database**: How can an application most efficiently store and retrieve interrelated data entities by navitating their relationships?
- **Hairline Cracks**: How do you identify the areas within a monolith application that are candidate boundaries for microservices?
- **Interaction Model**: How do yo avoid mixing business and presentation logic inside your Client application?
- **Key-value Database**: How can an application most efficiently store and retrieve independent data entities thar are always looked up by the same key?
- **Lift and shift**: What is the simplest possible way to move an existing application to the cloud?
- **Micro Frontend**: How do you avoid creating a monolithic Single-Page application by placing too much functionality in a common front-end?
- **Microservices**: How do you architect an application as a set of interconnected modules that can be developed independently?
- **Mobile Application**: How do you provide the most optimized user experience on a mobile device and take advantage of the features that make mobile computing unique?
- **Model Around the Domain**: How can you encourage stakeholders to explain enough of the domain requirements in a way that reveals the relevant capabilities for the application you are building?
- **Modular Monolith**: How can I architect my application to make it easier to maintain and evolve quickly?
- **New Features as Microservices**: While strangling a monolith, how do you avoid adding new functionality to the monolith that will later have to be modernized into microservices?
- **Pave the road**: How can we encourage teams to move to the cloud and adopt these new technologies without letting each team go in their own direction and work at cross purposes?
- **Playback testing**: How do you ensure that the new microservices architecture maintains the same functionality as the old monolithic system, especially when the amount of detailed end-to-end application knowledge of the existing application may be limited?
- **Polyglot Persistence**: How can an application store its Data Modelues in the type of database that works best for the application's data structure and how it accesses the data?
- **Polyglot Development**: What computer language(s) should be used for implementing microservices?
- **Public API**: How do you best enable third-party applications to interact programmatically with a Cloud Application?
- **Reactive Component**: How can you construct an application that can react to events?
- **Refactor the Monolith**: How can I make an existing application easier for multiple teams to maintain and able to run effectively in a multi-computer environment?
- **Refactor the Extract**: How do we address coupling within the monolith to facilitate extraction into microservices?
- **Relation Database**: How can an application store well-structured data that it needs to query dynamically?
- **Replace as Microservice**: How can we move complex and important pieces of functionality that are tightlyu coupled in the monolith to microservices with minimal impact?
- **Replicable application**: How can an application run reliably on an unreliable platform and scale to handle greater client load the way the platform scales?
- **Replicated Database**: How can a Cloud Database provide the same quality of service as a cloud-native application with the same availability, scalability, and performance as the application?
- **Repositories**: How do we address coupling within the monolith to facilitate extraction into microservices?
- **Self-Managed Data Store**: How does a microservice store its state?
- **Service API**: How should an application expose its functionality to clients that want to use the application?
- **Service Orchestator**: How does a microservice perfor a complex task, one that is performed in multiple steps?
- **Single-Page application**: How do you desing the frontend of your application to provide the best mix of client responsiveness and server optimization?
- **Smart Small**: How can we start adopting cloud services and moving existing application to the cloud or writing applications for the cloud, possibly using microservices?
- **Stateless Application**: How can an application support concurrent requests efficiently and reover from failures without losing data?
- **Strangle the Monolith**: How can we replace a monolithic architecture with a microservice architecture while reducing overall risk?
- **Transform Monolith into microservices**: How do you kieep the monolithic system working while you substiture piece of functionality with microservices over time?
- **Virtualize the application** What is the simpliest possible way to package an application so that it can easily be deployed to traditional IT or to the cloud?
- **Web Form application**: How do you build a user interface to provide basic functionality to the largest possible set of users using the largest set of devices and hardware.

## Introduction

Cloud Application Architecture Patterns is a collection of patterns and concepts that help you design, build, and run applications that take full advantage of cloud computing.

These patterns and concepts cover a wide range of topics, including microservices architecture, cloud-native design principles, data storage options, event-driven architectures, and strategies for modernizing existing applications.

By understanding and applying these patterns, you can create applications that are scalable, resilient, and adaptable to changing business needs in a cloud environment.

Each pattern and concept provides a solution to a specific problem or challenge encountered when developing cloud applications. They offer best practices, design strategies, and implementation guidelines to help you navigate the complexities of cloud application architecture.

Whether you are building new cloud-native applications or modernizing existing ones, these patterns and concepts serve as valuable resources to guide your architectural decisions and ensure successful outcomes in the cloud.

Phases:

* Application Architecture and Design
* Application Development and Deployment
* Cloud Operations and Nonfunctional Requirements

## Modern Application Development

* Modular Code
* Polyglot development
* Iterative development
* Continuos Delivery
* Automated builds

## Aspects of Software Development

* SDLC = Software Development Lifecycle
* SDLC Phases = [Planning, Analysis, Design, Implementation, Testing, Deployment, Maintenance]

* Application architecture
* Application migration and modernization: Migrate (rehost) and modernization (run in the cloud)
* Application development
* Build pipeline
* Application deployment
* Environent creation
* Application operations
* Cloud topology
* Security

## Evolution of application architecture

* Mainframe Application
* Desktop Application
* Client/Server Application
* Cloud-Native Application