#!/bin/bash

# Load Testing Script for OrgCarFleet API
# Sends 1000 requests with 100 concurrent workers using curl
#
# Usage:
#   ./load-test.sh <API_URL> <ID_TOKEN> [TOTAL_REQUESTS] [CONCURRENT_WORKERS]
#
# Example:
#   ./load-test.sh https://abc123.execute-api.eu-central-1.amazonaws.com/dev eyJraWq... 100 10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <API_URL> <ID_TOKEN> [TOTAL_REQUESTS] [CONCURRENT_WORKERS]"
    echo "Example: $0 https://abc123.execute-api.eu-central-1.amazonaws.com/dev eyJraWq... 100 10"
    echo ""
    echo "Arguments:"
    echo "  API_URL             - Base API URL (without /api suffix)"
    echo "  ID_TOKEN            - Cognito ID token for authentication"
    echo "  TOTAL_REQUESTS      - Total number of requests to send (default: 100)"
    echo "  CONCURRENT_WORKERS  - Number of concurrent workers (default: 10)"
    exit 1
fi

API_URL="$1/api"
ID_TOKEN="$2"
TOTAL_REQUESTS="${3:-100}"
CONCURRENT_WORKERS="${4:-10}"

# Sample payloads
PAYLOAD_CAR='{"type":"car","action":"status-update","vehicleId":"CAR-001","status":"available","location":{"lat":40.7128,"lng":-74.006}}'
PAYLOAD_FLEET='{"type":"fleet","action":"fleet-update","fleetId":"FLEET-001","vehicleCount":25}'
PAYLOAD_ORG='{"type":"org","action":"org-created","orgId":"ORG-001","name":"Acme Corporation"}'

# Create temp directory for results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "======================================================================"
echo "OrgCarFleet API Load Test"
echo "======================================================================"
echo "API URL: $API_URL"
echo "Total Requests: $TOTAL_REQUESTS"
echo "Concurrent Workers: $CONCURRENT_WORKERS"
echo "======================================================================"
echo ""

START_TIME=$(date +%s)

# Function to send a single request
send_request() {
    local request_num=$1
    local payload_type=$((request_num % 3))
    local payload=""
    
    case $payload_type in
        0) payload="$PAYLOAD_CAR" ;;
        1) payload="$PAYLOAD_FLEET" ;;
        2) payload="$PAYLOAD_ORG" ;;
    esac
    
    # Send request and capture response time and status code
    # Write to temp file to avoid subshell issues
    local temp_response="$TEMP_DIR/response_$request_num.txt"
    
    curl -s -w "\n%{http_code}\n%{time_total}" -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: $ID_TOKEN" \
        -d "$payload" > "$temp_response" 2>&1
    
    # Extract status code and time from response (last 2 lines)
    status_code=$(tail -n 2 "$temp_response" | head -n 1)
    time_total=$(tail -n 1 "$temp_response")
    
    # Save result
    echo "$status_code,$time_total" >> "$TEMP_DIR/results.txt"
    
    # Clean up temp response file
    rm -f "$temp_response"
}

export -f send_request
export API_URL ID_TOKEN PAYLOAD_CAR PAYLOAD_FLEET PAYLOAD_ORG TEMP_DIR

# Generate request numbers and run in parallel
echo "Starting load test..."
seq 1 $TOTAL_REQUESTS | xargs -P $CONCURRENT_WORKERS -I {} bash -c 'send_request {}'

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

# Calculate statistics
echo ""
echo "Calculating statistics..."

TOTAL=$(wc -l < "$TEMP_DIR/results.txt")

# Debug: Show sample of status codes
echo "Sample status codes:"
head -n 5 "$TEMP_DIR/results.txt"
echo ""

# Count successes (200-299 status codes)
SUCCESS=$(awk -F',' '$1 >= 200 && $1 < 300 {count++} END {print count+0}' "$TEMP_DIR/results.txt")
FAILED=$((TOTAL - SUCCESS))

# Extract response times (in seconds, convert to ms)
awk -F',' '{print $2 * 1000}' "$TEMP_DIR/results.txt" | sort -n > "$TEMP_DIR/times.txt"

# Calculate percentiles
MIN=$(head -n 1 "$TEMP_DIR/times.txt")
MAX=$(tail -n 1 "$TEMP_DIR/times.txt")
AVG=$(awk '{sum+=$1} END {print sum/NR}' "$TEMP_DIR/times.txt")
P50=$(awk -v p=50 'BEGIN{c=0} {a[c++]=$1} END{print a[int(c*p/100)]}' "$TEMP_DIR/times.txt")
P95=$(awk -v p=95 'BEGIN{c=0} {a[c++]=$1} END{print a[int(c*p/100)]}' "$TEMP_DIR/times.txt")
P99=$(awk -v p=99 'BEGIN{c=0} {a[c++]=$1} END{print a[int(c*p/100)]}' "$TEMP_DIR/times.txt")

# Calculate requests per second
REQ_PER_SEC=$(echo "scale=2; $TOTAL / $TOTAL_TIME" | bc)

# Calculate percentages safely
if [ "$TOTAL" -gt 0 ]; then
    SUCCESS_PCT=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS * 100 / $TOTAL)}")
    FAILED_PCT=$(awk "BEGIN {printf \"%.1f\", ($FAILED * 100 / $TOTAL)}")
else
    SUCCESS_PCT="0.0"
    FAILED_PCT="0.0"
fi

# Print results
echo ""
echo "======================================================================"
echo "RESULTS"
echo "======================================================================"
echo "Total Requests:       $TOTAL"
echo -e "Successful:           ${GREEN}$SUCCESS${NC} (${SUCCESS_PCT}%)"
echo -e "Failed:               ${RED}$FAILED${NC} (${FAILED_PCT}%)"
echo "Total Time:           ${TOTAL_TIME}s"
echo "Requests/Second:      $REQ_PER_SEC"
echo ""
echo "Response Times (ms):"
printf "  Min:                %.2f\n" "$MIN"
printf "  Average:            %.2f\n" "$AVG"
printf "  Max:                %.2f\n" "$MAX"
printf "  P50 (median):       %.2f\n" "$P50"
printf "  P95:                %.2f\n" "$P95"
printf "  P99:                %.2f\n" "$P99"
echo "======================================================================"
