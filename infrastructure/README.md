# Infrastructure - Unified AWS Glue ETL Pipeline

This directory contains the complete infrastructure code for the AWS Glue ETL Pipeline with intelligent concurrency control, organized in a unified, reusable architecture.

## 🏗️ Architecture Overview

The infrastructure has been refactored from a multi-stack approach to a **unified single-stack deployment** with reusable nested templates for better maintainability and ease of deployment.

### Key Improvements ✨

- **Single Stack Deployment**: One command deploys everything
- **Reusable Nested Templates**: Modular components for better organization
- **Centralized Scripts**: All deployment and management scripts under `infrastructure/scripts/`
- **Enhanced Monitoring**: Comprehensive status and health checking
- **Production Ready**: Robust error handling and retry logic

## 📁 Directory Structure

```
infrastructure/
├── scripts/                    # Deployment and management scripts
│   ├── deploy.sh              # Main deployment script (UNIFIED)
│   ├── destroy.sh             # Safe cleanup script
│   └── status.sh              # Comprehensive monitoring
├── templates/                  # Main CloudFormation templates
│   └── main-template.yaml     # Unified stack orchestration
├── nested-templates/          # Reusable infrastructure components
│   ├── networking.yaml        # VPC, subnets, security groups
│   ├── iam-roles.yaml         # IAM roles and policies
│   └── data-storage.yaml      # S3, RDS, Secrets Manager, SNS
└── README.md                  # This documentation
```

## 🚀 Quick Start

### 1. Deploy the Complete Infrastructure

```bash
# Deploy to development environment
./infrastructure/scripts/deploy.sh dev us-east-1 your-email@company.com

# Deploy to production environment
./infrastructure/scripts/deploy.sh prod us-west-2 ops@company.com
```

### 2. Monitor Pipeline Status

```bash
# Comprehensive status check
./infrastructure/scripts/status.sh dev us-east-1

# Check specific environment
./infrastructure/scripts/status.sh prod us-west-2
```

### 3. Cleanup (when needed)

```bash
# Safe destruction with confirmation
./infrastructure/scripts/destroy.sh dev us-east-1
```

## 🔧 Component Details

### Main Template (`templates/main-template.yaml`)
- **Purpose**: Orchestrates the entire infrastructure deployment
- **Features**: References all nested templates with proper dependencies
- **Benefits**: Single point of deployment, consistent parameter passing

### Nested Templates

#### 1. Networking (`nested-templates/networking.yaml`)
- VPC with private subnets across multiple AZs
- Security groups for Lambda, Glue, and database tiers
- VPC endpoints for S3 and Secrets Manager
- NAT gateway for outbound internet access

#### 2. IAM Roles (`nested-templates/iam-roles.yaml`)
- Least-privilege IAM roles for all services
- Separate roles for Lambda, Glue, Step Functions, and monitoring
- Cross-service trust relationships properly configured

#### 3. Data Storage (`nested-templates/data-storage.yaml`)
- Encrypted S3 bucket with lifecycle policies
- RDS PostgreSQL with enhanced monitoring
- Secrets Manager for database credentials
- SNS topic for notifications

### Enhanced Features 🌟

#### Intelligent Concurrency Control
- School-based locking system prevents concurrent processing of files from the same school
- Allows parallel processing of different schools
- Automatic retry logic with exponential backoff

#### Robust Error Handling
- Comprehensive error catching and notification
- Automatic retries with configurable parameters
- Graceful degradation and recovery

#### Monitoring & Observability
- CloudWatch integration for all components
- SNS notifications for success/failure
- Comprehensive logging and metrics

## 🛠️ Deployment Scripts

### deploy.sh
**Features:**
- Validates all CloudFormation templates
- Creates S3 bucket for artifacts
- Packages and uploads Lambda functions
- Deploys unified stack with dependencies
- Configures S3 notifications
- Runs post-deployment validation

**Usage:**
```bash
./infrastructure/scripts/deploy.sh [ENVIRONMENT] [REGION] [EMAIL]
```

