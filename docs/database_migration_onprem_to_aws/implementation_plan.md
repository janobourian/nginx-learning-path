# Implementation Plan

This plan follows the AWS three-phase migration framework and incorporates best practices from the [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html) and [Replication Instance Sizing Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.SizingReplicationInstance.html).

---

## Phase 1: Discovery and Assessment

### 1.1 Inventory Source Databases

Use [DMS Fleet Advisor](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_FleetAdvisor.html) for automated discovery, or collect manually:

| Attribute | Details | Why It Matters |
|-----------|---------|----------------|
| Database engine and version | e.g., SQL Server 2019 Enterprise | Determines DMS compatibility and CDC support |
| Size (data + indexes) | GB/TB | Drives replication instance sizing and task parallelism |
| Number of schemas/tables | — | Affects task partitioning strategy |
| Stored procedures, triggers, functions | Count and complexity | Determines SCT conversion effort |
| Linked servers / cross-database queries | Dependencies | Cannot be migrated by DMS; requires application changes |
| Replication or Always On setup | Current HA configuration | Must be disabled or accounted for during migration |
| Backup strategy and RPO/RTO | Current SLAs | Defines acceptable downtime window |
| Application connections | Connection strings, ports, protocols | Needed for cutover planning |
| Encryption (TDE, column-level) | At-rest and in-transit | Must be replicated on target (KMS) |
| Collation and character sets | Compatibility check | Mismatches cause data corruption in heterogeneous migrations |
| LOB columns | Count, average and max size per table | Drives LOB mode selection (limited vs full vs inline) |
| Tables without primary keys | Count | DMS handles these differently; batch apply falls back to transactional apply |

### 1.2 Run AWS DMS Premigration Assessment

AWS DMS provides a [premigration assessment](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.AssessmentReport.html) that evaluates components of a migration task to identify problems before running it. The assessment checks:

* Unsupported data types
* Source database configuration for CDC
* Target database compatibility
* LOB column handling
* Network connectivity

!!! tip "Diagnostic Support Scripts"
    AWS provides diagnostic support scripts for each source engine. Run these before migration to identify potential failures early. See [Working with diagnostic support scripts](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.html).

### 1.3 Assess Schema with AWS SCT

1. Install [AWS SCT](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html) on a machine with connectivity to the source database
2. Create a new project and connect to the source
3. Run the **Database Migration Assessment Report**
4. Review:
    * Conversion complexity (simple, medium, complex action items)
    * Objects that cannot be auto-converted (require manual effort)
    * Estimated manual effort in person-hours
5. For cloud-based schema conversion, consider [DMS Schema Conversion](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html) which supports SQL Server, Oracle, PostgreSQL, and MySQL sources

### 1.4 Run a Proof of Concept

AWS [strongly recommends](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html) running a small test migration to:

* Discover environment issues early
* Set a realistic migration timeline
* Benchmark initial full load and ongoing replication performance
* Understand network latency
* Identify data type and character-set conversion issues
* Determine how many tables are large, medium, and small
* Measure how long a test migration takes

### 1.5 Define Target Architecture

| Decision | Options | Considerations |
|----------|---------|----------------|
| Target engine | Same engine (homogeneous) vs different engine (heterogeneous) | Heterogeneous requires SCT; homogeneous can use native tools + DMS |
| Target service | EC2 self-managed, Amazon RDS, Amazon Aurora | Aurora for high performance; RDS for managed with engine flexibility |
| Instance class | db.r6g, db.r7g, db.x2g families | Size based on current workload metrics (CPU, memory, IOPS) |
| Storage type | gp3, io1, io2 | gp3 for general workloads; io1/io2 for high IOPS requirements |
| High availability | Multi-AZ (RDS), Aurora replicas | Multi-AZ for production; disable during migration for performance |
| VPC topology | Subnets, AZs, security groups | DMS replication instance must be in same VPC or have connectivity to target |

---

