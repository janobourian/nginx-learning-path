# Testing and Validation

Thorough testing is critical to ensure data integrity and application compatibility. AWS DMS provides built-in [data validation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html) that compares each row in the source with its corresponding row at the target, verifies the rows contain the same data, and reports any mismatches.

---

## DMS Built-in Data Validation

### How It Works

When validation is enabled, DMS begins comparing source and target data immediately after a full load completes for each table. During CDC, DMS validates changes as they are applied.

DMS validation compares rows using primary key lookups and verifies that column values match. It supports the following databases as both source and target:

* Oracle
* PostgreSQL
* MySQL / MariaDB
* Microsoft SQL Server
* Amazon Aurora (MySQL and PostgreSQL compatible)
* IBM Db2 LUW
* Amazon Redshift

!!! info "Reference"
    [AWS DMS Data Validation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html)

### Validation Task Settings

```json
{
    "ValidationSettings": {
        "EnableValidation": true,
        "ThreadCount": 5,
        "ValidationOnly": false,
        "FailureMaxCount": 10000,
        "HandleCollationDiff": false,
        "RecordFailureDelayLimitInMinutes": 0,
        "TableFailureMaxCount": 1000,
        "ValidationPartialLobSize": 0,
        "PartitionSize": 10000
    }
}
```

| Setting | Description |
|---------|-------------|
| `ThreadCount` | Number of parallel validation threads (default 5) |
| `FailureMaxCount` | Stop validation after this many failures across all tables |
| `TableFailureMaxCount` | Stop validating a table after this many failures |
| `PartitionSize` | Number of records to validate per batch |
| `HandleCollationDiff` | Set `true` if source and target have different collation settings |

### Validation States

| State | Meaning |
|-------|---------|
| `Not enabled` | Validation not turned on for this task |
| `Pending records` | Validation in progress |
| `Mismatched records` | Source and target rows don't match |
| `Suspended records` | Validation couldn't be performed (e.g., no PK) |
| `No primary key` | Table has no PK — DMS cannot validate |
| `Table error` | Table is in an error state |
| `Validated` | All rows match between source and target |

### Check Validation Results

```bash
# Show tables that are NOT validated
aws dms describe-table-statistics \
    --replication-task-arn <task-arn> \
    --query "TableStatistics[?ValidationState!='Validated'].{
        Table:TableName,
        State:ValidationState,
        Pending:ValidationPendingRecords,
        Failed:ValidationFailedRecords,
        Suspended:ValidationSuspendedRecords
    }" --output table
```

### Data Resync for Failed Validations

DMS can automatically fix validation failures using the [data resync feature](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.DataResync.html). It reads validation failures from a control table on the target and executes fix-up operations.

---

## Manual Data Validation (Complementary)

Use these queries alongside DMS validation for additional confidence.

### Level 1: Row Count Validation

**Source (SQL Server):**

```sql
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
```

**Target (PostgreSQL):**

```sql
-- Exact counts (slower but accurate)
SELECT
    schemaname,
    relname AS table_name,
    (SELECT COUNT(*) FROM public."" || relname || '"') AS row_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;
```

!!! tip "Quick Estimate"
    For a fast estimate, use `n_live_tup` from `pg_stat_user_tables`. Run `ANALYZE` first to refresh statistics. For exact counts, use `SELECT COUNT(*)` per table.

### Level 2: Aggregate Validation

Compare aggregated values for numeric columns on both source and target:

```sql
-- Run on BOTH source and target, compare results
SELECT
    COUNT(*) AS total_rows,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount), 2) AS avg_amount,
    MIN(created_at) AS earliest_record,
    MAX(created_at) AS latest_record
FROM orders;
```

### Level 3: Sample Data Comparison

For critical tables, compare random samples:

