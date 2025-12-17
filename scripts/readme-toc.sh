#!/bin/bash

# Install markdown-toc if not already installed
if ! command -v markdown-toc &> /dev/null; then
    echo "Installing markdown-toc..."
    npm install -g markdown-toc
fi

# Note! Insert <!-- toc --> and <!-- tocstop --> in the required position

set -x
markdown-toc -i ../README.md
markdown-toc -i ../backend/ingestion-service/README.md
markdown-toc -i ../backend/car-telemetry-service/README.md
markdown-toc -i ../backend/realtime-notifications/README.md

sleep 3
# read -p "Press enter to continue"
