# Database Migration: On-Premises to AWS

## Overview

This section is a comprehensive technical paper for planning and executing a database migration from on-premises infrastructure to AWS. It follows the [AWS Prescriptive Guidance for Large Migrations](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/phases.html) three-phase approach: **Assess**, **Mobilize**, and **Migrate & Modernize**.

The goal is to provide a single reference that any team can follow end-to-end — from initial discovery through cutover and decommissioning.

---

## AWS Migration Framework (Three Phases)

AWS segments the migration process into three sequential phases. Completing the assess and mobilize phases builds a solid foundation to support the migration.

```text
┌─────────────────┐     ┌─────────────────┐     ┌──────────────────────────┐
│   1. ASSESS     │────►│   2. MOBILIZE   │────►│  3. MIGRATE & MODERNIZE  │
│                 │     │                 │     │                          │
│ • Business case │     │ • Landing zone  │     │ Stage 1: Initialize      │
│ • Readiness     │     │ • Portfolio     │     │  • Runbooks & SOPs       │
│ • Portfolio     │     │   assessment    │     │  • Proof of concept      │
│   discovery     │     │ • Security &    │     │                          │
│ • Stakeholder   │     │   operating     │     │ Stage 2: Implement       │
│   alignment     │     │   model         │     │  • Full load + CDC       │
│                 │     │ • Team prep     │     │  • Validation & cutover  │
└─────────────────┘     └─────────────────┘     └──────────────────────────┘
```

!!! info "Reference"
    [Phases of a large migration — AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/phases.html)

---

## Migration Strategies for Databases

