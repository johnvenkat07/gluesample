#!/bin/bash

# ====================================================
# AWS Glue ETL Pipeline Unified Deployment Script
# ====================================================
# Single stack deployment with reusable nested templates

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
NOTIFICATION_EMAIL=${3:-admin@example.com}
STACK_NAME="glue-etl-pipeline-${ENVIRONMENT}"
TEMPLATES_BUCKET="${ENVIRONMENT}-glue-etl-templates-$(aws sts get-caller-identity --query Account --output text)"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}AWS Glue ETL Pipeline Unified Deployment${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Stack Name: ${YELLOW}${STACK_NAME}${NC}"
echo -e "Notification Email: ${YELLOW}${NOTIFICATION_EMAIL}${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Function to check if AWS CLI is configured
check_aws_cli() {
    echo -e "${YELLOW}Checking AWS CLI configuration...${NC}"
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${RED}ERROR: AWS CLI is not configured or credentials are invalid${NC}"
        echo "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    echo -e "${GREEN}✓ AWS CLI is configured${NC}"
}

# Function to create templates bucket
create_templates_bucket() {
    echo -e "${YELLOW}Creating S3 bucket for CloudFormation templates...${NC}"
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$TEMPLATES_BUCKET" 2>/dev/null; then
        echo -e "${YELLOW}Bucket $TEMPLATES_BUCKET already exists${NC}"
    else
        # Create bucket
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$TEMPLATES_BUCKET" --region "$REGION"
        else
            aws s3api create-bucket --bucket "$TEMPLATES_BUCKET" --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning --bucket "$TEMPLATES_BUCKET" \
            --versioning-configuration Status=Enabled
        
        echo -e "${GREEN}✓ Created S3 bucket: $TEMPLATES_BUCKET${NC}"
    fi
}

# Function to upload templates and scripts
upload_templates_and_scripts() {
    echo -e "${YELLOW}Uploading CloudFormation templates and scripts...${NC}"
    
    # Upload nested templates
    aws s3 cp infrastructure/nested-templates/ s3://$TEMPLATES_BUCKET/nested-templates/ --recursive
    
    # Upload Glue scripts
    aws s3 cp src/glue/ s3://$TEMPLATES_BUCKET/glue-scripts/ --recursive
    
    # Package and upload Lambda functions
    echo -e "${YELLOW}Packaging Lambda functions...${NC}"
    
    # Create temporary directory for Lambda packages
    mkdir -p infrastructure/scripts/lambda-packages
    
    # Package S3 trigger Lambda
    cd infrastructure/scripts/lambda-packages
    mkdir -p s3-trigger
    cp ../../../src/lambda/s3_trigger.py s3-trigger/
    cp -r ../../../src/utils s3-trigger/
    cd s3-trigger
    zip -r ../s3-trigger.zip . > /dev/null
    cd ..
    
    # Package release lock Lambda
    mkdir -p release-lock
    cp ../../../src/lambda/release_lock.py release-lock/
    cp -r ../../../src/utils release-lock/
    cd release-lock
    zip -r ../release-lock.zip . > /dev/null
    cd ../../../
    
    # Upload Lambda packages to S3
    aws s3 cp infrastructure/scripts/lambda-packages/s3-trigger.zip s3://$TEMPLATES_BUCKET/lambda-packages/
    aws s3 cp infrastructure/scripts/lambda-packages/release-lock.zip s3://$TEMPLATES_BUCKET/lambda-packages/
    
    # Step Functions definition is embedded in the main template
    
    # Clean up temp directory
    rm -rf infrastructure/scripts/lambda-packages
    
    echo -e "${GREEN}✓ Uploaded all templates and scripts${NC}"
}

# Function to validate templates
validate_templates() {
    echo -e "${YELLOW}Validating CloudFormation templates...${NC}"
    
    # Validate main template
    aws cloudformation validate-template \
        --template-body file://infrastructure/templates/main-template.yaml \
        --region "$REGION" > /dev/null
    
    # Validate nested templates
    for template in infrastructure/nested-templates/*.yaml; do
        aws cloudformation validate-template \
            --template-body file://"$template" \
            --region "$REGION" > /dev/null
    done
    
    echo -e "${GREEN}✓ All templates are valid${NC}"
}

# Function to deploy the unified stack
deploy_stack() {
    echo -e "${YELLOW}Deploying unified CloudFormation stack...${NC}"
    
    # Generate a secure random password for database
    DB_PASSWORD=$(openssl rand -base64 12 | tr -d "/@'\"\\\\")
    
    # Deploy the stack
    aws cloudformation deploy \
        --template-file infrastructure/templates/main-template.yaml \
        --stack-name "$STACK_NAME" \
        --parameter-overrides \
            EnvironmentName="$ENVIRONMENT" \
            DatabasePassword="$DB_PASSWORD" \
            NotificationEmail="$NOTIFICATION_EMAIL" \
            TemplatesBucketName="$TEMPLATES_BUCKET" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --no-fail-on-empty-changeset
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Stack deployed successfully${NC}"
    else
        echo -e "${RED}ERROR: Failed to deploy stack${NC}"
        exit 1
    fi
}

# Function to update Lambda functions with actual code
update_lambda_functions() {
    echo -e "${YELLOW}Updating Lambda functions with actual code...${NC}"
    
    # Update S3 trigger Lambda
    aws lambda update-function-code \
        --function-name "${ENVIRONMENT}-glue-etl-s3-trigger" \
        --s3-bucket "$TEMPLATES_BUCKET" \
        --s3-key "lambda-packages/s3-trigger.zip" \
        --region "$REGION" > /dev/null
    
    # Update release lock Lambda
    aws lambda update-function-code \
        --function-name "${ENVIRONMENT}-glue-etl-release-lock" \
        --s3-bucket "$TEMPLATES_BUCKET" \
        --s3-key "lambda-packages/release-lock.zip" \
        --region "$REGION" > /dev/null
    
    echo -e "${GREEN}✓ Lambda functions updated with actual code${NC}"
}

# Function to configure S3 bucket notifications
configure_s3_notifications() {
    echo -e "${YELLOW}Configuring S3 bucket notifications...${NC}"
    
    # Get S3 bucket name and Lambda function ARN
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
        --output text --region "$REGION")
    
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${ENVIRONMENT}-glue-etl-s3-trigger" \
        --query "Configuration.FunctionArn" \
        --output text --region "$REGION")
    
    # Create notification configuration
    cat > /tmp/s3-notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "ETLTrigger",
            "LambdaFunctionArn": "$LAMBDA_ARN",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "incoming/"
                        },
                        {
                            "Name": "suffix",
                            "Value": ".xlsx"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "$S3_BUCKET" \
        --notification-configuration file:///tmp/s3-notification.json \
        --region "$REGION"
    
    # Clean up temp file
    rm -f /tmp/s3-notification.json
    
    echo -e "${GREEN}✓ S3 bucket notifications configured${NC}"
}

# Function to initialize database schema
initialize_database() {
    echo -e "${YELLOW}Database initialization...${NC}"
    
    # Get database endpoint
    DB_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
        --output text --region "$REGION")
    
    echo -e "${BLUE}Database Schema Initialization${NC}"
    echo -e "${YELLOW}Manual step required:${NC}"
    echo "1. Install PostgreSQL client: brew install postgresql (macOS) or apt-get install postgresql-client (Ubuntu)"
    echo "2. Run schema script: psql -h $DB_ENDPOINT -U etl_admin -d postgres -f sql/schema.sql"
    echo "3. Enter password when prompted (check AWS Secrets Manager for credentials)"
    echo ""
}

# Function to run post-deployment tests
run_tests() {
    echo -e "${YELLOW}Running post-deployment validation tests...${NC}"
    
    # Test 1: Check if stack exists and is in good state
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text --region "$REGION" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✓ CloudFormation stack is healthy${NC}"
    else
        echo -e "${RED}✗ CloudFormation stack status: $STACK_STATUS${NC}"
    fi
    
    # Test 2: Check if S3 bucket exists and has scripts
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
        --output text --region "$REGION")
    
    if aws s3 ls s3://$TEMPLATES_BUCKET/glue-scripts/ > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Glue scripts uploaded successfully${NC}"
    else
        echo -e "${RED}✗ Glue scripts not found${NC}"
    fi
    
    # Test 3: Check Lambda functions
    if aws lambda get-function --function-name "${ENVIRONMENT}-glue-etl-s3-trigger" --region "$REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Lambda functions created successfully${NC}"
    else
        echo -e "${RED}✗ Lambda functions not found${NC}"
    fi
    
    # Test 4: Check Glue jobs
    if aws glue get-job --job-name "${ENVIRONMENT}-raw-ingestion-job" --region "$REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Glue jobs created successfully${NC}"
    else
        echo -e "${RED}✗ Glue jobs not found${NC}"
    fi
    
    # Test 5: Check Step Functions
    if aws stepfunctions describe-state-machine --state-machine-arn "$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='StepFunctionsStateMachineArn'].OutputValue" --output text --region "$REGION")" --region "$REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Step Functions state machine created successfully${NC}"
    else
        echo -e "${RED}✗ Step Functions state machine not found${NC}"
    fi
    
    echo -e "${GREEN}✓ Post-deployment validation completed${NC}"
}

# Function to display deployment summary
display_summary() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}UNIFIED DEPLOYMENT SUMMARY${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # Get stack outputs
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
        --output text --region "$REGION")
    
    STEP_FUNCTIONS_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='StepFunctionsStateMachineArn'].OutputValue" \
        --output text --region "$REGION")
    
    DB_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
        --output text --region "$REGION")
    
    echo -e "Environment: ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "Region: ${GREEN}${REGION}${NC}"
    echo -e "Stack Name: ${GREEN}${STACK_NAME}${NC}"
    echo -e "S3 Bucket (ETL): ${GREEN}${S3_BUCKET}${NC}"
    echo -e "S3 Bucket (Templates): ${GREEN}${TEMPLATES_BUCKET}${NC}"
    echo -e "Database Endpoint: ${GREEN}${DB_ENDPOINT}${NC}"
    echo -e "Step Functions ARN: ${GREEN}${STEP_FUNCTIONS_ARN}${NC}"
    echo ""
    echo -e "${YELLOW}ARCHITECTURE BENEFITS:${NC}"
    echo "✅ Single unified stack deployment (no more multiple stacks)"
    echo "✅ Reusable nested templates for modularity"
    echo "✅ Centralized script management under infrastructure/scripts"
    echo "✅ Automated S3 notification configuration"
    echo "✅ Enhanced error handling and retry logic"
    echo ""
    echo -e "${YELLOW}NEXT STEPS:${NC}"
    echo "1. Initialize database schema: psql -h ${DB_ENDPOINT} -U etl_admin -d postgres -f sql/schema.sql"
    echo "2. Upload test Excel files: aws s3 cp test.xlsx s3://${S3_BUCKET}/incoming/"
    echo "3. Monitor processing: AWS Step Functions console"
    echo "4. Check results: s3://${S3_BUCKET}/exports/"
    echo ""
    echo -e "${GREEN}Unified deployment completed successfully! 🎉${NC}"
}

# Function to show help
show_help() {
    echo "Usage: $0 [ENVIRONMENT] [REGION] [NOTIFICATION_EMAIL]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT       Environment name (dev, test, prod). Default: dev"
    echo "  REGION           AWS region. Default: us-east-1"
    echo "  NOTIFICATION_EMAIL  Email for notifications. Default: admin@example.com"
    echo ""
    echo "Features of Unified Deployment:"
    echo "  • Single CloudFormation stack (no nested stack complexity)"
    echo "  • Reusable modular templates"
    echo "  • Centralized script management"
    echo "  • Automated configuration"
    echo "  • Enhanced monitoring and error handling"
    echo ""
    echo "Examples:"
    echo "  $0 dev us-east-1 dev@company.com"
    echo "  $0 prod us-west-2 ops@company.com"
    echo ""
}

# Main execution function
main() {
    check_aws_cli
    create_templates_bucket
    validate_templates
    upload_templates_and_scripts
    deploy_stack
    update_lambda_functions
    configure_s3_notifications
    initialize_database
    run_tests
    display_summary
}

# Handle script arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
    exit 0
fi

# Run main function
main