# Troubleshooting

Common issues encountered during database migrations from on-premises to AWS, with solutions based on the [AWS DMS Troubleshooting Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting.html) and [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html).

---

## Connectivity Issues

### DMS Cannot Connect to Source

**Symptoms:** Endpoint test fails with timeout or connection refused.

| Cause | Diagnosis | Fix |
| ------- | ----------- | ----- |
| Firewall blocking port | `nc -zv <source-ip> <port>` from EC2 in same VPC | Open source DB port from DMS replication instance subnet CIDR on on-premises firewall |
| VPN tunnel is down | Check VPN status in VPC console | Verify on-premises router config; check tunnel status |
| Wrong IP/hostname | `nslookup <hostname>` from VPC | Verify source endpoint server name resolves correctly |
| SSL mismatch | Check endpoint SSL mode vs source DB SSL config | Match SSL mode; use `require` for on-premises connections |
| DMS SG missing egress | Check DMS replication instance security group | Ensure SG allows all outbound traffic (DMS requirement) |
| Source DB not listening | Check source DB service status | Verify database service is running and accepting remote connections |

```bash

# Verify from an EC2 instance in the same VPC/subnet as DMS
nc -zv <source-ip> 1433
telnet <source-ip> 1433
```

### DMS Cannot Connect to Target

**Symptoms:** Target endpoint test fails.

| Cause | Fix |
| ------- | ----- |
| Target SG missing ingress from DMS | Add inbound rule: DMS SG → target DB port |
| Target RDS not in same VPC | Use VPC peering or place DMS in target VPC |
| Database/user doesn't exist on target | Create database and user before testing endpoint |
| Wrong endpoint (reader vs writer) | Use the cluster **writer** endpoint for DMS target |

### Connection Test Shows "Testing" Indefinitely

* The replication instance may still be starting — wait for status `available`
* Check that the replication instance subnet has a route to the target
* Verify DNS resolution works from the VPC

---

## CDC Issues

### CDC Not Capturing Changes

### SQL Server

```sql
-- Verify CDC is enabled on the database
SELECT name, is_cdc_enabled FROM sys.databases WHERE name = 'your_database';
-- Expected: is_cdc_enabled = 1

-- Verify CDC is enabled on tables
SELECT name, is_tracked_by_cdc FROM sys.tables WHERE is_tracked_by_cdc = 1;

-- Check CDC agent jobs are running
EXEC sys.sp_cdc_help_jobs;
-- Both capture and cleanup jobs should exist and be enabled

-- Check SQL Server Agent is running
SELECT * FROM sys.dm_server_services WHERE servicename LIKE '%Agent%';
```

### PostgreSQL

```sql
-- Verify wal_level (must be 'logical')
SHOW wal_level;

-- Check replication slots
SELECT slot_name, plugin, active, restart_lsn FROM pg_replication_slots;

-- If slot is inactive, DMS may have disconnected
-- Check if max_replication_slots is sufficient
SHOW max_replication_slots;
SHOW max_wal_senders;
```

### MySQL

```sql
-- Verify binary logging is enabled
SHOW VARIABLES LIKE 'log_bin';          -- Must be ON
SHOW VARIABLES LIKE 'binlog_format';    -- Must be ROW
SHOW VARIABLES LIKE 'binlog_row_image'; -- Must be FULL

-- Check binary log retention
SHOW VARIABLES LIKE 'expire_logs_days';
-- Must be >= 1 day (3 recommended)
```

### Oracle

```sql
-- Verify supplemental logging
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;
-- Both should be YES

-- Verify ARCHIVELOG mode
SELECT LOG_MODE FROM V$DATABASE;
-- Must be ARCHIVELOG

-- Check LogMiner access
SELECT * FROM V$LOGMNR_CONTENTS WHERE ROWNUM < 5;
```

### High CDC Latency

Per [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html), high CDC latency can be caused by:

| Cause | Diagnosis | Fix |
| ------- | ----------- | ----- |
| Replication instance undersized | `CPUUtilization` > 80% or `FreeableMemory` < 1 GB | Scale up instance class |
| Large transactions on source | `CDCIncomingChanges` spikes | Consider batch optimized apply |
| Network bandwidth saturated | Check Direct Connect/VPN throughput metrics | Upgrade bandwidth or use Direct Connect |
| Target database slow to apply | Target `CPUUtilization` high, IOPS maxed | Scale up target instance or increase IOPS |
| Too many tasks on one replication instance | High CPU across all tasks | Distribute tasks across multiple replication instances |
| Memory swapping | `SwapUsage` > 0 | Scale up to memory-optimized instance (R5/R6g) |

