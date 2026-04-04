# Migration Checklist

Printable checklist for tracking migration progress. Based on [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html) and [AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/phases.html).

---

## Phase 1: Assess

### Discovery & Planning

- [ ] Inventory all source databases (engine, version, size, schemas, table count)
- [ ] Identify LOB columns — count, average size, max size per table
- [ ] Identify tables without primary keys (DMS handles these differently)
- [ ] Identify all application dependencies and connection strings
- [ ] Document current RPO and RTO requirements
- [ ] Run [DMS diagnostic support scripts](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.html) on source
- [ ] Run AWS SCT or DMS Schema Conversion assessment report
- [ ] Run a proof of concept with a representative subset of tables
- [ ] Choose migration strategy (rehost, replatform, refactor)
- [ ] Select target database engine and instance size
- [ ] Define rollback plan and rollback criteria
- [ ] Get stakeholder sign-off on migration window and downtime budget
- [ ] Establish communication plan (teams, escalation contacts, status cadence)
- [ ] Estimate migration cost using [AWS Pricing Calculator](https://calculator.aws)

---

## Phase 2: Mobilize

### Network & Connectivity

- [ ] Establish VPN or Direct Connect between on-premises and AWS VPC
- [ ] Verify network latency (`< 100ms` recommended for DMS)
- [ ] Verify bandwidth is sufficient for data volume (calculate transfer time)
- [ ] Create VPC with private subnets in at least 2 AZs
- [ ] Create route tables with routes to on-premises via VPN/DX
- [ ] Test connectivity from VPC to source database (`nc -zv <source-ip> <port>`)

### Security

- [ ] Create security group for DMS replication instance (allow all egress)
- [ ] Create security group for target database (allow inbound from DMS SG on DB port)
- [ ] Configure NACLs for required ports and ephemeral return traffic
- [ ] Create IAM role `dms-vpc-role` with `AmazonDMSVPCManagementRole` policy
- [ ] Create IAM role `dms-cloudwatch-logs-role` with `AmazonDMSCloudWatchLogsRole` policy
- [ ] Store database credentials in AWS Secrets Manager
- [ ] Enable SSL/TLS on source and target endpoints
- [ ] Enable KMS encryption on target RDS/Aurora instance
- [ ] Download [RDS CA certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) for SSL verification

### Source Database Preparation

- [ ] Create a dedicated DMS user with required permissions
- [ ] Enable CDC on source database:
    - [ ] **SQL Server**: set recovery model to FULL, enable CDC on database and tables, configure distribution
    - [ ] **PostgreSQL**: set `wal_level = logical`, configure `max_replication_slots` and `max_wal_senders`, restart
    - [ ] **MySQL**: enable binary logging with `ROW` format, set `binlog_row_image = FULL`, restart
    - [ ] **Oracle**: enable supplemental logging (ALL COLUMNS), enable ARCHIVELOG mode
- [ ] Verify source database has sufficient resources for replication overhead (DMS reads transaction logs)
- [ ] Take a full backup of source database before migration

### Target Database Preparation

- [ ] Create RDS/Aurora instance with appropriate instance class and storage type
- [ ] Create DB subnet group spanning at least 2 AZs
- [ ] Configure parameter groups (match source settings where applicable: character set, collation, timezone)
- [ ] Configure option groups if needed (e.g., Oracle options)
- [ ] Disable Multi-AZ during migration (re-enable after cutover for performance)
- [ ] Disable automated backups during migration (re-enable after cutover)
- [ ] Create target database and schemas
- [ ] Apply schema using SCT output or native tools
- [ ] Apply tables and primary keys first; defer foreign keys, secondary indexes, and triggers
- [ ] Verify schema objects match source (table count, column count, data types)

---

## Phase 3: Migrate & Modernize

### Stage 1: Initialize — DMS Setup

- [ ] Create DMS replication subnet group
- [ ] Create DMS replication instance (same VPC as target, appropriate size)
- [ ] Wait for replication instance status = `available`
- [ ] Create source endpoint
- [ ] **Test source endpoint connection** — must show `successful`
- [ ] Create target endpoint
- [ ] **Test target endpoint connection** — must show `successful`
- [ ] Create migration task with appropriate settings:
    - [ ] Migration type: `full-load-and-cdc`
    - [ ] Table preparation mode: `DO_NOTHING`
    - [ ] LOB mode: selected based on data profile
    - [ ] Enable validation: `true`
    - [ ] Enable CloudWatch logs: `true`
- [ ] Configure table mappings (selection rules + transformation rules)
- [ ] Run [premigration assessment](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.AssessmentReport.html) — resolve all failures
- [ ] Set up SNS event subscription for task failures and state changes

### Stage 2: Implement — Full Load

- [ ] Start migration task
- [ ] Monitor full load progress in DMS console (Table Statistics tab)
- [ ] Monitor replication instance metrics: CPU, FreeableMemory, FreeStorageSpace, SwapUsage
- [ ] Check CloudWatch logs for errors or warnings
- [ ] Verify row counts match between source and target for each table
- [ ] Validate data types were mapped correctly (spot-check sample rows)
- [ ] Verify LOB data migrated completely (check for truncation in task logs)

### Stage 2: Implement — CDC (Ongoing Replication)

- [ ] Confirm task status transitions from `Load complete` to `Running` (CDC active)
- [ ] Monitor `CDCLatencySource` and `CDCLatencyTarget` — both should be < 60s
- [ ] Monitor `CDCIncomingChanges` — should trend toward zero
- [ ] Test INSERT, UPDATE, DELETE operations on source replicate correctly to target
- [ ] Monitor replication instance CPU and memory utilization
- [ ] If latency is high: scale up replication instance or reduce source load

---

## Validation

- [ ] Run DMS data validation — all tables should show `Validated` state
- [ ] Run row count comparison queries (source vs target)
- [ ] Run aggregate validation (SUM, MIN, MAX, AVG on numeric columns)
- [ ] Compare random sample rows for critical tables
- [ ] Verify all schema objects exist on target (tables, views, procedures, triggers, indexes)
- [ ] Validate foreign key relationships
- [ ] Run application-level smoke tests against target database (read-only)
- [ ] Verify stored procedures and functions execute correctly on target
- [ ] Run performance baseline queries — compare execution times with source

---

## Cutover

- [ ] Communicate maintenance window to all stakeholders
- [ ] Freeze application writes to source database
- [ ] Wait for CDC replication lag to reach zero (`CDCLatencyTarget` = 0)
- [ ] Wait for `CDCIncomingChanges` = 0
- [ ] Run final data validation (row counts + checksums)
- [ ] Add foreign keys to target database
- [ ] Add remaining secondary indexes to target database
- [ ] Enable triggers on target database
- [ ] Reset sequences to correct values on target
- [ ] Update application connection strings to target database endpoint
- [ ] Restart application services
- [ ] Verify application functionality end-to-end
- [ ] Monitor application logs for errors
- [ ] Stop DMS replication task

---

## Post-Cutover

- [ ] Monitor target database performance for 24–72 hours (CPU, memory, IOPS, connections)
- [ ] Monitor application response times and error rates
- [ ] Re-enable RDS automated backups on target
- [ ] Re-enable Multi-AZ on target
- [ ] Keep source database running for rollback window (7–14 days recommended)
- [ ] If rollback needed: switch connection strings back to source, verify application works
- [ ] After rollback window: stop DMS replication task
- [ ] After rollback window: delete DMS replication instance
- [ ] Update DNS records if applicable (e.g., CNAME to new RDS endpoint)
- [ ] Update documentation, runbooks, and monitoring dashboards
- [ ] Conduct post-migration review with team (lessons learned)
- [ ] Decommission source database after validation period
