#!/bin/bash

# ====================================================
# AWS Glue ETL Pipeline Unified Status & Monitoring
# ====================================================
# Comprehensive status checking and monitoring script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
STACK_NAME="glue-etl-pipeline-${ENVIRONMENT}"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}AWS Glue ETL Pipeline Status & Monitoring${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Stack Name: ${YELLOW}${STACK_NAME}${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${RED}ERROR: AWS CLI is not configured or credentials are invalid${NC}"
        exit 1
    fi
}

# Function to check CloudFormation stack status
check_stack_status() {
    echo -e "${PURPLE}📋 CLOUDFORMATION STACK STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    if STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null); then
        STACK_STATUS=$(echo "$STACK_INFO" | jq -r '.Stacks[0].StackStatus')
        CREATION_TIME=$(echo "$STACK_INFO" | jq -r '.Stacks[0].CreationTime')
        LAST_UPDATED=$(echo "$STACK_INFO" | jq -r '.Stacks[0].LastUpdatedTime // "Never"')
        
        case $STACK_STATUS in
            *COMPLETE)
                echo -e "Status: ${GREEN}$STACK_STATUS${NC}"
                ;;
            *IN_PROGRESS)
                echo -e "Status: ${YELLOW}$STACK_STATUS${NC}"
                ;;
            *FAILED)
                echo -e "Status: ${RED}$STACK_STATUS${NC}"
                ;;
            *)
                echo -e "Status: ${YELLOW}$STACK_STATUS${NC}"
                ;;
        esac
        
        echo -e "Created: ${BLUE}$CREATION_TIME${NC}"
        echo -e "Last Updated: ${BLUE}$LAST_UPDATED${NC}"
        
        # Get stack outputs
        echo -e "\n${YELLOW}Stack Outputs:${NC}"
        echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[]? | "  \(.OutputKey): \(.OutputValue)"'
        
        return 0
    else
        echo -e "${RED}Stack not found or inaccessible${NC}"
        return 1
    fi
}

# Function to check S3 buckets
check_s3_status() {
    echo -e "\n${PURPLE}🗄️  S3 BUCKETS STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    if STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null); then
        S3_BUCKET=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[]? | select(.OutputKey=="S3BucketName") | .OutputValue')
        
        if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "null" ]; then
            echo -e "ETL Bucket: ${GREEN}$S3_BUCKET${NC}"
            
            # Check bucket contents
            echo -e "\n${YELLOW}Bucket Structure:${NC}"
            for folder in "incoming" "processing" "processed" "exports" "archive" "errors"; do
                COUNT=$(aws s3 ls s3://$S3_BUCKET/$folder/ --region "$REGION" 2>/dev/null | wc -l | tr -d ' ')
                echo -e "  $folder/: ${BLUE}$COUNT files${NC}"
            done
            
            # Recent activity
            echo -e "\n${YELLOW}Recent Activity (Last 10 files):${NC}"
            aws s3 ls s3://$S3_BUCKET --recursive --region "$REGION" 2>/dev/null | sort -k1,2 | tail -10 | while read -r line; do
                echo "  $line"
            done 2>/dev/null || echo "  No recent files found"
        fi
    fi
}

# Function to check Lambda functions
check_lambda_status() {
    echo -e "\n${PURPLE}⚡ LAMBDA FUNCTIONS STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    for function_name in "${ENVIRONMENT}-glue-etl-s3-trigger" "${ENVIRONMENT}-glue-etl-release-lock"; do
        if FUNC_INFO=$(aws lambda get-function --function-name "$function_name" --region "$REGION" 2>/dev/null); then
            LAST_MODIFIED=$(echo "$FUNC_INFO" | jq -r '.Configuration.LastModified')
            RUNTIME=$(echo "$FUNC_INFO" | jq -r '.Configuration.Runtime')
            STATE=$(echo "$FUNC_INFO" | jq -r '.Configuration.State')
            
            echo -e "Function: ${GREEN}$function_name${NC}"
            echo -e "  State: ${BLUE}$STATE${NC}"
            echo -e "  Runtime: ${BLUE}$RUNTIME${NC}"
            echo -e "  Last Modified: ${BLUE}$LAST_MODIFIED${NC}"
            
            # Get recent invocations
            END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
            START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S.000Z)
            
            INVOCATIONS=$(aws logs filter-log-events \
                --log-group-name "/aws/lambda/$function_name" \
                --start-time $(date -d "$START_TIME" +%s)000 \
                --end-time $(date -d "$END_TIME" +%s)000 \
                --filter-pattern "START RequestId" \
                --region "$REGION" 2>/dev/null | jq -r '.events | length')
            
            echo -e "  Invocations (24h): ${BLUE}${INVOCATIONS:-0}${NC}"
        else
            echo -e "Function: ${RED}$function_name (Not Found)${NC}"
        fi
        echo ""
    done
}

