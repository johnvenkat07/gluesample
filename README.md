# AWS Infrastructure Project - Simplified

A simplified AWS infrastructure project with basic components demonstrating AWS cloud services integration.

## 🚀 **Simplified Architecture**

**Focus on Infrastructure!** Basic setup with:

✅ **Infrastructure as Code** - Complete CloudFormation templates  
✅ **Modular Design** - Reusable nested templates  
✅ **Simple Python Code** - Hello World examples for Lambda and Glue  
✅ **Production Ready Infrastructure** - VPC, Security Groups, IAM Roles  

## 🏗️ Architecture Overview

### Core Components

- **Infrastructure**: VPC, Subnets, Security Groups, IAM Roles
- **Compute**: AWS Lambda with simple Python functions
- **Data Processing**: AWS Glue jobs with basic examples
- **Storage**: Amazon S3 buckets and RDS PostgreSQL
- **Security**: IAM policies and VPC networking

### Technology Stack

- **Compute**: AWS Lambda (Python 3.9), AWS Glue 4.0
- **Storage**: Amazon S3, Amazon RDS PostgreSQL 15.4
- **Security**: VPC networking, IAM roles, AWS Secrets Manager
- **Infrastructure**: CloudFormation nested templates

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- AWS Account with service access to Glue, Lambda, Step Functions, RDS, S3
- Email address for notifications

### 1. Deploy Infrastructure (Single Command!)

```bash
# Deploy to development environment
./infrastructure/scripts/deploy.sh dev us-east-1 your-email@company.com

# Deploy to production environment  
./infrastructure/scripts/deploy.sh prod us-west-2 ops@company.com
```

### 2. Initialize Database Schema

```bash
# Get database endpoint from deployment output
psql -h [DB_ENDPOINT] -U etl_admin -d postgres -f sql/schema.sql
```

### 3. Test the Pipeline

```bash
# Upload test Excel file
aws s3 cp test.xlsx s3://[S3_BUCKET]/incoming/school_123/data.xlsx

# Monitor processing
./infrastructure/scripts/status.sh dev us-east-1
```

### 4. Monitor Results

```bash
# Check exports
aws s3 ls s3://[S3_BUCKET]/exports/ --recursive

# View comprehensive status
./infrastructure/scripts/status.sh dev us-east-1
```

## 📁 Project Structure

```
glue-etl-pipeline/
├── infrastructure/              # 🆕 UNIFIED INFRASTRUCTURE
│   ├── scripts/                # Deployment & management scripts
│   │   ├── deploy.sh           # Single deployment command
│   │   ├── destroy.sh          # Safe cleanup
│   │   └── status.sh           # Comprehensive monitoring
│   ├── templates/              # Main CloudFormation templates
│   │   └── main-template.yaml  # Unified stack orchestration
│   ├── nested-templates/       # Reusable components
│   │   ├── networking.yaml     # VPC, security groups
│   │   ├── iam-roles.yaml      # IAM roles & policies
│   │   └── data-storage.yaml   # S3, RDS, Secrets
├── src/                        # Application code
│   ├── glue/                   # Glue ETL jobs
│   │   ├── raw_ingestion_job.py
│   │   ├── transformation_job.py
│   │   ├── csv_export_job.py
│   │   └── file_archiver_job.py
│   ├── lambda/                 # Lambda functions
│   │   ├── s3_trigger.py       # S3 event handler
│   │   └── release_lock.py     # Lock management
│   └── utils/                  # Shared utilities
│       └── common.py           # Database, logging, utilities
├── sql/                        # Database schema
│   └── schema.sql              # PostgreSQL schema
├── tests/                      # Unit tests
│   └── test_pipeline.py        # Comprehensive test suite
├── scripts/                    # 🚨 DEPRECATED (redirects to infrastructure/scripts/)
└── config.ini                 # Configuration settings
```

## 🔧 Advanced Usage

### Environment Management

```bash
# Development environment
./infrastructure/scripts/deploy.sh dev us-east-1 dev@company.com

# Staging environment
./infrastructure/scripts/deploy.sh staging us-east-1 staging@company.com

# Production environment
./infrastructure/scripts/deploy.sh prod us-west-2 ops@company.com
```

### Monitoring and Status

```bash
# Comprehensive status check
./infrastructure/scripts/status.sh prod us-west-2

# View recent errors and issues
./infrastructure/scripts/status.sh dev us-east-1

# Get AWS console links for monitoring
./infrastructure/scripts/status.sh prod us-west-2
```

### Safe Cleanup

```bash
# Destroy environment (with confirmation)
./infrastructure/scripts/destroy.sh dev us-east-1
```

## 🔒 Security Features