## Phase 2: Network and Security Setup

### 2.1 Network Architecture

Based on [DMS Network Configurations](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.VPC.html):

```text
On-Premises Data Center
    │
    ├── AWS Site-to-Site VPN (encrypted over internet, up to 1.25 Gbps per tunnel)
    │       OR
    ├── AWS Direct Connect (dedicated private connection, 1/10/100 Gbps)
    │
    └──► AWS VPC
            ├── Private Subnet AZ-a
            │     ├── DMS Replication Instance
            │     └── Target RDS/Aurora (primary)
            ├── Private Subnet AZ-b
            │     └── Target RDS/Aurora (standby, Multi-AZ)
            ├── Security Groups
            │     ├── sg-dms: allows egress to source and target ports
            │     └── sg-target: allows ingress from sg-dms
            └── NACLs: allow ephemeral ports for return traffic
```

!!! warning "Bandwidth"
    For large databases (TB+), Direct Connect is strongly recommended. VPN throughput is limited to ~1.25 Gbps per tunnel and is subject to internet variability. Calculate expected transfer time: `(Database Size in GB × 8) / (Bandwidth in Gbps × 3600) = hours`.

### 2.2 Security Configuration

| Component | Configuration | Reference |
|-----------|---------------|-----------|
| Security Groups | DMS replication instance SG must allow **all egress** (default). Target SG must allow inbound from DMS SG on DB port | [DMS VPC Security](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.VPC.html) |
| NACLs | Allow ephemeral ports (1024–65535) for return traffic | — |
| IAM Roles | `dms-vpc-role` and `dms-cloudwatch-logs-role` (auto-created by console, manual for CLI) | [DMS IAM Roles](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.IAMPermissions) |
| Encryption in transit | SSL/TLS on source and target endpoints | [Using SSL with DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.SSL.html) |
| Encryption at rest | KMS encryption on target RDS/Aurora | [RDS Encryption](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html) |
| Secrets Manager | Store database credentials; DMS supports Secrets Manager integration | [DMS Secrets Manager](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#security-iam-secretsmanager) |

### 2.3 Required IAM Roles for DMS

DMS requires two service-linked roles. If using the console for the first time, these are created automatically. For CLI/CloudFormation, create them manually:

**dms-vpc-role** (allows DMS to manage ENIs in your VPC):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "Service": "dms.amazonaws.com" },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

Attach the managed policy: `AmazonDMSVPCManagementRole`

**dms-cloudwatch-logs-role** (allows DMS to write CloudWatch logs):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "Service": "dms.amazonaws.com" },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

Attach the managed policy: `AmazonDMSCloudWatchLogsRole`

