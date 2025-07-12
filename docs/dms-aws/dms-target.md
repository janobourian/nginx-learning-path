# DMS Targets

## Options

Exists several targets:

* Aurora MySQL
* Aurora PostgreSQL
* Oracle
* Microsoft SQL Server
* S3 (Simple Storage Service)
* Redshift

## S3 Simple Storage Service

### Create a DMS Replication Instance

* The process is:
    * Source Database
    * > AWS DMS replication instance
    * > Target Database or Amazon S3 or non-database

* If you want to create the replication instance:
    * Name:
    * ARN: Leave blank
    * Description: 
    * Instance Class: dms.c5.xlarge
    * Engine Version: Leave the default value
    * High Availability/Multi-AZ: Single AZ
    * Allocated storage GB: 50
    * VPC: 
    * Publicly accessible: No/unchecked
    * Advanced -> VPC Security Groups: default

### Configure the Target S3 Bucket

* The steps are:
    * Create the bucket with a legible name, for example: `dmstagetbucket-janobourian-maxine`
    * Create `dmstargetfolder` folder inside the bucket
    * Create a policy to access the bucket `DMS-LAB-S3-Access-Policy`
    * Create the role and associate the policy


```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::dmstagetbucket-janobourian-maxine/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::dmstagetbucket-janobourian-maxine"
            ]
        }
    ]
}
```

### Create DMS Source and Target Endpoints

* Create the source endpoint (SQL Server Source)
* Create the target endpoint for S3 Bucket

### Create a DMS Migration Task

* The configuration for tasks:
    * Tasks identifier:
    * Replication instance:
    * Source database endpoint:
    * Target database endpoint:
    * Migration type:
        * Migrate existing data and replicate ongoing changes
    * Custom CDC stop mode for source transactions:
        * Don’t use custom CDC stop mode
    * Create recovery table on target DB:
        * leave blank/unchecked
    * Target table preparation mode:
        * Do nothing
    * Stop task after full load completes:
        * Don't stop
    * LOB Column settings / Include LOB columns in replication:
        * Limited LOB mode
    * Max LOB size (KB)
    * Data validation
        * Unchecked
    * Task Logs / Enable CloudWatch logs
    * Log Context
    * Batch-optimized apply if visible

* Table mappings:
    * Wizard

* Add new selection rule:
    * Schema: dbo%
    * Table name: %
    * Action: Include

* Transformation rules:
    * Target: Schema
    * Schema Name: dbo
    * Action: Rename to: dms_sample_dbo

* Uncheck Turn on premigration assessment

### Inspect the Content in the S3 Bucket

* Check the bucket and folders to validate the information

### Replicate Data Changes

* Inside the SQL Server executes the script

```sql
USE [dms_sample]
GO

INSERT INTO [dbo].[sport_type]
           ([name]
           ,[description])
     VALUES
           ('hockey', 'A sport in which two teams play against each other by trying to more a puck into the opponents goal using a hockey stick');

INSERT INTO [dbo].[sport_type]
           ([name]
           ,[description])
     VALUES
           ('basketball', 'A sport in which two teams of five players each that oppose one another shoot a basketball through the defenders hoop');

INSERT INTO [dbo].[sport_type]
           ([name]
           ,[description])
     VALUES
           ('soccer','A sport played with a spherical ball between two teams of eleven players');

INSERT INTO [dbo].[sport_type]
           ([name]
           ,[description])
     VALUES
            ('volleyball','two teams of six players are separated by a net and each team tries to score by grounding a ball on the others court');

INSERT INTO [dbo].[sport_type]
           ([name]
           ,[description])
     VALUES
           ('cricket','A bat-and-ball game between two teams of eleven players on a field with a wicket at each end');
GO

```
