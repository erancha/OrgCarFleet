#!/bin/bash
# OrgCarFleet Deployment Orchestrator
# Orchestrates deployment of all services and configures frontend

set -e  # Exit on error

# Source AWS configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aws-config.sh"

# Source color definitions
source "${SCRIPT_DIR}/colors.sh"

# Configuration
REGION="${AWS_DEFAULT_REGION}"
INGESTION_SERVICE_DIR="../backend/ingestion-service"
INGESTION_DEPLOY_SCRIPT="${INGESTION_SERVICE_DIR}/scripts/build-deploy.sh"

# Get AWS Account ID
echo -e "${CYAN}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS Account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi

echo -e "${GREEN}Account ID: ${ACCOUNT_ID}${NC}"

# Source Cognito Configuration
source "${SCRIPT_DIR}/cognito-config.sh"

echo -e "\n${CYAN}=== OrgCarFleet Deployment ===${NC}"
echo -e "${CYAN}Configuration:${NC}"
echo "  Region: ${REGION}"
echo "  User Pool ID: ${USER_POOL_ID}"
echo "  Cognito Domain: ${COGNITO_DOMAIN}"

# Deploy Ingestion Service
echo -e "\n${CYAN}Deploying Ingestion Service...${NC}"
if [ ! -f "${INGESTION_DEPLOY_SCRIPT}" ]; then
    echo -e "${RED}Error: Ingestion service deployment script not found at ${INGESTION_DEPLOY_SCRIPT}${NC}"
    exit 1
fi

chmod +x "${INGESTION_DEPLOY_SCRIPT}"

# Run ingestion service deployment and capture outputs
INGESTION_OUTPUT=$("${INGESTION_DEPLOY_SCRIPT}")

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Ingestion service deployment failed${NC}"
    exit 1
fi

# Parse outputs from ingestion service deployment
API_URL=$(echo "${INGESTION_OUTPUT}" | grep "^API_URL=" | cut -d'=' -f2)
CLIENT_ID=$(echo "${INGESTION_OUTPUT}" | grep "^CLIENT_ID=" | cut -d'=' -f2)
QUEUE_URL=$(echo "${INGESTION_OUTPUT}" | grep "^QUEUE_URL=" | cut -d'=' -f2)

echo -e "\n${GREEN}=== Deployment Successful ===${NC}"

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

# Start frontend in background
echo -e "\n${CYAN}Starting frontend...${NC}"
cd ../frontend && npm install && npm start