!!! info "Reference"
    [Creating IAM roles for DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Security.html#CHAP_Security.IAMPermissions)

---

## Phase 3: Schema Migration

### 3.1 Homogeneous Migration (Same Engine)

AWS DMS supports basic schema migration (tables and primary keys only). For a complete schema, use native tools:

| Source Engine | Tool | Command |
|---------------|------|---------|
| SQL Server | SSMS Generate Scripts or `sqlpackage` | `sqlpackage /Action:Export /SourceServerName:... /SourceDatabaseName:... /TargetFile:schema.bacpac` |
| MySQL | `mysqldump` | `mysqldump --no-data --routines --triggers -h host -u user -p dbname > schema.sql` |
| PostgreSQL | `pg_dump` | `pg_dump --schema-only -h host -U user -d dbname > schema.sql` |
| Oracle | Data Pump | `expdp user/pass DIRECTORY=dpump DUMPFILE=schema.dmp CONTENT=METADATA_ONLY` |

!!! warning "DMS Schema Limitations"
    Per the [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html): "AWS DMS doesn't automatically create secondary indexes, foreign keys, user accounts, and so on, in the target database." Always migrate schema separately.

### 3.2 Heterogeneous Migration (Different Engine)

Use AWS SCT or DMS Schema Conversion:

1. Connect to source and target
2. Convert schema objects (tables, indexes, views, triggers, stored procedures)
3. SCT converts PL/SQL or T-SQL to PgSQL or MySQL equivalent
4. Review conversion report — fix items marked as requiring manual intervention
5. Apply converted schema to target
6. Save the SCT project for audit trail

**DMS Schema Conversion** (cloud-based alternative to SCT) supports:

| Source | Target |
|--------|--------|
| SQL Server 2008 R2–2022 | Aurora MySQL, Aurora PostgreSQL, RDS MySQL, RDS PostgreSQL |
| Oracle 10.2–19c | Aurora MySQL, Aurora PostgreSQL, RDS MySQL, RDS PostgreSQL |
| PostgreSQL 9.2+ | Aurora MySQL, RDS MySQL |
| MySQL 5.5–8.0 | Aurora PostgreSQL, RDS PostgreSQL |

### 3.3 Schema Objects Migration Order

Apply schema in this order to avoid dependency issues:

1. **Tables** (without foreign keys) — data types, defaults, NOT NULL constraints
2. **Primary keys and unique constraints**
3. **Indexes** (for full load + CDC: add secondary indexes before CDC phase)
4. **Views**
5. **Stored procedures and functions**
6. **Triggers** (enable right before cutover, not during migration)
7. **Foreign keys** (add after full load completes)
8. **Sequences** (reset to correct values after migration)

!!! tip "Performance Best Practice"
    Per [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html): "For a full load task, drop primary key indexes, secondary indexes, referential integrity constraints, and DML triggers. Or delay their creation until after the full load tasks are complete."

### 3.4 Objects That Cannot Be Migrated by DMS

These require manual migration or application-level changes:

- [ ] Linked servers → Refactor to use application-level connections or AWS PrivateLink
- [ ] SQL Agent jobs → Migrate to AWS Lambda, Step Functions, or Amazon EventBridge Scheduler
- [ ] Database mail → Migrate to Amazon SES
- [ ] User accounts and permissions → Recreate on target with appropriate RDS/Aurora roles
- [ ] Server-level settings → Configure via RDS parameter groups and option groups

---

## Phase 4: Data Migration with AWS DMS

### 4.1 Replication Instance Sizing

Based on the [Replication Instance Sizing Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.SizingReplicationInstance.html):

**Key factors:**

| Factor | Impact | Recommendation |
|--------|--------|----------------|
| Database size | Determines parallelism and task count | For 2× 1TB schemas, partition into 4 tasks of 500GB each |
| LOB columns | LOBs are processed in memory (two-step: insert row, then update LOB) | Use R5/R6g (memory-optimized) instances |
| Transaction rate (TPS) | High TPS leads to high memory usage during CDC | Monitor `FreeableMemory`; scale up if swapping occurs |
| Number of tasks | Each task consumes CPU | Avoid more than 8 `MaxFullLoadSubTasks` per task |
| Table keys | Tables without PKs force transactional apply (slower) | Add PKs where possible before migration |

**Instance class recommendations:**

| Workload | Instance Class | vCPU | Memory | Use Case |
|----------|---------------|------|--------|----------|
| Testing / small migrations | dms.t3.medium | 2 | 4 GiB | < 100 GB, few tables |
| Medium migrations | dms.r5.large | 2 | 16 GiB | 100 GB–1 TB, moderate LOBs |
| Large migrations | dms.r5.xlarge | 4 | 32 GiB | 1–5 TB, many LOBs |
| Very large / high TPS | dms.r5.2xlarge+ | 8+ | 64+ GiB | 5+ TB, high CDC throughput |
| Heterogeneous (CPU-intensive) | dms.c5.xlarge+ | 4+ | 8+ GiB | Complex data type conversions |

!!! info "R5 vs C5"
    Per [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html): R5 instances are memory-optimized for high-throughput transaction systems. C5 instances are compute-optimized for heterogeneous migrations (e.g., Oracle to PostgreSQL) where data type conversion is CPU-intensive.

**Storage:**

* Default: 50 GB or 100 GB depending on instance class
* All DMS storage volumes are GP2 (SSD) with base performance of 3 IOPS/GB, bursting to 3,000 IOPS
* Monitor `ReadIOPS` + `WriteIOPS` — ensure sum doesn't exceed base performance
* Increase storage for: large transactions, multiple tasks, high LOB volume

**Multi-AZ:**

* Recommended for ongoing replication (provides HA and failover)
* During full load: if failover occurs, the full load task will fail and must be restarted
* Not required for one-time migrations with acceptable restart tolerance

### 4.2 Source Database Prerequisites for CDC

CDC requires specific configuration on each source engine. These must be done **before** creating the DMS task.

#### SQL Server

```sql
-- 1. Create dedicated DMS user
USE [master]
GO
CREATE LOGIN dms_user WITH PASSWORD = '<strong-password>';
GO
USE [your_database]
GO
CREATE USER dms_user FOR LOGIN dms_user;
EXEC sp_addrolemember 'db_datareader', 'dms_user';
EXEC sp_addrolemember 'db_owner', 'dms_user';
GO

-- 2. Set recovery model to FULL (required for CDC)
ALTER DATABASE [your_database] SET RECOVERY FULL WITH NO_WAIT
GO

-- 3. Enable CDC on the database
USE [your_database]
GO
EXEC sys.sp_cdc_enable_db
GO

-- 4. Enable CDC on each table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'your_table',
    @role_name = NULL;
GO

-- 5. Configure as distributor (required for MS-CDC)
USE [master]
GO
EXEC sp_adddistributor @distributor = @@SERVERNAME, @password = N'<password>'
GO
```

!!! warning "SQL Server Editions"
    CDC is only supported on Enterprise, Standard (2016+), and Developer editions. Express and Web editions do not support CDC.

#### PostgreSQL

```sql
-- 1. Configure logical replication (requires restart)
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;
-- Restart PostgreSQL after these changes

-- 2. Create dedicated DMS user with replication privilege
CREATE USER dms_user WITH PASSWORD '<strong-password>' REPLICATION;
GRANT USAGE ON SCHEMA public TO dms_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dms_user;

-- 3. Create a publication for all tables (PostgreSQL 10+)
CREATE PUBLICATION dms_publication FOR ALL TABLES;
```

#### MySQL

```ini
# In my.cnf or my.ini (requires restart)
[mysqld]
server-id              = 1
log_bin                = mysql-bin
binlog_format          = ROW
expire_logs_days       = 3
binlog_row_image       = FULL
binlog_checksum        = NONE
```

```sql
-- Create dedicated DMS user
CREATE USER 'dms_user'@'%' IDENTIFIED BY '<strong-password>';
GRANT SELECT, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'dms_user'@'%';
FLUSH PRIVILEGES;
```

#### Oracle

```sql
-- 1. Enable supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- 2. Enable supplemental logging for all columns (recommended)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- 3. Enable ARCHIVELOG mode (if not already enabled)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- 4. Create dedicated DMS user
CREATE USER dms_user IDENTIFIED BY "<strong-password>"
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;
GRANT CREATE SESSION TO dms_user;
GRANT SELECT ANY TABLE TO dms_user;
GRANT SELECT ANY TRANSACTION TO dms_user;
GRANT SELECT ON DBA_TABLESPACES TO dms_user;
GRANT EXECUTE ON DBMS_LOGMNR TO dms_user;
GRANT SELECT ON V_$LOG TO dms_user;
GRANT SELECT ON V_$LOGFILE TO dms_user;
GRANT SELECT ON V_$ARCHIVED_LOG TO dms_user;
GRANT SELECT ON V_$DATABASE TO dms_user;
GRANT SELECT ON V_$TRANSACTION TO dms_user;
GRANT LOGMINING TO dms_user;  -- Oracle 12c+
```

### 4.3 Configure DMS Endpoints

**Source endpoint settings:**

| Setting | Value | Notes |
|---------|-------|-------|
| Endpoint type | Source | — |
| Engine | `sqlserver`, `oracle`, `mysql`, `postgres` | Match your source |
| Server name | On-premises IP or DNS | Must be reachable from DMS replication instance |
| Port | 1433, 1521, 3306, 5432 | Default ports; adjust if custom |
| SSL mode | `require` or `verify-ca` | Always use SSL for on-premises connections |
| Extra connection attributes | Engine-specific | See [DMS endpoint settings](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Endpoints.html) |

**Target endpoint settings:**

| Setting | Value | Notes |
|---------|-------|-------|
| Endpoint type | Target | — |
| Engine | `aurora-postgresql`, `aurora`, `mysql`, `postgres`, `oracle`, `sqlserver` | Match your target |
| Server name | RDS/Aurora endpoint | Use cluster endpoint for Aurora |
| SSL mode | `require` or `verify-full` | Use `verify-full` with RDS CA certificate |

### 4.4 Create Migration Task

**Task settings:**

| Setting | Recommended Value | Rationale |
|---------|-------------------|-----------|
| Migration type | `full-load-and-cdc` | Migrates existing data + ongoing changes for minimal downtime |
| Target table preparation mode | `DO_NOTHING` | Schema already created separately |
| Stop task after full load | `DontStopTask` | Transition to CDC automatically |
| LOB column settings | See LOB section below | Depends on your data profile |
| Enable validation | `true` | Validates data integrity row-by-row |
| Enable CloudWatch logs | `true` | Essential for troubleshooting |
| Max full load sub-tasks | 8 (default) | Increase only for large replication instances (c5.xlarge+) |
| Batch optimized apply | Consider for CDC | Faster but temporarily violates referential integrity |

### 4.5 LOB Mode Selection

Based on [DMS LOB Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html):

| Mode | Behavior | Performance | When to Use |
|------|----------|-------------|-------------|
| **Limited LOB** (default) | Migrates LOBs up to `MaxLobSize` (default 32 KB); truncates larger ones | Best | Most LOBs are small and fit within the limit |
| **Full LOB** | Migrates all LOBs regardless of size via two-step process (insert row, then update LOB) | Slowest | You have large LOBs and cannot tolerate truncation |
| **Inline LOB** | Small LOBs transferred inline (efficient); large LOBs via lookup | Good | Mix of small and large LOBs; most are small |

**Inline LOB configuration** (set `FullLobMode: true` + `InlineLobMaxSize`):

```json
{
    "TargetMetadata": {
        "SupportLobs": true,
        "FullLobMode": true,
        "InlineLobMaxSize": 32,
        "LobChunkSize": 64,
        "LobMaxSize": 102400
    }
}
```

!!! tip "Per-Table LOB Settings"
    You can override task-level LOB settings per table using `lob-settings` in your `table-settings` rule. This is useful when different tables have different LOB characteristics.

### 4.6 Table Mappings

**Selection rules** (which tables to include):

```json
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all-dbo",
            "object-locator": {
                "schema-name": "dbo",
                "table-name": "%"
            },
            "rule-action": "include"
        }
    ]
}
```

**Transformation rules** (rename schema, filter columns):

```json
{
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-all",
            "object-locator": {
                "schema-name": "dbo",
                "table-name": "%"
            },
            "rule-action": "include"
        },
        {
            "rule-type": "transformation",
            "rule-id": "2",
            "rule-name": "rename-schema",
            "rule-action": "rename",
            "rule-target": "schema",
            "object-locator": {
                "schema-name": "dbo"
            },
            "value": "public"
        }
    ]
}
```

**Parallel load for large tables** (partition-based):

```json
{
    "rule-type": "table-settings",
    "rule-id": "3",
    "rule-name": "parallel-load-large-table",
    "object-locator": {
        "schema-name": "dbo",
        "table-name": "large_table"
    },
    "parallel-load": {
        "type": "ranges",
        "columns": ["id"],
        "boundaries": [
            ["1000000"],
            ["2000000"],
            ["3000000"]
        ]
    }
}
```

!!! info "Reference"
    [Table and collection settings rules](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TableMapping.SelectionTransformation.Tablesettings.html)

### 4.7 Monitor Migration Progress

**Key CloudWatch metrics** (from [DMS Monitoring](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Monitoring.html)):

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `CDCLatencySource` | Seconds of lag between source and replication instance | > 60s |
| `CDCLatencyTarget` | Seconds of lag between replication instance and target | > 60s |
| `CDCIncomingChanges` | Number of pending changes to be applied | Trending upward |
| `FullLoadThroughputRowsSource` | Rows read per second during full load | Baseline comparison |
| `FullLoadThroughputRowsTarget` | Rows written per second during full load | Baseline comparison |
| `CPUUtilization` | Replication instance CPU | > 80% sustained |
| `FreeableMemory` | Available memory on replication instance | < 1 GB |
| `FreeStorageSpace` | Available disk on replication instance | < 5 GB |
| `ReadIOPS` / `WriteIOPS` | Disk I/O operations | Sum > GP2 base IOPS |
| `SwapUsage` | Memory swapping to disk | > 0 (indicates memory pressure) |

**Set up SNS notifications** for DMS events:

```bash
aws dms create-event-subscription \
    --subscription-name migration-alerts \
    --sns-topic-arn arn:aws:sns:region:account:migration-topic \
    --source-type replication-task \
    --event-categories '["failure","state change"]'
```

!!! info "Reference"
    [DMS Events and Notifications](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Events.html)

### 4.8 Performance Optimization

Based on [DMS Best Practices — Improving Performance](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html):

| Technique | Description |
|-----------|-------------|
| **Drop indexes before full load** | Indexes incur maintenance overhead during bulk inserts; recreate after full load |
| **Disable triggers** | Insert/update/delete triggers cause errors during bulk load |
| **Disable foreign keys** | Referential integrity constraints are violated during parallel table loading |
| **Turn off backups on target** | Disable RDS automated backups and Multi-AZ until cutover |
| **Use multiple tasks** | Partition tables into separate tasks for parallelism (ensure no cross-task transactions) |
| **Parallel full load** | Use `parallel-load` in table-settings for large/partitioned tables |
| **Batch optimized apply** | Groups CDC transactions for efficiency (violates referential integrity temporarily) |
| **Increase MaxFullLoadSubTasks** | Default 8; increase for large replication instances only |
| **Row filtering for large tables** | Split migration of large tables by key ranges across multiple tasks |

---

## Cutover Strategy

### Pre-Cutover

1. Verify CDC replication is active and latency is stable
2. Run [DMS data validation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html) — all tables should show `Validated`
3. Add foreign keys and secondary indexes to target (if deferred)
4. Enable triggers on target
5. Run application smoke tests against target (read-only)
6. Communicate maintenance window to all stakeholders

### Cutover Execution

1. **Stop application writes** to source database
2. **Wait for CDC lag to reach zero** (`CDCLatencyTarget` = 0, `CDCIncomingChanges` = 0)
3. **Run final data validation** (row counts + checksums)
4. **Update application connection strings** to target endpoint
5. **Restart application services**
6. **Verify application functionality** end-to-end
7. **Stop DMS replication task**

### Post-Cutover

1. Monitor target database performance for 24–72 hours
2. Keep source database running for rollback window (7–14 days recommended)
3. Re-enable RDS automated backups and Multi-AZ on target
4. Delete DMS replication instance after rollback window
5. Update DNS records, documentation, and runbooks
6. Conduct post-migration review
7. Decommission source database after validation period
