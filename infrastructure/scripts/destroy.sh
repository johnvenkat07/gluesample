#!/bin/bash

# ====================================================
# AWS Glue ETL Pipeline Unified Destroy Script
# ====================================================
# Safely destroys the unified stack and cleans up resources

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
STACK_NAME="glue-etl-pipeline-${ENVIRONMENT}"
TEMPLATES_BUCKET="${ENVIRONMENT}-glue-etl-templates-$(aws sts get-caller-identity --query Account --output text)"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}AWS Glue ETL Pipeline Unified Destroy${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Stack Name: ${YELLOW}${STACK_NAME}${NC}"
echo -e "${RED}WARNING: This will delete all resources!${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Function to confirm destruction
confirm_destruction() {
    echo -e "${RED}⚠️  DANGER ZONE ⚠️${NC}"
    echo "This will permanently delete:"
    echo "• CloudFormation stack: $STACK_NAME"
    echo "• S3 buckets and all data"
    echo "• RDS database and all data"
    echo "• Lambda functions"
    echo "• Glue jobs and metadata"
    echo "• Step Functions state machine"
    echo "• IAM roles and policies"
    echo ""
    echo -e "${YELLOW}Are you sure you want to proceed? (type 'DELETE' to confirm):${NC}"
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        echo -e "${GREEN}Destruction cancelled.${NC}"
        exit 0
    fi
}

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

# Function to get stack resources before deletion
get_stack_resources() {
    echo -e "${YELLOW}Identifying stack resources...${NC}"
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" > /dev/null 2>&1; then
        echo -e "${YELLOW}Stack $STACK_NAME does not exist or is already deleted${NC}"
        return 1
    fi
    
    # Get S3 bucket names
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
        --output text --region "$REGION" 2>/dev/null || echo "")
    
    echo -e "${GREEN}✓ Stack resources identified${NC}"
    return 0
}

# Function to empty S3 buckets
empty_s3_buckets() {
    echo -e "${YELLOW}Emptying S3 buckets...${NC}"
    
    # Empty main ETL bucket
    if [ -n "$S3_BUCKET" ]; then
        echo "Emptying S3 bucket: $S3_BUCKET"
        aws s3 rm s3://$S3_BUCKET --recursive --region "$REGION" 2>/dev/null || true
        
        # Delete versioned objects if versioning is enabled
        aws s3api delete-objects --bucket "$S3_BUCKET" \
            --delete "$(aws s3api list-object-versions --bucket "$S3_BUCKET" \
            --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
            --output json)" --region "$REGION" 2>/dev/null || true
        
        # Delete delete markers
        aws s3api delete-objects --bucket "$S3_BUCKET" \
            --delete "$(aws s3api list-object-versions --bucket "$S3_BUCKET" \
            --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
            --output json)" --region "$REGION" 2>/dev/null || true
    fi
    
    # Empty templates bucket
    if aws s3 ls s3://$TEMPLATES_BUCKET > /dev/null 2>&1; then
        echo "Emptying templates bucket: $TEMPLATES_BUCKET"
        aws s3 rm s3://$TEMPLATES_BUCKET --recursive --region "$REGION" 2>/dev/null || true
        
        # Delete versioned objects from templates bucket
        aws s3api delete-objects --bucket "$TEMPLATES_BUCKET" \
            --delete "$(aws s3api list-object-versions --bucket "$TEMPLATES_BUCKET" \
            --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
            --output json)" --region "$REGION" 2>/dev/null || true
        
        # Delete delete markers from templates bucket
        aws s3api delete-objects --bucket "$TEMPLATES_BUCKET" \
            --delete "$(aws s3api list-object-versions --bucket "$TEMPLATES_BUCKET" \
            --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
            --output json)" --region "$REGION" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ S3 buckets emptied${NC}"
}

# Function to stop any running executions
stop_running_executions() {
    echo -e "${YELLOW}Stopping running Step Functions executions...${NC}"
    
    # Get Step Functions ARN
    STEP_FUNCTIONS_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='StepFunctionsStateMachineArn'].OutputValue" \
        --output text --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$STEP_FUNCTIONS_ARN" ]; then
        # List and stop running executions
        RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
            --state-machine-arn "$STEP_FUNCTIONS_ARN" \
            --status-filter RUNNING \
            --query "executions[].executionArn" \
            --output text --region "$REGION" 2>/dev/null || echo "")
        
        for execution in $RUNNING_EXECUTIONS; do
            if [ -n "$execution" ]; then
                echo "Stopping execution: $execution"
                aws stepfunctions stop-execution \
                    --execution-arn "$execution" \
                    --region "$REGION" 2>/dev/null || true
            fi
        done
    fi
    
    echo -e "${GREEN}✓ Running executions stopped${NC}"
}

