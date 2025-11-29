#!/bin/bash
# Ingestion Service Deployment Script
# Deploys API Gateway, Lambda, SQS, and Cognito resources for the ingestion service

set -e  # Exit on error

# Source AWS configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../scripts/aws-config.sh"

# Source color definitions
source "${SCRIPT_DIR}/../../../scripts/colors.sh"

# Default parameters
ENVIRONMENT="${1:-dev}"

# Configuration
REGION="${AWS_DEFAULT_REGION}"
STACK_NAME="OCF-ing-${ENVIRONMENT}"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"

# Kafka Configuration
KAFKA_BROKER_ENDPOINT="ec2-3-71-113-150.${REGION}.compute.amazonaws.com:19092"

# Get AWS Account ID
echo -e "${CYAN}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS Account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi

echo -e "${GREEN}Account ID: ${ACCOUNT_ID}${NC}"

# Source Cognito Configuration
source "${SCRIPT_DIR}/../../../scripts/cognito-config.sh"

echo -e "\n${CYAN}=== Ingestion Service Deployment ===${NC}"
echo -e "${CYAN}Configuration:${NC}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Stack Name: ${STACK_NAME}"
echo "  Region: ${REGION}"
echo "  User Pool ID: ${USER_POOL_ID}"
echo "  Cognito Domain: ${COGNITO_DOMAIN}"
echo "  Kafka Broker: ${KAFKA_BROKER_ENDPOINT}"

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo -e "${YELLOW}AWS SAM CLI not found. Installing...${NC}"
    
    # Download and install SAM CLI
    curl -L https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip -o /tmp/sam-installation.zip
    unzip -q /tmp/sam-installation.zip -d /tmp/sam-installation
    sudo /tmp/sam-installation/install
    
    # Verify installation
    if command -v sam &> /dev/null; then
        echo -e "${GREEN}SAM CLI installed successfully: $(sam --version)${NC}"
    else
        echo -e "${RED}Error: Failed to install SAM CLI${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}SAM CLI found: $(sam --version)${NC}"
fi

# Change to script directory for SAM operations
cd "${SCRIPT_DIR}"

# Clean SAM build cache
echo -e "\n${CYAN}Cleaning SAM build cache...${NC}"
if [ -d ".aws-sam" ]; then
    rm -rf .aws-sam
    echo -e "${GREEN}Removed .aws-sam directory${NC}"
fi

# Build with SAM CLI
echo -e "\n${CYAN}Building Lambda package with SAM...${NC}"
SAM_CLI_TELEMETRY=0 sam build --template-file template.yaml --use-container --build-dir .aws-sam/build

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: SAM build failed${NC}"
    exit 1
fi

echo -e "${GREEN}Lambda package built successfully${NC}"

# Deploy with SAM CLI (already in SCRIPT_DIR)
echo -e "\n${CYAN}Deploying ingestion service to AWS...${NC}"
SAM_CLI_TELEMETRY=0 sam deploy \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --capabilities CAPABILITY_IAM \
    --resolve-s3 \
    --parameter-overrides \
        "Environment=${ENVIRONMENT}" \
        "ExistingUserPoolId=${USER_POOL_ID}" \
        "ExistingCognitoDomain=${COGNITO_DOMAIN}" \
        "KafkaBrokerEndpoint=${KAFKA_BROKER_ENDPOINT}" \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: SAM deploy failed${NC}"
    exit 1
fi

# Clear CloudWatch logs in background
echo -e "\n${CYAN}Clearing CloudWatch logs in background...${NC}"
"${SCRIPT_DIR}/../../../scripts/clear-logs.sh" "${STACK_NAME}" &

# Get stack outputs
echo -e "\n${CYAN}Retrieving stack outputs...${NC}"
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

echo -e "\n${GREEN}=== Ingestion Service Deployment Successful ===${NC}"
echo -e "\n${CYAN}Stack Outputs:${NC}"

# Parse and display outputs
echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"' | while read -r line; do
    echo -e "${YELLOW}${line}${NC}"
done

# Export outputs for parent script
export API_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiUrl") | .OutputValue')
export CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolClientId") | .OutputValue')
export QUEUE_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="QueueUrl") | .OutputValue')

# Output for parent script to capture
echo "API_URL=${API_URL}"
echo "CLIENT_ID=${CLIENT_ID}"
echo "QUEUE_URL=${QUEUE_URL}"
