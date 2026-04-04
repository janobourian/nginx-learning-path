# Step-by-Step Migration Guide

This guide walks through a concrete migration of a **SQL Server** database from on-premises to **Amazon Aurora PostgreSQL** using AWS DMS. All commands use the AWS CLI.

!!! note "Adapt to Your Scenario"
    Replace engine-specific commands with equivalents for your source/target combination. See the [DMS Step-by-Step Walkthroughs](https://docs.aws.amazon.com/dms/latest/sbs/dms-sbs-welcome.html) for other engine combinations.

---

## Step 1: Set Up Network Connectivity

### 1.1 Create a VPC

```bash
aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=db-migration-vpc}]'
```

Save the `VpcId` from the output for subsequent commands.

### 1.2 Create Private Subnets (two AZs required for RDS/Aurora)

```bash
# Subnet in AZ-a
aws ec2 create-subnet \
    --vpc-id <vpc-id> \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-migration-private-1a}]'

# Subnet in AZ-b
aws ec2 create-subnet \
    --vpc-id <vpc-id> \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-migration-private-1b}]'
```

### 1.3 Establish VPN Connectivity to On-Premises

```bash
# Create Virtual Private Gateway
aws ec2 create-vpn-gateway --type ipsec.1

# Attach to VPC
aws ec2 attach-vpn-gateway \
    --vpn-gateway-id <vgw-id> \
    --vpc-id <vpc-id>

# Create Customer Gateway (your on-premises router public IP)
aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip <your-router-public-ip> \
    --bgp-asn 65000

# Create VPN Connection
aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id <cgw-id> \
    --vpn-gateway-id <vgw-id>
```

!!! tip "Direct Connect"
    For databases larger than 500 GB, consider [AWS Direct Connect](https://docs.aws.amazon.com/directconnect/latest/UserGuide/Welcome.html) for dedicated bandwidth (1/10/100 Gbps). VPN is limited to ~1.25 Gbps per tunnel.

### 1.4 Update Route Tables

```bash
# Enable route propagation from VPN gateway
aws ec2 enable-vgw-route-propagation \
    --gateway-id <vgw-id> \
    --route-table-id <rtb-id>
```

### 1.5 Verify Connectivity

Launch a test EC2 instance in the VPC and verify:

```bash
# Test connectivity to source database
nc -zv <source-db-ip> 1433

# Expected output: Connection to <source-db-ip> 1433 port [tcp/ms-sql-s] succeeded!
```

---

## Step 2: Create Security Groups

```bash
# Security group for DMS replication instance
# Per DMS docs: allow all egress for DMS to communicate with source and target
aws ec2 create-security-group \
    --group-name dms-replication-sg \
    --description "DMS replication instance - all egress allowed" \
    --vpc-id <vpc-id>

# Security group for target Aurora
aws ec2 create-security-group \
    --group-name aurora-target-sg \
    --description "Aurora target - ingress from DMS only" \
    --vpc-id <vpc-id>

# Allow DMS to connect to Aurora (PostgreSQL port 5432)
aws ec2 authorize-security-group-ingress \
    --group-id <sg-aurora-id> \
    --protocol tcp \
    --port 5432 \
    --source-group <sg-dms-id>
```

!!! info "Reference"
    Per [DMS VPC documentation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.VPC.html): "Make sure that the elastic network interface allocated for your replication instance's VPC is associated with a security group whose rules let all traffic on all ports leave (egress) the VPC."

---

## Step 3: Create IAM Roles for DMS

If this is your first time using DMS via CLI (the console creates these automatically):

```bash
# Create dms-vpc-role
aws iam create-role \
    --role-name dms-vpc-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "dms.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

aws iam attach-role-policy \
    --role-name dms-vpc-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole

# Create dms-cloudwatch-logs-role
aws iam create-role \
    --role-name dms-cloudwatch-logs-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "dms.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

aws iam attach-role-policy \
    --role-name dms-cloudwatch-logs-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole
```

---

## Step 4: Prepare Source Database (SQL Server)

Connect to your on-premises SQL Server and run:

```sql
-- 1. Create dedicated DMS user
USE [master]
GO
CREATE LOGIN dms_user WITH PASSWORD = '<strong-password>';
GO

USE [your_database]
GO
CREATE USER dms_user FOR LOGIN dms_user;
GO

-- 2. Grant required permissions
EXEC sp_addrolemember 'db_datareader', 'dms_user';
EXEC sp_addrolemember 'db_owner', 'dms_user';
GO

-- 3. Set recovery model to FULL (required for CDC)
ALTER DATABASE [your_database] SET RECOVERY FULL WITH NO_WAIT
GO

-- 4. Enable CDC on the database
USE [your_database]
GO
EXEC sys.sp_cdc_enable_db
GO

-- 5. Enable CDC on each table you want to migrate
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'customers',
    @role_name = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'orders',
    @role_name = NULL;
GO

-- Repeat for each table...

-- 6. Verify CDC is enabled
SELECT name, is_cdc_enabled FROM sys.databases WHERE name = 'your_database';
SELECT name, is_tracked_by_cdc FROM sys.tables WHERE is_tracked_by_cdc = 1;
```

---

## Step 5: Create Target Aurora PostgreSQL Cluster

```bash
# Create DB subnet group (requires subnets in at least 2 AZs)
aws rds create-db-subnet-group \
    --db-subnet-group-name db-migration-subnet-group \
    --db-subnet-group-description "Subnets for migration target" \
    --subnet-ids '["<subnet-1a-id>","<subnet-1b-id>"]'

# Create Aurora PostgreSQL cluster
# Note: backups and Multi-AZ disabled during migration for performance
aws rds create-db-cluster \
    --db-cluster-identifier migration-target-cluster \
    --engine aurora-postgresql \
    --engine-version 15.4 \
    --master-username dbadmin \
    --master-user-password '<strong-password>' \
    --db-subnet-group-name db-migration-subnet-group \
    --vpc-security-group-ids <sg-aurora-id> \
    --storage-encrypted \
    --kms-key-id alias/aws/rds \
    --backup-retention-period 1 \
    --no-deletion-protection

# Create Aurora writer instance
aws rds create-db-instance \
    --db-instance-identifier migration-target-instance-1 \
    --db-cluster-identifier migration-target-cluster \
    --db-instance-class db.r6g.xlarge \
    --engine aurora-postgresql

# Wait for instance to be available
aws rds wait db-instance-available \
    --db-instance-identifier migration-target-instance-1
```

---

## Step 6: Apply Schema to Target

### Option A: Using AWS SCT (Heterogeneous — SQL Server to PostgreSQL)

1. Download and install [AWS SCT](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Installing.html)
2. Create a new project → connect to source SQL Server
3. Connect to target Aurora PostgreSQL
4. Right-click source schema → **Convert Schema**
5. Review the conversion report:
    * Green = auto-converted
    * Blue = converted with warnings (review)
    * Red = cannot auto-convert (manual fix required)
6. Fix red items manually
7. Right-click target schema → **Apply to Database**

### Option B: Manual Schema Export/Import

```bash
# If you have the schema as SQL files from SCT or manual export:
psql -h <aurora-cluster-endpoint> \
     -U dbadmin -d your_database \
     -f schema_tables_only.sql

# Apply primary keys
psql -h <aurora-cluster-endpoint> \
     -U dbadmin -d your_database \
     -f schema_primary_keys.sql
```

!!! warning "Defer Foreign Keys and Triggers"
    Per [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html): "For a full load task, drop primary key indexes, secondary indexes, referential integrity constraints, and DML triggers." Apply foreign keys and triggers after full load completes.

---

## Step 7: Set Up AWS DMS

### 7.1 Create Replication Subnet Group

```bash
aws dms create-replication-subnet-group \
    --replication-subnet-group-identifier db-migration-subnet-group \
    --replication-subnet-group-description "DMS subnet group" \
    --subnet-ids '["<subnet-1a-id>","<subnet-1b-id>"]'
```

### 7.2 Create Replication Instance

```bash
aws dms create-replication-instance \
    --replication-instance-identifier onprem-to-aurora-replication \
    --replication-instance-class dms.r5.xlarge \
    --allocated-storage 100 \
    --vpc-security-group-ids <sg-dms-id> \
    --replication-subnet-group-identifier db-migration-subnet-group \
    --no-publicly-accessible \
    --no-multi-az

# Wait for instance to be available
aws dms wait replication-instance-available \
    --filters "Name=replication-instance-id,Values=onprem-to-aurora-replication"
```

### 7.3 Create Source Endpoint

```bash
aws dms create-endpoint \
    --endpoint-identifier source-sqlserver-onprem \
    --endpoint-type source \
    --engine-name sqlserver \
    --server-name <on-premises-ip-or-dns> \
    --port 1433 \
    --database-name your_database \
    --username dms_user \
    --password '<password>' \
    --ssl-mode require
```

### 7.4 Create Target Endpoint

```bash
# Get the Aurora cluster endpoint
AURORA_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier migration-target-cluster \
    --query "DBClusters[0].Endpoint" --output text)

aws dms create-endpoint \
    --endpoint-identifier target-aurora-pg \
    --endpoint-type target \
    --engine-name aurora-postgresql \
    --server-name $AURORA_ENDPOINT \
    --port 5432 \
    --database-name your_database \
    --username dbadmin \
    --password '<password>' \
    --ssl-mode require
```

### 7.5 Test Endpoint Connections

```bash
# Get replication instance ARN
REP_ARN=$(aws dms describe-replication-instances \
    --filters "Name=replication-instance-id,Values=onprem-to-aurora-replication" \
    --query "ReplicationInstances[0].ReplicationInstanceArn" --output text)

# Get endpoint ARNs
SOURCE_ARN=$(aws dms describe-endpoints \
    --filters "Name=endpoint-id,Values=source-sqlserver-onprem" \
    --query "Endpoints[0].EndpointArn" --output text)

TARGET_ARN=$(aws dms describe-endpoints \
    --filters "Name=endpoint-id,Values=target-aurora-pg" \
    --query "Endpoints[0].EndpointArn" --output text)

# Test source connection
aws dms test-connection \
    --replication-instance-arn $REP_ARN \
    --endpoint-arn $SOURCE_ARN

# Test target connection
aws dms test-connection \
    --replication-instance-arn $REP_ARN \
    --endpoint-arn $TARGET_ARN

# Check connection status (wait a few seconds)
aws dms describe-connections \
    --filter "Name=endpoint-arn,Values=$SOURCE_ARN,$TARGET_ARN" \
    --query "Connections[].{Endpoint:EndpointIdentifier,Status:Status}"
```

Both connections must show `Status: successful` before proceeding.

### 7.6 Create Table Mappings File

Create `table-mappings.json`:

```json
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all-dbo-tables",
            "object-locator": {
                "schema-name": "dbo",
                "table-name": "%"
            },
            "rule-action": "include"
        },
        {
            "rule-type": "transformation",
            "rule-id": "2",
            "rule-name": "rename-schema-to-public",
            "rule-action": "rename",
            "rule-target": "schema",
            "object-locator": {
                "schema-name": "dbo"
            },
            "value": "public"
        },
        {
            "rule-type": "transformation",
            "rule-id": "3",
            "rule-name": "convert-table-names-to-lowercase",
            "rule-action": "convert-lowercase",
            "rule-target": "table",
            "object-locator": {
                "schema-name": "dbo",
                "table-name": "%"
            }
        },
        {
            "rule-type": "transformation",
            "rule-id": "4",
            "rule-name": "convert-column-names-to-lowercase",
            "rule-action": "convert-lowercase",
            "rule-target": "column",
            "object-locator": {
                "schema-name": "dbo",
                "table-name": "%",
                "column-name": "%"
            }
        }
    ]
}
```

!!! tip "Why Lowercase?"
    PostgreSQL folds unquoted identifiers to lowercase. Converting names during migration avoids quoting issues in application queries.

### 7.7 Create Task Settings File

Create `task-settings.json`:

```json
{
    "TargetMetadata": {
        "TargetSchema": "",
        "SupportLobs": true,
        "FullLobMode": false,
        "LobChunkSize": 64,
        "LimitedSizeLobMode": true,
        "LobMaxSize": 32,
        "InlineLobMaxSize": 0,
        "LoadMaxFileSize": 0,
        "ParallelLoadThreads": 0,
        "ParallelLoadBufferSize": 0,
        "BatchApplyEnabled": false
    },
    "FullLoadSettings": {
        "MaxFullLoadSubTasks": 8,
        "TransactionConsistencyTimeout": 600,
        "CommitRate": 10000
    },
    "Logging": {
        "EnableLogging": true,
        "LogComponents": [
            {"Id": "TRANSFORMATION", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "SOURCE_UNLOAD", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "IO", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "TARGET_LOAD", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "PERFORMANCE", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "SOURCE_CAPTURE", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "SORTER", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "REST_SERVER", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "VALIDATOR_EXT", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "TARGET_APPLY", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "TASK_MANAGER", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "TABLES_MANAGER", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "METADATA_MANAGER", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "FILE_FACTORY", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "COMMON", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "ADDONS", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "DATA_STRUCTURE", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "COMMUNICATION", "Severity": "LOGGER_SEVERITY_DEFAULT"},
            {"Id": "FILE_TRANSFER", "Severity": "LOGGER_SEVERITY_DEFAULT"}
        ]
    },
    "ValidationSettings": {
        "EnableValidation": true,
        "ThreadCount": 5,
        "FailureMaxCount": 10000,
        "TableFailureMaxCount": 1000,
        "HandleCollationDiff": false,
        "ValidationPartialLobSize": 0,
        "PartitionSize": 10000
    },
    "ControlTablesSettings": {
        "historyTimeslotInMinutes": 5,
        "ControlSchema": "dms_control",
        "HistoryTimeslotInMinutes": 5,
        "HistoryTableEnabled": true,
        "SuspendedTablesTableEnabled": true,
        "StatusTableEnabled": true
    }
}
```

### 7.8 Create and Start Migration Task

```bash
# Create the task
aws dms create-replication-task \
    --replication-task-identifier full-load-and-cdc-task \
    --source-endpoint-arn $SOURCE_ARN \
    --target-endpoint-arn $TARGET_ARN \
    --replication-instance-arn $REP_ARN \
    --migration-type full-load-and-cdc \
    --table-mappings file://table-mappings.json \
    --replication-task-settings file://task-settings.json

# Wait for task to be ready
aws dms wait replication-task-ready \
    --filters "Name=replication-task-id,Values=full-load-and-cdc-task"

# Run premigration assessment first
TASK_ARN=$(aws dms describe-replication-tasks \
    --filters "Name=replication-task-id,Values=full-load-and-cdc-task" \
    --query "ReplicationTasks[0].ReplicationTaskArn" --output text)

aws dms start-replication-task-assessment-run \
    --replication-task-arn $TASK_ARN \
    --service-access-role-arn arn:aws:iam::<account>:role/dms-vpc-role \
    --result-location-bucket <your-s3-bucket> \
    --assessment-run-name pre-migration-check

# After assessment passes, start the task
aws dms start-replication-task \
    --replication-task-arn $TASK_ARN \
    --start-replication-task-type start-replication
```

---

## Step 8: Monitor Migration

### 8.1 Check Task Status

```bash
# Overall task status and progress
aws dms describe-replication-tasks \
    --filters "Name=replication-task-arn,Values=$TASK_ARN" \
    --query "ReplicationTasks[0].{
        Status:Status,
        FullLoadProgress:ReplicationTaskStats.FullLoadProgressPercent,
        TablesLoaded:ReplicationTaskStats.TablesLoaded,
        TablesLoading:ReplicationTaskStats.TablesLoading,
        TablesErrored:ReplicationTaskStats.TablesErrored,
        CDCLatency:ReplicationTaskStats.CDCLatencyTarget
    }"
```

### 8.2 Check Per-Table Statistics

```bash
aws dms describe-table-statistics \
    --replication-task-arn $TASK_ARN \
    --query "TableStatistics[].{
        Schema:SchemaName,
        Table:TableName,
        State:TableState,
        RowsInserted:Inserts,
        RowsUpdated:Updates,
        RowsDeleted:Deletes,
        FullLoadRows:FullLoadRows,
        ValidationState:ValidationState
    }" --output table
```

### 8.3 Monitor Replication Instance Metrics

```bash
# Check CPU utilization
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DMS" \
    --metric-name "CPUUtilization" \
    --dimensions Name=ReplicationInstanceIdentifier,Value=onprem-to-aurora-replication \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average

# Check freeable memory
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DMS" \
    --metric-name "FreeableMemory" \
    --dimensions Name=ReplicationInstanceIdentifier,Value=onprem-to-aurora-replication \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

---

## Step 9: Cutover

### 9.1 Pre-Cutover Validation

```bash
# Verify all tables are validated
aws dms describe-table-statistics \
    --replication-task-arn $TASK_ARN \
    --query "TableStatistics[?ValidationState!='Validated'].{
        Table:TableName,
        State:ValidationState,
        Pending:ValidationPendingRecords,
        Failed:ValidationFailedRecords
    }"
# Expected: empty result (all tables validated)
```

### 9.2 Execute Cutover

1. **Announce maintenance window** to all stakeholders

2. **Stop application writes** to source database

3. **Wait for CDC lag to reach zero:**

    ```bash
    # Monitor until CDCLatencyTarget = 0 and CDCIncomingChanges = 0
    watch -n 5 "aws dms describe-replication-tasks \
        --filters 'Name=replication-task-arn,Values=$TASK_ARN' \
        --query 'ReplicationTasks[0].ReplicationTaskStats.{
            CDCLatency:CDCLatencyTarget,
            IncomingChanges:CDCIncomingChanges
        }'"
    ```

4. **Apply deferred schema objects to target:**

    ```bash
    # Add foreign keys
    psql -h $AURORA_ENDPOINT -U dbadmin -d your_database \
        -f schema_foreign_keys.sql

    # Add secondary indexes
    psql -h $AURORA_ENDPOINT -U dbadmin -d your_database \
        -f schema_indexes.sql

    # Enable triggers
    psql -h $AURORA_ENDPOINT -U dbadmin -d your_database \
        -f schema_triggers.sql
    ```

5. **Run final row count validation:**

    ```bash
    # Compare source and target row counts
    psql -h $AURORA_ENDPOINT -U dbadmin -d your_database -c "
        SELECT schemaname, relname, n_live_tup
        FROM pg_stat_user_tables
        ORDER BY schemaname, relname;"
    ```

6. **Update application connection strings** to Aurora endpoint

7. **Restart application services**

8. **Verify application functionality** — run smoke tests

9. **Stop DMS replication task:**

    ```bash
    aws dms stop-replication-task \
        --replication-task-arn $TASK_ARN
    ```

---

## Step 10: Post-Cutover

```bash
# Re-enable automated backups (increase retention)
aws rds modify-db-cluster \
    --db-cluster-identifier migration-target-cluster \
    --backup-retention-period 7 \
    --apply-immediately

# Enable deletion protection
aws rds modify-db-cluster \
    --db-cluster-identifier migration-target-cluster \
    --deletion-protection \
    --apply-immediately

# Add a read replica for read scaling (optional)
aws rds create-db-instance \
    --db-instance-identifier migration-target-reader-1 \
    --db-cluster-identifier migration-target-cluster \
    --db-instance-class db.r6g.xlarge \
    --engine aurora-postgresql
```

After the rollback window (7–14 days):

```bash
# Delete DMS resources
aws dms delete-replication-task --replication-task-arn $TASK_ARN
aws dms delete-endpoint --endpoint-arn $SOURCE_ARN
aws dms delete-endpoint --endpoint-arn $TARGET_ARN
aws dms delete-replication-instance --replication-instance-arn $REP_ARN
```