```sql
-- Source (SQL Server)
SELECT TOP 100 *
FROM dbo.orders
WHERE order_id IN (
    SELECT TOP 100 order_id FROM dbo.orders ORDER BY NEWID()
)
ORDER BY order_id;

-- Target (PostgreSQL)
SELECT *
FROM public.orders
WHERE order_id IN (
    SELECT order_id FROM public.orders ORDER BY RANDOM() LIMIT 100
)
ORDER BY order_id;
```

### Level 4: Checksum Validation

For tables with numeric PKs, compute checksums:

```sql
-- PostgreSQL: MD5 checksum of all rows (ordered by PK)
SELECT MD5(STRING_AGG(
    CAST(ROW(id, name, amount, created_at) AS TEXT), ','
    ORDER BY id
)) AS table_checksum
FROM orders;
```

---

## Schema Validation

After migration, verify all schema objects were created correctly on the target.

### Verify Table Structure

```sql
-- PostgreSQL: List all tables and columns with data types
SELECT
    table_schema,
    table_name,
    column_name,
    data_type,
    character_maximum_length,
    numeric_precision,
    numeric_scale,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
```

### Verify Indexes

```sql
-- PostgreSQL: List all indexes
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

### Verify Constraints

```sql
-- PostgreSQL: List all constraints (PK, FK, UNIQUE, CHECK)
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    STRING_AGG(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public'
GROUP BY tc.table_name, tc.constraint_name, tc.constraint_type
ORDER BY tc.table_name, tc.constraint_type;
```

### Verify Stored Procedures and Functions

```sql
-- PostgreSQL: List all functions/procedures
SELECT
    routine_schema,
    routine_name,
    routine_type,
    data_type AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY routine_name;
```

### Verify Triggers

```sql
-- PostgreSQL: List all triggers
SELECT
    trigger_schema,
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;
```

### Schema Object Count Comparison

Create a summary to compare with source:

```sql
-- PostgreSQL: Count of each object type
SELECT 'Tables' AS object_type, COUNT(*) AS count
FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Views', COUNT(*)
FROM information_schema.views WHERE table_schema = 'public'
UNION ALL
SELECT 'Indexes', COUNT(*)
FROM pg_indexes WHERE schemaname = 'public'
UNION ALL
SELECT 'Functions', COUNT(*)
FROM information_schema.routines WHERE routine_schema = 'public'
UNION ALL
SELECT 'Triggers', COUNT(*)
FROM information_schema.triggers WHERE trigger_schema = 'public'
UNION ALL
SELECT 'Foreign Keys', COUNT(*)
FROM information_schema.table_constraints WHERE table_schema = 'public' AND constraint_type = 'FOREIGN KEY';
```

---

## Connection Testing

### Test Direct Database Connectivity

```bash
# PostgreSQL (Aurora) — basic connection
psql -h <aurora-cluster-endpoint> \
     -U dbadmin -d your_database -c "SELECT version();"

# Verify SSL connection
psql "host=<aurora-cluster-endpoint> \
      port=5432 dbname=your_database user=dbadmin \
      sslmode=verify-full sslrootcert=global-bundle.pem" \
     -c "SELECT ssl_is_used();"
```

Download the RDS CA certificate bundle from: [Amazon RDS SSL/TLS Certificates](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)

### Test Network Connectivity

```bash
# TCP connectivity test
nc -zv <aurora-cluster-endpoint> 5432

# DNS resolution
nslookup <aurora-cluster-endpoint>

# Latency test
ping <aurora-cluster-endpoint>
```

### Test Application Connectivity

```bash
# Update application config temporarily to point to target
# Run health check
curl -s http://localhost:8080/health | jq .

# Run a read-only smoke test endpoint
curl -s http://localhost:8080/api/v1/status | jq .
```

### Connection Pool Validation

Verify your application connection pool settings are compatible with Aurora:

```sql
-- Check Aurora max connections (varies by instance class)
SHOW max_connections;

-- Check current active connections
SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active';

-- Check idle connections
SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle';
```

**Aurora PostgreSQL `max_connections` by instance class:**

| Instance Class | Approximate max_connections |
|----------------|----------------------------|
| db.r6g.large | ~1,600 |
| db.r6g.xlarge | ~3,200 |
| db.r6g.2xlarge | ~5,000 |

!!! info "Formula"
    Aurora PostgreSQL calculates `max_connections` as: `LEAST({DBInstanceClassMemory/9531392}, 5000)`. See [Aurora PostgreSQL parameters](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Reference.ParameterGroups.html).

---

## Performance Testing

### Baseline Critical Queries

Run your most critical queries on both source and target, compare execution times:

```sql
-- Enable timing in PostgreSQL
\timing on

-- Run your critical queries and capture execution plan
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT ... -- your critical query here
;
```

### Load Testing with pgbench

```bash
# Initialize pgbench tables (creates pgbench_accounts, pgbench_branches, etc.)
pgbench -i -h <aurora-cluster-endpoint> -U dbadmin -d your_database

# Run load test: 10 clients, 2 threads, 60 seconds
pgbench -h <aurora-cluster-endpoint> -U dbadmin -d your_database \
    -c 10 -j 2 -T 60 --progress=5

# Run with custom SQL script
pgbench -h <aurora-cluster-endpoint> -U dbadmin -d your_database \
    -c 10 -j 2 -T 60 -f custom_workload.sql --progress=5
```

### Performance Comparison Matrix

| Metric | Source Baseline | Target Result | Acceptable Threshold | Pass/Fail |
|--------|----------------|---------------|---------------------|-----------|
| Average query latency | ___ ms | ___ ms | ≤ 120% of source | |
| Transactions per second | ___ TPS | ___ TPS | ≥ 80% of source | |
| P99 query latency | ___ ms | ___ ms | ≤ 150% of source | |
| Connection time | ___ ms | ___ ms | < 500 ms | |
| Bulk insert rate | ___ rows/s | ___ rows/s | ≥ 70% of source | |

### Monitor Aurora Performance Insights

```bash
# Enable Performance Insights on the Aurora instance
aws rds modify-db-instance \
    --db-instance-identifier migration-target-instance-1 \
    --enable-performance-insights \
    --performance-insights-retention-period 7 \
    --apply-immediately
```

Use the [RDS Performance Insights console](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_PerfInsights.html) to identify top SQL queries, wait events, and resource bottlenecks.

---

## Application-Level Testing

### Smoke Tests

- [ ] Application starts and connects to target database
- [ ] Login/authentication works
- [ ] Basic CRUD operations succeed (create, read, update, delete)
- [ ] Reports and dashboards render correctly with accurate data
- [ ] Search functionality returns expected results
- [ ] File uploads/downloads work (if LOB-dependent)
- [ ] Pagination works correctly
- [ ] Date/time values display correctly (timezone handling)
- [ ] Special characters and Unicode data display correctly

### Regression Tests

- [ ] Run full automated test suite against target database
- [ ] Verify all API endpoints return expected responses
- [ ] Test batch jobs and scheduled tasks
- [ ] Test integrations with external systems
- [ ] Verify audit logging works correctly
- [ ] Test error handling and edge cases
- [ ] Verify transaction rollback behavior

### User Acceptance Testing (UAT)

- [ ] Key business workflows validated by end users
- [ ] Data accuracy confirmed by data owners (spot-check critical records)
- [ ] Performance acceptable for end users (subjective assessment)
- [ ] Reports match expected values
- [ ] Sign-off from application owners

---

## Rollback Testing

Before cutover, validate your rollback plan works:

1. **Verify source database is still operational** and has not been modified
2. **Test switching connection strings back** to source
3. **Confirm application works** against source after rollback
4. **Document rollback time** — must be within your RTO
5. **Test that DMS CDC can be restarted** if you need to attempt cutover again

!!! warning "Rollback Window"
    Keep the source database running and DMS task available for 7–14 days after cutover. After this window, decommission source and delete DMS resources.