AWS defines six common migration strategies (the 6 R's). For databases, the most relevant are:

| Strategy | Description | When to Use | Target |
|----------|-------------|-------------|--------|
| **Rehost** (Lift & Shift) | Move database as-is to EC2 | Minimal changes needed, tight timeline | EC2 self-managed |
| **Replatform** | Move to a managed service with minor adjustments | Reduce operational overhead, same engine | Amazon RDS |
| **Refactor** | Change database engine entirely | Cost optimization, modernization, license reduction | Amazon Aurora, RDS PostgreSQL/MySQL |

---

## AWS Services for Database Migration

| Service | Role in Migration | Documentation |
|---------|-------------------|---------------|
| **AWS DMS** | Data replication (full load + CDC) | [DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html) |
| **AWS SCT** | Schema conversion for heterogeneous migrations | [SCT User Guide](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html) |
| **DMS Fleet Advisor** | Automated discovery and inventory of source databases | [Fleet Advisor](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_FleetAdvisor.html) |
| **DMS Schema Conversion** | Cloud-based schema conversion (replaces SCT for supported engines) | [DMS Schema Conversion](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html) |
| **Amazon RDS** | Managed relational database (Oracle, SQL Server, MySQL, PostgreSQL, MariaDB) | [RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html) |
| **Amazon Aurora** | High-performance managed database (MySQL/PostgreSQL compatible) | [Aurora User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html) |
| **AWS Direct Connect / VPN** | Secure network connectivity between on-premises and AWS | [Direct Connect](https://docs.aws.amazon.com/directconnect/latest/UserGuide/Welcome.html) |
| **Amazon S3** | Intermediate storage for large dataset migrations or as a DMS target | [S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) |
| **Amazon CloudWatch** | Monitoring DMS tasks, replication instance metrics, and alerting | [CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html) |

---

## DMS Architecture: How It Works

An AWS DMS migration consists of five components:

1. **Discovery** of databases to migrate (Fleet Advisor)
2. **Schema conversion** (SCT or DMS Schema Conversion)
3. **Replication instance** — an EC2 instance running DMS replication software
4. **Source and target endpoints** — connection configurations
5. **Replication task** — defines what data to migrate and how

```text
┌──────────────────┐                                      ┌──────────────────┐
│  SOURCE DATABASE │                                      │  TARGET DATABASE │
│  (On-Premises)   │                                      │  (AWS)           │
│                  │     ┌──────────────────────────┐     │                  │
│  Oracle          │────►│  DMS REPLICATION INSTANCE │────►│  Amazon Aurora   │
│  SQL Server      │     │                          │     │  Amazon RDS      │
│  MySQL           │     │  • Reads source data     │     │  Amazon Redshift │
│  PostgreSQL      │     │  • Formats/converts      │     │  Amazon S3       │
│  MariaDB         │     │  • Applies to target     │     │  Amazon DynamoDB │
│  Db2             │     │  • Caches changes in     │     │                  │
│  MongoDB         │     │    memory or disk        │     │                  │
│  SAP ASE         │     └──────────────────────────┘     │                  │
└──────────────────┘                                      └──────────────────┘
```

!!! info "Reference"
    [AWS DMS Components](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Introduction.Components.html)

---

## Supported Source Databases (On-Premises and EC2)

Based on the [official DMS sources documentation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Introduction.Sources.html):

| Engine | Supported Versions | CDC Support |
|--------|--------------------|-------------|
| Oracle | 10.2+, 11g, 12.2, 18c, 19c (Enterprise, Standard, Standard One, Standard Two) | Yes |
| Microsoft SQL Server | 2008, 2008R2, 2012, 2014, 2016, 2017, 2019, 2022 | Enterprise, Standard (2016+), Developer only |
| MySQL | 5.5, 5.6, 5.7, 8.0, 8.4 | Yes |
| PostgreSQL | 9.4+, 10.x–18.x | Yes |
| MariaDB | 10.0.24+, 10.2–10.6, 11.4.3–11.4.5 | Yes (as MySQL-compatible) |
| MongoDB | 3.x, 4.0, 4.2, 4.4, 5.0, 6.0, 7.0, 8.0 | Yes |
| SAP ASE (Sybase) | 12.5, 15, 15.5, 15.7, 16+ | Yes |
| IBM Db2 LUW | 9.7, 10.1, 10.5, 11.1, 11.5 | Yes |
| IBM Db2 for z/OS | 12 | Yes |

!!! warning "SQL Server Express"
    AWS DMS does **not** support SQL Server Express edition.

---

## Supported Target Databases on AWS

Based on the [official DMS targets documentation](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Introduction.Targets.html):

| Target | Notes |
|--------|-------|
| Amazon RDS (Oracle, SQL Server, MySQL, PostgreSQL, MariaDB) | Managed, Multi-AZ available |
| Amazon Aurora (MySQL-Compatible, PostgreSQL-Compatible) | High performance, auto-scaling storage |
| Amazon Redshift | Data warehouse target |
| Amazon DynamoDB | NoSQL target |
| Amazon S3 | Data lake / archival target |
| Amazon OpenSearch Service | Search and analytics |
| Amazon DocumentDB | MongoDB-compatible |
| Amazon Neptune | Graph database |
| Amazon Kinesis Data Streams | Streaming target |
| Apache Kafka (Amazon MSK) | Event streaming target |
| Amazon ElastiCache (Redis) | In-memory cache target |

---

## Migration Types

AWS DMS supports three migration types per task:

| Type | Description | Use Case |
|------|-------------|----------|
| **Full load** | Migrates existing data from source to target | One-time migration, no ongoing sync needed |
| **Full load + CDC** | Migrates existing data, then replicates ongoing changes | Production migrations with minimal downtime |
| **CDC only** | Captures and applies only ongoing changes | Source data already loaded via other means (native tools, S3) |

---

## Section Contents

| Page | Description |
|------|-------------|
| [Implementation Plan](implementation_plan.md) | Four-phase detailed plan: Discovery → Network → Schema → Data Migration |
| [Checklist](checklist.md) | Complete pre/during/post migration checklist with checkboxes |
| [Step by Step](step_by_step.md) | Concrete walkthrough with AWS CLI commands for each step |
| [Testing and Validation](testing_and_validation.md) | Data validation, schema validation, connection testing, performance testing |
| [Troubleshooting](troubleshooting.md) | Common issues, error messages, and fixes |

---

## Key References

| Resource | URL |
|----------|-----|
| AWS DMS User Guide | [docs.aws.amazon.com/dms/latest/userguide/](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html) |
| AWS DMS Best Practices | [docs.aws.amazon.com/dms/.../CHAP_BestPractices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html) |
| Replication Instance Sizing | [docs.aws.amazon.com/dms/.../SizingReplicationInstance](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.SizingReplicationInstance.html) |
| AWS SCT User Guide | [docs.aws.amazon.com/SchemaConversionTool/](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html) |
| DMS Step-by-Step Walkthroughs | [docs.aws.amazon.com/dms/latest/sbs/](https://docs.aws.amazon.com/dms/latest/sbs/dms-sbs-welcome.html) |
| AWS Prescriptive Guidance — Large Migrations | [docs.aws.amazon.com/prescriptive-guidance/.../phases](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/phases.html) |
| DMS Network Configurations | [docs.aws.amazon.com/dms/.../VPC.Configurations](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReplicationInstance.VPC.html) |
| DMS Data Validation | [docs.aws.amazon.com/dms/.../CHAP_Validating](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html) |
| AWS DMS Pricing | [aws.amazon.com/dms/pricing/](https://aws.amazon.com/dms/pricing/) |
| AWS Pricing Calculator | [calculator.aws](https://calculator.aws) |