# Function to check Glue jobs
check_glue_status() {
    echo -e "${PURPLE}🔧 GLUE JOBS STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    for job_name in "${ENVIRONMENT}-raw-ingestion-job" "${ENVIRONMENT}-transformation-job" "${ENVIRONMENT}-csv-export-job" "${ENVIRONMENT}-file-archiver-job"; do
        if JOB_INFO=$(aws glue get-job --job-name "$job_name" --region "$REGION" 2>/dev/null); then
            GLUE_VERSION=$(echo "$JOB_INFO" | jq -r '.Job.GlueVersion')
            WORKER_TYPE=$(echo "$JOB_INFO" | jq -r '.Job.WorkerType')
            NUM_WORKERS=$(echo "$JOB_INFO" | jq -r '.Job.NumberOfWorkers')
            LAST_MODIFIED=$(echo "$JOB_INFO" | jq -r '.Job.LastModifiedOn')
            
            echo -e "Job: ${GREEN}$job_name${NC}"
            echo -e "  Glue Version: ${BLUE}$GLUE_VERSION${NC}"
            echo -e "  Worker Type: ${BLUE}$WORKER_TYPE${NC}"
            echo -e "  Workers: ${BLUE}$NUM_WORKERS${NC}"
            echo -e "  Last Modified: ${BLUE}$LAST_MODIFIED${NC}"
            
            # Get recent runs
            RECENT_RUNS=$(aws glue get-job-runs --job-name "$job_name" --max-items 5 --region "$REGION" 2>/dev/null | jq -r '.JobRuns[]? | "\(.JobRunState) - \(.StartedOn)"' 2>/dev/null || echo "No recent runs")
            echo -e "  Recent Runs:"
            if [ "$RECENT_RUNS" != "No recent runs" ]; then
                echo "$RECENT_RUNS" | while read -r run; do
                    echo "    $run"
                done
            else
                echo "    No recent runs"
            fi
        else
            echo -e "Job: ${RED}$job_name (Not Found)${NC}"
        fi
        echo ""
    done
}

# Function to check Step Functions
check_stepfunctions_status() {
    echo -e "${PURPLE}🔄 STEP FUNCTIONS STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    if STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null); then
        SF_ARN=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[]? | select(.OutputKey=="StepFunctionsStateMachineArn") | .OutputValue')
        
        if [ -n "$SF_ARN" ] && [ "$SF_ARN" != "null" ]; then
            if SF_INFO=$(aws stepfunctions describe-state-machine --state-machine-arn "$SF_ARN" --region "$REGION" 2>/dev/null); then
                STATUS=$(echo "$SF_INFO" | jq -r '.status')
                CREATION_DATE=$(echo "$SF_INFO" | jq -r '.creationDate')
                
                echo -e "State Machine: ${GREEN}$(echo "$SF_ARN" | cut -d: -f6)${NC}"
                echo -e "Status: ${BLUE}$STATUS${NC}"
                echo -e "Created: ${BLUE}$CREATION_DATE${NC}"
                
                # Get recent executions
                echo -e "\n${YELLOW}Recent Executions (Last 10):${NC}"
                aws stepfunctions list-executions --state-machine-arn "$SF_ARN" --max-items 10 --region "$REGION" 2>/dev/null | \
                    jq -r '.executions[]? | "\(.status) - \(.startDate) - \(.name)"' | while read -r execution; do
                    echo "  $execution"
                done 2>/dev/null || echo "  No recent executions"
                
                # Count executions by status
                echo -e "\n${YELLOW}Execution Summary (Last 50):${NC}"
                EXECUTIONS_JSON=$(aws stepfunctions list-executions --state-machine-arn "$SF_ARN" --max-items 50 --region "$REGION" 2>/dev/null || echo '{"executions":[]}')
                
                SUCCEEDED=$(echo "$EXECUTIONS_JSON" | jq -r '.executions[]? | select(.status=="SUCCEEDED") | .status' | wc -l | tr -d ' ')
                FAILED=$(echo "$EXECUTIONS_JSON" | jq -r '.executions[]? | select(.status=="FAILED") | .status' | wc -l | tr -d ' ')
                RUNNING=$(echo "$EXECUTIONS_JSON" | jq -r '.executions[]? | select(.status=="RUNNING") | .status' | wc -l | tr -d ' ')
                
                echo -e "  ${GREEN}Succeeded: $SUCCEEDED${NC}"
                echo -e "  ${RED}Failed: $FAILED${NC}"
                echo -e "  ${YELLOW}Running: $RUNNING${NC}"
            fi
        fi
    fi
}

