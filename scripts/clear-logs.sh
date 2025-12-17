#!/bin/bash
# Clear CloudWatch log streams for OrgCarFleet Lambda functions
# Usage: ./clear-logs.sh <stack-name>

set -e  # Exit on error

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if stack name is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Stack name is required${NC}"
    echo "Usage: $0 <stack-name>"
    exit 1
fi

STACK_NAME="$1"

echo -e "${CYAN}Clearing log streams for stack: ${STACK_NAME}${NC}"

# Get all log groups that contain the stack name
LOG_GROUPS=$(aws logs describe-log-groups \
    --query "logGroups[?contains(logGroupName, '${STACK_NAME}')].logGroupName" \
    --output text)

if [ -z "$LOG_GROUPS" ]; then
    echo -e "${YELLOW}No log groups found containing '${STACK_NAME}'${NC}"
    exit 0
fi

echo -e "${CYAN}Found log groups:${NC}"
echo "$LOG_GROUPS" | tr '\t' '\n' | while read -r group; do
    echo -e "  ${YELLOW}${group}${NC}"
done

# Delete log streams from each log group
echo -e "\n${CYAN}Deleting log streams...${NC}"
echo "$LOG_GROUPS" | tr '\t' '\n' | while read -r log_group; do
    if [ -n "$log_group" ]; then
        echo -e "${CYAN}Processing: ${log_group}${NC}"
        
        # Get all log streams in the group
        LOG_STREAMS=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --query 'logStreams[].logStreamName' \
            --output text)
        
        if [ -n "$LOG_STREAMS" ]; then
            # Delete each log stream
            echo "$LOG_STREAMS" | tr '\t' '\n' | while read -r stream; do
                if [ -n "$stream" ]; then
                    echo -e "  Deleting stream: ${stream}"
                    aws logs delete-log-stream \
                        --log-group-name "$log_group" \
                        --log-stream-name "$stream" 2>/dev/null || true
                fi
            done
            echo -e "${GREEN}  ✓ Cleared log streams from ${log_group}${NC}"
        else
            echo -e "${YELLOW}  No log streams found in ${log_group}${NC}"
        fi
    fi
done

echo -e "\n${GREEN}Log streams cleared successfully${NC}"