### Network Security
- **Private Subnets**: All compute resources in private subnets
- **VPC Endpoints**: Secure communication with AWS services
- **Security Groups**: Minimal required access patterns

### Data Security
- **Encryption at Rest**: S3 and RDS encrypted with AWS KMS
- **Encryption in Transit**: All communications encrypted
- **Secrets Management**: Database credentials in AWS Secrets Manager

### Access Control
- **IAM Least Privilege**: Minimal required permissions
- **Resource-based Policies**: Fine-grained access control
- **Cross-service Trust**: Secure service-to-service communication

## 📊 Processing Flow

### 1. File Upload
```
Excel file → s3://bucket/incoming/school_123/data.xlsx
```

### 2. Trigger Processing
```
S3 Event → Lambda → Step Functions (with lock acquisition)
```

### 3. ETL Pipeline
```
Raw Ingestion → Data Transformation → CSV Export + File Archiving
```

### 4. Results
```
Processed data → s3://bucket/exports/school_123/
```

## 🎯 Intelligent Concurrency Control

### How It Works

1. **School-based Locking**: Each school gets a processing lock in RDS
2. **Parallel Processing**: Different schools can process simultaneously  
3. **Sequential Safety**: Same school files process sequentially
4. **Automatic Retry**: Failed lock acquisition retries with backoff

### Benefits

- **No Race Conditions**: Prevents data corruption
- **Optimal Resource Usage**: Maximizes parallel processing
- **Fault Tolerance**: Automatic recovery from failures
- **Scalability**: Handles hundreds of concurrent schools

## 💰 Cost Optimization

### Estimated Monthly Costs (USD)
- **RDS db.t3.micro**: ~$12-15
- **Lambda (1M requests)**: ~$0.20  
- **Glue (100 DPU-hours)**: ~$44
- **Step Functions (1K transitions)**: ~$0.025
- **S3 storage (100GB)**: ~$2.30

**Total**: ~$60-70 USD/month (usage dependent)

### Optimization Features
- S3 lifecycle policies for cost-effective storage
- Glue job timeout configurations
- Lambda memory optimization
- Automatic file archiving

## 🧪 Testing

### Unit Tests
```bash
python -m pytest tests/test_pipeline.py -v
```

### Integration Tests
```bash
# Upload test file and monitor
aws s3 cp test.xlsx s3://[bucket]/incoming/test_school/test.xlsx
./infrastructure/scripts/status.sh dev us-east-1
```

### Load Testing
```bash
# Upload multiple files for different schools
for i in {1..10}; do
    aws s3 cp test.xlsx s3://[bucket]/incoming/school_$i/data_$i.xlsx
done
```

## 🆕 Migration from v1.0

If you're using the previous multi-stack architecture:

### Step 1: Backup Data
```bash
# Export any important data
aws s3 sync s3://old-bucket/exports/ ./backup/exports/
```

### Step 2: Clean Old Infrastructure
```bash
# Use old destroy scripts or manually delete stacks
aws cloudformation delete-stack --stack-name old-stack-name
```

### Step 3: Deploy New Unified Architecture
```bash
./infrastructure/scripts/deploy.sh dev us-east-1 your-email@company.com
```

### Step 4: Verify Migration
```bash
./infrastructure/scripts/status.sh dev us-east-1
```

## 🔧 Troubleshooting

### Common Issues

**Deployment Failures:**
```bash
# Check template validation
aws cloudformation validate-template --template-body file://infrastructure/templates/main-template.yaml

# Check stack events
aws cloudformation describe-stack-events --stack-name glue-etl-pipeline-dev
```

**Processing Failures:**
```bash
# Check Step Functions executions
./infrastructure/scripts/status.sh dev us-east-1

# View recent errors
aws logs filter-log-events --log-group-name /aws/lambda/dev-glue-etl-s3-trigger
```

**Database Connection Issues:**
```bash
# Test database connectivity
psql -h [endpoint] -U etl_admin -d postgres -c "SELECT version();"
```

### Support Resources

- **AWS Documentation**: [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- **CloudFormation**: [Template Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- **Step Functions**: [State Machine Guide](https://docs.aws.amazon.com/step-functions/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎉 What's New in v2.0

- ✅ **Unified Single-Stack Deployment**
- ✅ **Reusable Nested CloudFormation Templates**
- ✅ **Enhanced Error Handling & Retry Logic**
- ✅ **Comprehensive Monitoring Scripts**
- ✅ **Production-Ready Security Features**
- ✅ **Cost Optimization Improvements**
- ✅ **Simplified Management Scripts**

---

**Ready to process thousands of Excel files with confidence? Start with the unified deployment! 🚀**