```bash

# Monitor CDC latency over time
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DMS" \
    --metric-name "CDCLatencyTarget" \
    --dimensions Name=ReplicationInstanceIdentifier,Value=<instance-id> \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average Maximum
```

---

## Data Validation Failures

### Row Count Mismatch

| Cause | Fix |
| ------- | ----- |
| DMS skipped or errored rows | Check CloudWatch task logs for `SOURCE_UNLOAD` and `TARGET_LOAD` errors |
| Table mappings exclude rows | Verify selection rules don't have filters that exclude data |
| Tables without primary key | DMS may not migrate all rows; add a PK or use full LOB mode |
| Concurrent writes during validation | Wait for CDC to catch up; re-run validation |
| Filter conditions in table mappings | Review `object-locator` patterns — `%` matches all |

### Data Type Conversion Errors

Common problematic conversions (SQL Server → PostgreSQL):

| Source (SQL Server) | Target (PostgreSQL) | Issue | Solution |
| --------------------- | --------------------- | ------- | ---------- |
| `DATETIME` | `TIMESTAMP` | Precision differences (3ms vs 1μs) | Usually auto-handled; verify edge cases |
| `DATETIME2` | `TIMESTAMP` | Higher precision | Auto-converted |
| `MONEY` | `NUMERIC(19,4)` | Verify scale matches | Check SCT mapping |
| `NVARCHAR(MAX)` | `TEXT` | LOB handling required | Set appropriate LOB mode |
| `IMAGE` / `VARBINARY(MAX)` | `BYTEA` | LOB mode settings | Use Full LOB mode |
| `BIT` | `BOOLEAN` | Usually auto-converted | Verify in SCT report |
| `UNIQUEIDENTIFIER` | `UUID` | Requires explicit mapping | Use SCT or transformation rule |
| `HIERARCHYID` | No equivalent | Not supported by DMS | Manual migration required |
| `GEOGRAPHY` / `GEOMETRY` | `GEOMETRY` (PostGIS) | Requires PostGIS extension | Install PostGIS; manual mapping |
| `SQL_VARIANT` | No equivalent | Not supported | Flatten to specific type |

### LOB Migration Issues

**Symptoms:** LOB columns are truncated or NULL on target.

Per [DMS LOB Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html):

| Symptom | Cause | Fix |
| --------- | ------- | ----- |
| LOB truncated to 32 KB | Limited LOB mode with default `MaxLobSize` | Increase `LobMaxSize` or switch to Full LOB mode |
| LOB column is NULL | Target column is NOT NULL but DMS needs it nullable | Make LOB columns nullable on target |
| LOB data missing entirely | `SupportLobs` is `false` | Set `SupportLobs: true` in task settings |
| Slow LOB migration | Full LOB mode (two-step process per row) | Use Inline LOB mode for mixed LOB sizes |

### Task settings for Full LOB with Inline optimization

```json
{
    "TargetMetadata": {
        "SupportLobs": true,
        "FullLobMode": true,
        "LobChunkSize": 64,
        "LobMaxSize": 102400,
        "InlineLobMaxSize": 32
    }
}
```

!!! warning "LOB Column Nullable Requirement"
    Per DMS documentation: "All LOB columns on the target table must be nullable" during migration. This is because DMS inserts the row first (without LOB), then updates with the LOB value. Exception: homogeneous Oracle-to-Oracle in Limited LOB mode.

---

## Performance Issues

### Slow Full Load

Per [DMS Best Practices — Improving Performance](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html):

| Technique | Setting | Notes |
| ----------- | --------- | ------- |
| Increase parallel table loads | `MaxFullLoadSubTasks: 16` | Default 8; increase for large replication instances only |
| Increase commit rate | `CommitRate: 50000` | Default 10000; higher = fewer commits, faster load |
| Drop indexes before full load | Manual | Recreate after full load; indexes add overhead during bulk insert |
| Drop foreign keys | Manual | Referential integrity violated during parallel loading |
| Disable triggers | Manual | Triggers cause errors during bulk load |
| Disable backups on target | RDS setting | Re-enable after cutover |
| Use parallel load for large tables | `parallel-load` in table-settings | Partition by ranges or auto-partitions |
| Increase target IOPS | Use io1/io2 storage | GP3 may bottleneck on large loads |

```json
{
    "FullLoadSettings": {
        "MaxFullLoadSubTasks": 16,
        "TransactionConsistencyTimeout": 600,
        "CommitRate": 50000
    }
}
```

### Target Database High CPU During CDC