### status.sh
**Features:**
- CloudFormation stack health check
- S3 bucket contents and activity monitoring
- Lambda function status and recent invocations
- Glue job status and execution history
- Step Functions execution monitoring
- Database connectivity and metrics
- Recent error analysis
- Cost estimates
- Monitoring dashboard links

**Usage:**
```bash
./infrastructure/scripts/status.sh [ENVIRONMENT] [REGION]
```

### destroy.sh
**Features:**
- Safety confirmation required
- Empties S3 buckets (including versioned objects)
- Stops running Step Functions executions
- Deletes CloudFormation stack
- Cleans up orphaned resources
- Verification of complete cleanup

**Usage:**
```bash
./infrastructure/scripts/destroy.sh [ENVIRONMENT] [REGION]
```

## 📊 Cost Optimization

### Estimated Monthly Costs (USD)
- **RDS db.t3.micro**: ~$12-15
- **Lambda (1M requests)**: ~$0.20
- **Glue (100 DPU-hours)**: ~$44
- **Step Functions (1K transitions)**: ~$0.025
- **S3 storage (100GB)**: ~$2.30
- **CloudWatch logs**: ~$0.50

**Total**: ~$60-70 USD/month (usage dependent)

### Cost Optimization Features
- Lifecycle policies for S3 object transitions
- Automatic archiving of processed files
- Glue job timeout configurations
- Lambda memory optimization

## 🔐 Security Features

### Network Security
- Private subnets for all compute resources
- Security groups with minimal required access
- VPC endpoints for AWS service communication
- No direct internet access for processing components

### Data Security
- Encryption at rest for S3 and RDS
- Encryption in transit for all communications
- AWS Secrets Manager for credential management
- IAM roles with least-privilege access

### Operational Security
- CloudTrail integration for audit logging
- Resource tagging for compliance
- Automated backup configurations
- Secure parameter passing between components

## 🔄 Migration from Old Architecture

If migrating from the previous multi-stack architecture:

1. **Backup existing data** (if any)
2. **Destroy old stacks** using the old scripts
3. **Deploy new unified architecture** using `infrastructure/scripts/deploy.sh`
4. **Verify functionality** using `infrastructure/scripts/status.sh`

### Old vs New Command Mapping
```bash
# OLD (deprecated)
./scripts/deploy.sh → ./infrastructure/scripts/deploy.sh
./scripts/run-tests.sh → ./infrastructure/scripts/status.sh

# NEW (unified)
./infrastructure/scripts/deploy.sh   # Deploy everything
./infrastructure/scripts/status.sh   # Monitor everything
./infrastructure/scripts/destroy.sh  # Clean everything
```

## 🧪 Testing and Validation

### Automated Checks
- Template validation before deployment
- Resource health verification post-deployment
- Lambda function code updates
- S3 notification configuration
- Database connectivity tests

### Manual Testing Steps
1. Upload test Excel file to `s3://bucket/incoming/`
2. Monitor Step Functions execution in AWS Console
3. Verify processed data in `s3://bucket/exports/`
4. Check database records for processing history

## 📞 Support and Troubleshooting

### Common Issues

**Template validation errors:**
```bash
# Check template syntax
aws cloudformation validate-template --template-body file://templates/main-template.yaml
```

**Lambda packaging issues:**
```bash
# Check Lambda packages in S3
aws s3 ls s3://[templates-bucket]/lambda-packages/
```

**Step Functions execution failures:**
```bash
# Check execution history
./infrastructure/scripts/status.sh [env] [region]
```

### Monitoring Commands
```bash
# Check all resources
./infrastructure/scripts/status.sh

# Check specific stack
aws cloudformation describe-stacks --stack-name glue-etl-pipeline-dev

# Monitor Step Functions
aws stepfunctions list-executions --state-machine-arn [arn]
```

## 🎯 Best Practices

1. **Environment Isolation**: Use different environments (dev/test/prod)
2. **Resource Tagging**: All resources are properly tagged
3. **Backup Strategy**: Regular RDS snapshots configured
4. **Monitoring**: Set up CloudWatch alarms for critical metrics
5. **Documentation**: Keep deployment logs and change records

---

**Happy deploying! 🚀**

For additional support or feature requests, please refer to the main project documentation.