# Function to check RDS database
check_database_status() {
    echo -e "\n${PURPLE}🗄️  DATABASE STATUS${NC}"
    echo "────────────────────────────────────────────────────"
    
    DB_IDENTIFIER="${ENVIRONMENT}-glue-etl-db"
    
    if DB_INFO=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --region "$REGION" 2>/dev/null); then
        DB_STATUS=$(echo "$DB_INFO" | jq -r '.DBInstances[0].DBInstanceStatus')
        ENGINE_VERSION=$(echo "$DB_INFO" | jq -r '.DBInstances[0].EngineVersion')
        DB_CLASS=$(echo "$DB_INFO" | jq -r '.DBInstances[0].DBInstanceClass')
        ENDPOINT=$(echo "$DB_INFO" | jq -r '.DBInstances[0].Endpoint.Address')
        
        case $DB_STATUS in
            "available")
                echo -e "Status: ${GREEN}$DB_STATUS${NC}"
                ;;
            "creating"|"modifying"|"backing-up")
                echo -e "Status: ${YELLOW}$DB_STATUS${NC}"
                ;;
            *)
                echo -e "Status: ${RED}$DB_STATUS${NC}"
                ;;
        esac
        
        echo -e "Engine Version: ${BLUE}$ENGINE_VERSION${NC}"
        echo -e "Instance Class: ${BLUE}$DB_CLASS${NC}"
        echo -e "Endpoint: ${BLUE}$ENDPOINT${NC}"
        
        # Check recent connections (if CloudWatch metrics available)
        echo -e "\n${YELLOW}Database Metrics (24h):${NC}"
        END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
        START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S.000Z)
        
        CONNECTIONS=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/RDS \
            --metric-name DatabaseConnections \
            --dimensions Name=DBInstanceIdentifier,Value="$DB_IDENTIFIER" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --period 3600 \
            --statistics Average \
            --region "$REGION" 2>/dev/null | jq -r '.Datapoints | length')
        
        echo -e "  Connection Metrics Available: ${BLUE}${CONNECTIONS:-0} data points${NC}"
    else
        echo -e "${RED}Database not found or inaccessible${NC}"
    fi
}

# Function to show recent errors
check_recent_errors() {
    echo -e "\n${PURPLE}⚠️  RECENT ERRORS & ISSUES${NC}"
    echo "────────────────────────────────────────────────────"
    
    # Check Lambda function errors
    echo -e "${YELLOW}Lambda Function Errors (24h):${NC}"
    for function_name in "${ENVIRONMENT}-glue-etl-s3-trigger" "${ENVIRONMENT}-glue-etl-release-lock"; do
        ERROR_COUNT=$(aws logs filter-log-events \
            --log-group-name "/aws/lambda/$function_name" \
            --start-time $(($(date +%s) - 86400))000 \
            --filter-pattern "ERROR" \
            --region "$REGION" 2>/dev/null | jq -r '.events | length')
        
        if [ "${ERROR_COUNT:-0}" -gt 0 ]; then
            echo -e "  ${RED}$function_name: $ERROR_COUNT errors${NC}"
        else
            echo -e "  ${GREEN}$function_name: No errors${NC}"
        fi
    done
    
    # Check Glue job failures
    echo -e "\n${YELLOW}Glue Job Failures (Recent):${NC}"
    for job_name in "${ENVIRONMENT}-raw-ingestion-job" "${ENVIRONMENT}-transformation-job" "${ENVIRONMENT}-csv-export-job" "${ENVIRONMENT}-file-archiver-job"; do
        FAILED_RUNS=$(aws glue get-job-runs --job-name "$job_name" --max-items 10 --region "$REGION" 2>/dev/null | \
            jq -r '.JobRuns[]? | select(.JobRunState=="FAILED") | .Id' | wc -l | tr -d ' ')
        
        if [ "${FAILED_RUNS:-0}" -gt 0 ]; then
            echo -e "  ${RED}$job_name: $FAILED_RUNS recent failures${NC}"
        else
            echo -e "  ${GREEN}$job_name: No recent failures${NC}"
        fi
    done
    
    # Check Step Functions failures
    if STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null); then
        SF_ARN=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Outputs[]? | select(.OutputKey=="StepFunctionsStateMachineArn") | .OutputValue')
        
        if [ -n "$SF_ARN" ] && [ "$SF_ARN" != "null" ]; then
            FAILED_EXECUTIONS=$(aws stepfunctions list-executions --state-machine-arn "$SF_ARN" --status-filter FAILED --max-items 10 --region "$REGION" 2>/dev/null | \
                jq -r '.executions | length')
            
            echo -e "\n${YELLOW}Step Functions Failures (Recent):${NC}"
            if [ "${FAILED_EXECUTIONS:-0}" -gt 0 ]; then
                echo -e "  ${RED}Recent failed executions: $FAILED_EXECUTIONS${NC}"
            else
                echo -e "  ${GREEN}No recent failed executions${NC}"
            fi
        fi
    fi
}

