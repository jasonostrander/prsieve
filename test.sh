#!/bin/bash
set -euo pipefail

echo "Building tests..."

# Collect all source files except the @main app entry point
SOURCES=$(find Sources/PRSieve -name '*.swift' ! -name 'PRSieveApp.swift' | sort)
TEST_FILE="Tests/PRSieveTests/PRSieveTests.swift"

swiftc \
    -parse-as-library \
    -module-name PRSieveTests \
    -sdk "$(xcrun --show-sdk-path)" \
    $SOURCES \
    "$TEST_FILE" \
    -o .build/PRSieveTests

echo "Running tests..."
.build/PRSieveTests