| Cause | Diagnosis | Fix |
| ------- | ----------- | ----- |
| Missing indexes on target | `EXPLAIN ANALYZE` shows sequential scans | Add indexes before CDC phase |
| Lock contention | `pg_stat_activity` shows waiting queries | Check for long-running transactions |
| Batch apply disabled | Transactional apply is slower | Enable `BatchApplyEnabled: true` (temporarily violates FK constraints) |
| Insufficient `work_mem` | Sort operations spill to disk | Increase `work_mem` in parameter group |

```sql
-- PostgreSQL: Check for long-running queries
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    state,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC
LIMIT 10;

-- Check for lock contention
SELECT
    blocked_locks.pid AS blocked_pid,
    blocking_locks.pid AS blocking_pid,
    blocked_activity.query AS blocked_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
WHERE NOT blocked_locks.granted;
```

### Replication Instance Running Out of Disk

```bash

# Check free storage
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DMS" \
    --metric-name "FreeStorageSpace" \
    --dimensions Name=ReplicationInstanceIdentifier,Value=<instance-id> \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Minimum
```

### Fixes

* Increase allocated storage: `aws dms modify-replication-instance --allocated-storage 200`
* Reduce task log verbosity
* Reduce number of concurrent tasks
* Large transactions cache to disk — scale up instance or reduce source transaction size

---

## Common Error Messages

| Error | Cause | Fix |
| ------- | ------- | ----- |
| `Last Error Stop Reason FATAL_ERROR` | Task crashed due to unrecoverable error | Check CloudWatch logs; restart task with `resume-processing` |
| `Error 1045 Access denied for user` | Wrong credentials | Verify username/password on endpoint |
| `Replication slot already exists` | Previous DMS task left orphaned slot | Drop slot on source: `SELECT pg_drop_replication_slot('slot_name');` |
| `No tables were found` | Wrong schema in table mappings | Verify `schema-name` in selection rules matches source |
| `LOB column has NULL value` | LOB mode misconfigured | Enable Full LOB mode or increase `LobMaxSize` |
| `Cannot connect to source/target` | Network or credential issue | Test endpoint connection; check SG, VPN, credentials |
| `The task was stopped due to a fatal error` | Various | Check CloudWatch logs for `TASK_MANAGER` component |
| `Disk space is low on the replication instance` | Cached changes exceed disk | Increase allocated storage or scale up instance |
| `CDC start position not found` | Transaction log was purged on source | Restart task with full load; increase log retention on source |
| `Table 'X' is being loaded by another task` | Overlapping table mappings across tasks | Ensure each table is in exactly one task |

---

## Diagnostic Tools

### CloudWatch Logs

DMS writes detailed logs to CloudWatch. Key log components:

| Component | What It Logs |
| ----------- | ------------- |
| `SOURCE_UNLOAD` | Reading data from source during full load |
| `SOURCE_CAPTURE` | CDC change capture from source |
| `TARGET_LOAD` | Writing data to target during full load |
| `TARGET_APPLY` | Applying CDC changes to target |
| `TASK_MANAGER` | Task lifecycle events, errors |
| `TABLES_MANAGER` | Table state transitions |
| `TRANSFORMATION` | Data type conversions and transformations |
| `VALIDATOR_EXT` | Data validation results |

```bash

# View recent task logs
aws logs get-log-events \
    --log-group-name dms-tasks-<task-id> \
    --log-stream-name dms-task-<task-id> \
    --limit 50
```

### Time Travel (Debug Logging)

For deep troubleshooting, enable [Time Travel](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.TimeTravel.html) to capture detailed change records:

!!! warning "Performance Impact"
    Time Travel adds overhead to the replication instance. Only enable for tasks that need debugging, and monitor instance metrics while it's active.

### DMS Diagnostic Support Scripts

AWS provides diagnostic scripts for each source engine. Run these before migration to identify potential issues:

* [SQL Server diagnostic script](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.SQLServer.html)
* [Oracle diagnostic script](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.Oracle.html)
* [MySQL diagnostic script](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.MySQL.html)
* [PostgreSQL diagnostic script](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SupportScripts.PostgreSQL.html)

---

## When to Contact AWS Support

Open a support case if:

* DMS task fails repeatedly with `FATAL_ERROR` and CloudWatch logs don't provide a clear cause
* Data validation shows persistent mismatches that cannot be explained
* Replication instance becomes unresponsive
* CDC latency increases continuously despite scaling up resources
* You encounter a suspected DMS bug

Include in your support case:

* DMS task ARN
* Replication instance identifier
* CloudWatch log excerpts around the error
* Results from diagnostic support scripts
* Source and target engine versions