# Function to show cost estimates
show_cost_info() {
    echo -e "\n${PURPLE}💰 ESTIMATED COSTS${NC}"
    echo "────────────────────────────────────────────────────"
    
    echo -e "${YELLOW}Monthly Cost Estimates (USD):${NC}"
    echo "  RDS db.t3.micro (24/7): ~$12-15"
    echo "  Lambda (1M requests): ~$0.20"
    echo "  Glue jobs (100 DPU-hours): ~$44"
    echo "  Step Functions (1K transitions): ~$0.025"
    echo "  S3 storage (100GB): ~$2.30"
    echo "  CloudWatch logs: ~$0.50"
    echo ""
    echo -e "${GREEN}Total estimated monthly cost: $60-70 USD${NC}"
    echo -e "${YELLOW}Note: Actual costs depend on usage patterns${NC}"
}

# Function to display monitoring dashboard URLs
show_monitoring_urls() {
    echo -e "\n${PURPLE}🖥️  MONITORING DASHBOARDS${NC}"
    echo "────────────────────────────────────────────────────"
    
    echo -e "${YELLOW}AWS Console Links:${NC}"
    echo "CloudFormation Stack:"
    echo "  https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks/stackinfo?stackId=$STACK_NAME"
    echo ""
    echo "Step Functions:"
    echo "  https://console.aws.amazon.com/states/home?region=$REGION#/statemachines"
    echo ""
    echo "Glue Jobs:"
    echo "  https://console.aws.amazon.com/glue/home?region=$REGION#etl:tab=jobs"
    echo ""
    echo "Lambda Functions:"
    echo "  https://console.aws.amazon.com/lambda/home?region=$REGION#/functions"
    echo ""
    echo "CloudWatch Logs:"
    echo "  https://console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
}

# Function to show help
show_help() {
    echo "Usage: $0 [ENVIRONMENT] [REGION]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT       Environment name (dev, test, prod). Default: dev"
    echo "  REGION           AWS region. Default: us-east-1"
    echo ""
    echo "This script provides comprehensive monitoring including:"
    echo "  • CloudFormation stack status"
    echo "  • S3 bucket contents and activity"
    echo "  • Lambda function health and invocations"
    echo "  • Glue job status and recent runs"
    echo "  • Step Functions execution history"
    echo "  • RDS database status"
    echo "  • Recent errors and issues"
    echo "  • Cost estimates"
    echo "  • Monitoring dashboard links"
    echo ""
    echo "Examples:"
    echo "  $0 dev us-east-1"
    echo "  $0 prod us-west-2"
}

# Main execution function
main() {
    check_aws_cli
    
    if check_stack_status; then
        check_s3_status
        check_lambda_status
        check_glue_status
        check_stepfunctions_status
        check_database_status
        check_recent_errors
        show_cost_info
        show_monitoring_urls
    fi
    
    echo -e "\n${GREEN}Status check completed! 📊${NC}"
}

# Handle script arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
    exit 0
fi

# Run main function
main