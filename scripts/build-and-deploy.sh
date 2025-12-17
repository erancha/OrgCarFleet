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
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INGESTION_SERVICE_DIR="${REPO_ROOT}/backend/ingestion-service"
INGESTION_DEPLOY_SCRIPT="${INGESTION_SERVICE_DIR}/scripts/build-and-deploy.sh"
CAR_TELEMETRY_SERVICE_DIR="${REPO_ROOT}/backend/car-telemetry-service"
CAR_TELEMETRY_DEPLOY_SCRIPT="${CAR_TELEMETRY_SERVICE_DIR}/scripts/build-and-deploy.sh"
REALTIME_NOTIFICATIONS_SERVICE_DIR="${REPO_ROOT}/backend/realtime-notifications"
REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT="${REALTIME_NOTIFICATIONS_SERVICE_DIR}/scripts/build-and-deploy.sh"

# Get AWS Account ID
echo -e "${CYAN}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>"${SCRIPT_DIR}/.aws-sts-error.log" || true)

if [ -z "$ACCOUNT_ID" ] && grep -q "InvalidClientTokenId" "${SCRIPT_DIR}/.aws-sts-error.log" 2>/dev/null; then
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_SECURITY_TOKEN
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>"${SCRIPT_DIR}/.aws-sts-error.log" || true)
fi

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS Account ID. Make sure AWS CLI is configured and credentials are valid.${NC}"
    echo -e "${YELLOW}AWS error:${NC} $(cat "${SCRIPT_DIR}/.aws-sts-error.log" 2>/dev/null)"
    echo -e "${YELLOW}Tip:${NC} Run 'aws configure list' and 'aws sts get-caller-identity'. If you use SSO, run 'aws sso login --profile <profile>' and export AWS_PROFILE=<profile>."
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

# -----------------------------------------------------------------------------------------------------------------------------------
# Deploy Ingestion Service
echo -e "\n${CYAN}Deploying Ingestion Service...${NC}"
if [ ! -f "${INGESTION_DEPLOY_SCRIPT}" ]; then
    echo -e "${RED}Error: Ingestion service deployment script not found at ${INGESTION_DEPLOY_SCRIPT}${NC}"
    exit 1
fi

chmod +x "${INGESTION_DEPLOY_SCRIPT}"
sed -i 's/\r$//' "${INGESTION_DEPLOY_SCRIPT}" || true

"${INGESTION_DEPLOY_SCRIPT}"

# -----------------------------------------------------------------------------------------------------------------------------------
# Deploy Car Telemetry Service
echo -e "\n${CYAN}Deploying Car Telemetry Service...${NC}"
if [ ! -f "${CAR_TELEMETRY_DEPLOY_SCRIPT}" ]; then
    echo -e "${RED}Error: Car telemetry service deployment script not found at ${CAR_TELEMETRY_DEPLOY_SCRIPT}${NC}"
    exit 1
fi

chmod +x "${CAR_TELEMETRY_DEPLOY_SCRIPT}"
sed -i 's/\r$//' "${CAR_TELEMETRY_DEPLOY_SCRIPT}" || true

"${CAR_TELEMETRY_DEPLOY_SCRIPT}" up

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Car telemetry service deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}Car Telemetry Service deployed successfully${NC}"

# -----------------------------------------------------------------------------------------------------------------------------------
# Deploy Realtime Notifications Service
echo -e "\n${CYAN}Starting Realtime Notifications Service...${NC}"
if [ ! -f "${REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT}" ]; then
    echo -e "${RED}Error: Realtime notifications deployment script not found at ${REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT}${NC}"
    exit 1
fi

chmod +x "${REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT}"
sed -i 's/\r$//' "${REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT}" || true

"${REALTIME_NOTIFICATIONS_DEPLOY_SCRIPT}" up

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Realtime notifications service deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}Realtime Notifications Service started successfully${NC}"

# -----------------------------------------------------------------------------------------------------------------------------------
echo -e "\n${GREEN}=== All Services Deployed Successfully ===${NC}"
