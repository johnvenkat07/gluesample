"""
AWS Glue Job: Raw Data Ingestion - Simplified
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# Get job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME'])

# Initialize Spark/Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

print("Hello World - Raw Ingestion Glue Job")
print(f"Job Name: {args['JOB_NAME']}")

# Simple return - job completed successfully
job.commit()