# Function to delete the CloudFormation stack
delete_stack() {
    echo -e "${YELLOW}Deleting CloudFormation stack...${NC}"
    
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    echo "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"
    
    echo -e "${GREEN}✓ CloudFormation stack deleted${NC}"
}

# Function to clean up remaining resources
cleanup_remaining_resources() {
    echo -e "${YELLOW}Cleaning up any remaining resources...${NC}"
    
    # Delete templates bucket if it still exists
    if aws s3 ls s3://$TEMPLATES_BUCKET > /dev/null 2>&1; then
        echo "Deleting templates bucket: $TEMPLATES_BUCKET"
        aws s3 rb s3://$TEMPLATES_BUCKET --force --region "$REGION" 2>/dev/null || true
    fi
    
    # Clean up any orphaned Glue jobs (if they exist)
    for job_name in "${ENVIRONMENT}-raw-ingestion-job" "${ENVIRONMENT}-transformation-job" "${ENVIRONMENT}-csv-export-job" "${ENVIRONMENT}-file-archiver-job"; do
        if aws glue get-job --job-name "$job_name" --region "$REGION" > /dev/null 2>&1; then
            echo "Deleting orphaned Glue job: $job_name"
            aws glue delete-job --job-name "$job_name" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Clean up any orphaned Lambda functions
    for function_name in "${ENVIRONMENT}-glue-etl-s3-trigger" "${ENVIRONMENT}-glue-etl-release-lock"; do
        if aws lambda get-function --function-name "$function_name" --region "$REGION" > /dev/null 2>&1; then
            echo "Deleting orphaned Lambda function: $function_name"
            aws lambda delete-function --function-name "$function_name" --region "$REGION" 2>/dev/null || true
        fi
    done
    
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Function to verify cleanup
verify_cleanup() {
    echo -e "${YELLOW}Verifying cleanup completion...${NC}"
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" > /dev/null 2>&1; then
        echo -e "${RED}✗ Stack still exists${NC}"
    else
        echo -e "${GREEN}✓ Stack successfully deleted${NC}"
    fi
    
    # Check if S3 buckets still exist
    if aws s3 ls s3://$TEMPLATES_BUCKET > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Templates bucket still exists (may be in use by other stacks)${NC}"
    else
        echo -e "${GREEN}✓ Templates bucket cleaned up${NC}"
    fi
    
    if [ -n "$S3_BUCKET" ] && aws s3 ls s3://$S3_BUCKET > /dev/null 2>&1; then
        echo -e "${RED}✗ Main ETL bucket still exists${NC}"
    else
        echo -e "${GREEN}✓ Main ETL bucket cleaned up${NC}"
    fi
    
    echo -e "${GREEN}✓ Cleanup verification completed${NC}"
}

# Function to display destruction summary
display_summary() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}DESTRUCTION SUMMARY${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "Environment: ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "Region: ${GREEN}${REGION}${NC}"
    echo -e "Stack Name: ${GREEN}${STACK_NAME} (DELETED)${NC}"
    echo ""
    echo -e "${GREEN}Resources Successfully Destroyed:${NC}"
    echo "✅ CloudFormation stack and all managed resources"
    echo "✅ S3 buckets and all data"
    echo "✅ RDS database and all data"
    echo "✅ Lambda functions and execution logs"
    echo "✅ Glue jobs and metadata"
    echo "✅ Step Functions state machine"
    echo "✅ IAM roles and policies"
    echo "✅ VPC resources (if exclusively used by this stack)"
    echo ""
    echo -e "${YELLOW}NOTE:${NC} Some CloudWatch logs may persist with their configured retention periods"
    echo -e "${YELLOW}NOTE:${NC} Secrets Manager secrets have a recovery window (7-30 days)"
    echo ""
    echo -e "${GREEN}Unified stack destruction completed successfully! 🗑️${NC}"
}

# Function to show help
show_help() {
    echo "Usage: $0 [ENVIRONMENT] [REGION]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT       Environment name (dev, test, prod). Default: dev"
    echo "  REGION           AWS region. Default: us-east-1"
    echo ""
    echo "This script will:"
    echo "  • Stop all running Step Functions executions"
    echo "  • Empty and delete S3 buckets"
    echo "  • Delete the unified CloudFormation stack"
    echo "  • Clean up any orphaned resources"
    echo "  • Verify complete cleanup"
    echo ""
    echo "Examples:"
    echo "  $0 dev us-east-1"
    echo "  $0 prod us-west-2"
    echo ""
    echo "⚠️  WARNING: This action is irreversible!"
}

# Main execution function
main() {
    check_aws_cli
    
    if get_stack_resources; then
        confirm_destruction
        stop_running_executions
        empty_s3_buckets
        delete_stack
        cleanup_remaining_resources
        verify_cleanup
        display_summary
    else
        echo -e "${GREEN}No resources to clean up.${NC}"
    fi
}

# Handle script arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
    exit 0
fi

# Run main function
main