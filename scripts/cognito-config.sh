#!/bin/bash
# Cognito Configuration Helper
# Sets up Cognito User Pool ID and Domain based on AWS Account ID and Region

# Get AWS Account ID if not already set
if [ -z "$ACCOUNT_ID" ]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$ACCOUNT_ID" ]; then
        echo -e "${RED}Error: Could not get AWS Account ID. Make sure AWS CLI is configured.${NC}"
        exit 1
    fi
fi

# Get Region from AWS configuration if not already set
if [ -z "$REGION" ]; then
    REGION="${AWS_DEFAULT_REGION}"
fi

# Cognito Configuration
export USER_POOL_ID="${REGION}_AGzi24ZGD"
export COGNITO_DOMAIN="vsdb-${ACCOUNT_ID}.auth.${REGION}.amazoncognito.com"
