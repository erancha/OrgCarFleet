set -e  # Exit on error

# Source AWS configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aws-configure.sh"

# Configuration
STACK_NAME="OCF-${ENVIRONMENT}"

echo -e "\n${CYAN}Clearing CloudWatch logs in background...${NC}"
"${SCRIPT_DIR}/clear-logs.sh" "${STACK_NAME}"
