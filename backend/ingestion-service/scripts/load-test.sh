#!/bin/bash

# Load Testing Script for OrgCarFleet API
# Sends 1000 requests with 100 concurrent workers using curl
#
# Usage:
#   ./load-test.sh <API_URL> <ID_TOKEN> [TOTAL_REQUESTS] [CONCURRENT_WORKERS] [PAYLOAD_TYPE]
#
# Example:
#   ./load-test.sh https://abc123.execute-api.eu-central-1.amazonaws.com/dev eyJraWq... 100 10 round-robin

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <API_URL> <ID_TOKEN> [TOTAL_REQUESTS] [CONCURRENT_WORKERS] [PAYLOAD_TYPE]"
    echo "Example: $0 https://abc123.execute-api.eu-central-1.amazonaws.com/dev eyJraWq... 100 10 round-robin"
    echo ""
    echo "Arguments:"
    echo "  API_URL             - Base API URL (without /api suffix)"
    echo "  ID_TOKEN            - Cognito ID token for authentication"
    echo "  TOTAL_REQUESTS      - Total number of requests to send (default: 100)"
    echo "  CONCURRENT_WORKERS  - Number of concurrent workers (default: 10)"
    echo "  PAYLOAD_TYPE        - Payload type: 'round-robin', 'car', 'fleet', or 'org' (default: round-robin)"
    exit 1
fi

API_URL="$1/api"
ID_TOKEN="$2"
TOTAL_REQUESTS="${3:-100}"
CONCURRENT_WORKERS="${4:-10}"
PAYLOAD_TYPE="${5:-round-robin}"

# Tel Aviv center coordinates
TEL_AVIV_LAT=32.0853
TEL_AVIV_LNG=34.7818
RADIUS_KM=1.0

# Function to generate random location within radius
generate_random_location() {
    # Generate random angle (0-360 degrees)
    local angle=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand() * 360}')
    # Generate random distance (0-1000m)
    local distance=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand() * 1000}')
    
    # Convert to lat/lng offset (approximate, 1 degree ≈ 111km)
    local lat_offset=$(awk -v dist=$distance -v angle=$angle 'BEGIN{print (dist/111000) * cos(angle * 3.14159/180)}')
    local lng_offset=$(awk -v dist=$distance -v angle=$angle -v lat=$TEL_AVIV_LAT 'BEGIN{print (dist/111000) * sin(angle * 3.14159/180) / cos(lat * 3.14159/180)}')
    
    # Calculate new coordinates
    local new_lat=$(awk -v base=$TEL_AVIV_LAT -v offset=$lat_offset 'BEGIN{printf "%.6f", base + offset}')
    local new_lng=$(awk -v base=$TEL_AVIV_LNG -v offset=$lng_offset 'BEGIN{printf "%.6f", base + offset}')
    
    echo "$new_lat,$new_lng"
}

# Sample payloads (car payload will be generated dynamically with random location)
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
echo "Payload Type: $PAYLOAD_TYPE"
echo "======================================================================"
echo ""

START_TIME=$(date +%s)

# Function to send a single request
send_request() {
    local request_num=$1
    local payload=""
    
    # Determine payload based on PAYLOAD_TYPE parameter
    case $PAYLOAD_TYPE in
        "car")
            # Generate random location for car payload
            local coords=$(generate_random_location)
            local lat=$(echo $coords | cut -d',' -f1)
            local lng=$(echo $coords | cut -d',' -f2)
            payload="{\"type\":\"car\",\"action\":\"status-update\",\"vehicleId\":\"CAR-$(printf '%03d' $((request_num % 100)))\",\"status\":\"available\",\"location\":{\"lat\":$lat,\"lng\":$lng}}"
            ;;
        "fleet")
            payload="$PAYLOAD_FLEET"
            ;;
        "org")
            payload="$PAYLOAD_ORG"
            ;;
        "round-robin"|*)
            # Round-robin through all three types
            local payload_type=$((request_num % 3))
            case $payload_type in
                0) 
                    # Generate random location for car payload
                    local coords=$(generate_random_location)
                    local lat=$(echo $coords | cut -d',' -f1)
                    local lng=$(echo $coords | cut -d',' -f2)
                    payload="{\"type\":\"car\",\"action\":\"status-update\",\"vehicleId\":\"CAR-$(printf '%03d' $((request_num % 100)))\",\"status\":\"available\",\"location\":{\"lat\":$lat,\"lng\":$lng}}"
                    ;;
                1) payload="$PAYLOAD_FLEET" ;;
                2) payload="$PAYLOAD_ORG" ;;
            esac
            ;;
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

export -f send_request generate_random_location
export API_URL ID_TOKEN PAYLOAD_FLEET PAYLOAD_ORG PAYLOAD_TYPE TEMP_DIR TEL_AVIV_LAT TEL_AVIV_LNG

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
