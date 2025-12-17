set -e  # Exit on error

# Source AWS configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/aws-config.sh"

# Source color definitions
source "${SCRIPT_DIR}/colors.sh"

# Default parameters
ENVIRONMENT="${1:-dev}"

# Configuration
STACK_NAME="OCF-${ENVIRONMENT}"

echo -e "\n${CYAN}Clearing CloudWatch logs in background...${NC}"
"${SCRIPT_DIR}/clear-logs.sh" "${STACK_NAME}"
