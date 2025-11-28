#!/bin/bash
# OrgCarFleet Deployment Script
# Deploys API Gateway, Lambda, and SQS with Cognito authentication

set -e  # Exit on error

# Source AWS configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aws-configure.sh"

# Default parameters
ENVIRONMENT="${1:-dev}"
REGION="${AWS_DEFAULT_REGION}"

# Configuration
STACK_NAME="OCF-${ENVIRONMENT}"
TEMPLATE_FILE="template.yaml"
BACKEND_DIR="../backend"

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

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

# Get AWS Account ID
echo -e "${CYAN}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS Account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi

echo -e "${GREEN}Account ID: ${ACCOUNT_ID}${NC}"

# Cognito Configuration (same as Summaries.AI)
USER_POOL_ID="${REGION}_AGzi24ZGD"
COGNITO_DOMAIN="vsdb-${ACCOUNT_ID}.auth.${REGION}.amazoncognito.com"

echo -e "\n${CYAN}Configuration:${NC}"
echo "  Stack Name: ${STACK_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Region: ${REGION}"
echo "  User Pool ID: ${USER_POOL_ID}"
echo "  Cognito Domain: ${COGNITO_DOMAIN}"

# Clean SAM build cache
echo -e "\n${CYAN}Cleaning SAM build cache...${NC}"
if [ -d ".aws-sam" ]; then
    rm -rf .aws-sam
    echo -e "${GREEN}Removed .aws-sam directory${NC}"
fi

# Build with SAM CLI
echo -e "\n${CYAN}Building Lambda package with SAM...${NC}"
sam build --template-file "$TEMPLATE_FILE" --use-container

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: SAM build failed${NC}"
    exit 1
fi

echo -e "${GREEN}Lambda package built successfully${NC}"

echo -e "\n${CYAN}Deploying to AWS...${NC}"
sam deploy \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --capabilities CAPABILITY_IAM \
    --resolve-s3 \
    --parameter-overrides \
        "Environment=${ENVIRONMENT}" \
        "ExistingUserPoolId=${USER_POOL_ID}" \
        "ExistingCognitoDomain=${COGNITO_DOMAIN}" \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: SAM deploy failed${NC}"
    exit 1
fi

# Get stack outputs
echo -e "\n${CYAN}Retrieving stack outputs...${NC}"
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

echo -e "\n${GREEN}=== Deployment Successful ===${NC}"
echo -e "\n${CYAN}Stack Outputs:${NC}"

# Parse and display outputs
echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"' | while read -r line; do
    echo -e "${YELLOW}${line}${NC}"
done

# Save outputs to frontend config
API_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiUrl") | .OutputValue')
CLIENT_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserPoolClientId") | .OutputValue')

# Create frontend config
cat > "../frontend/src/config.js" << EOF
export const config = {
  apiUrl: '${API_URL}',
  region: '${REGION}',
  userPoolId: '${USER_POOL_ID}',
  cognitoDomain: '${COGNITO_DOMAIN}',
  clientId: '${CLIENT_ID}',
  redirectUri: 'http://localhost:3000/'
};
EOF

echo -e "\n${GREEN}Frontend configuration saved to: ../frontend/src/config.js${NC}"
echo -e "${GREEN}Cognito App Client ID automatically configured: ${CLIENT_ID}${NC}"

echo -e "\n${CYAN}Next steps:${NC}"
echo -e "${WHITE}1. Run 'cd ../frontend && npm install && npm start'${NC}"
echo -e "${WHITE}2. (If not automatically opened) Open http://localhost:3000 in your browser${NC}"
echo -e "${WHITE}3. Sign in with Google to test the application${NC}"

cd ../frontend && npm install && npm start