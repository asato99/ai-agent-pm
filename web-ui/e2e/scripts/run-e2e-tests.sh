#!/bin/bash
# Run E2E tests with isolated test database
#
# This script:
# 1. Sets up a fresh test database
# 2. Starts the REST server with the test database
# 3. Runs E2E tests
# 4. Cleans up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../.."
WEB_UI_DIR="$SCRIPT_DIR/../.."

# Test database path (isolated from production)
export AIAGENTPM_E2E_DB_PATH="${AIAGENTPM_E2E_DB_PATH:-/tmp/AIAgentPM_E2ETest.db}"
export AIAGENTPM_DB_PATH="$AIAGENTPM_E2E_DB_PATH"

# REST server port for E2E tests
E2E_REST_PORT="${E2E_REST_PORT:-8080}"

# PID file for cleanup
REST_SERVER_PID=""

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$REST_SERVER_PID" ] && kill -0 "$REST_SERVER_PID" 2>/dev/null; then
        echo "Stopping REST server (PID: $REST_SERVER_PID)..."
        kill "$REST_SERVER_PID" 2>/dev/null || true
        wait "$REST_SERVER_PID" 2>/dev/null || true
    fi
    echo "Cleanup complete."
}

trap cleanup EXIT

echo "=== Web-UI E2E Test Runner ==="
echo "Test DB: $AIAGENTPM_E2E_DB_PATH"
echo "REST Port: $E2E_REST_PORT"
echo ""

# Step 1: Setup test data
echo "Step 1: Setting up test database..."
"$SCRIPT_DIR/setup-test-data.sh"
echo ""

# Step 2: Start REST server in background
echo "Step 2: Starting REST server..."
REST_SERVER_BIN="$PROJECT_ROOT/.build/release/rest-server-pm"

if [ ! -f "$REST_SERVER_BIN" ]; then
    echo "Error: REST server binary not found at $REST_SERVER_BIN"
    echo "Please build the project first: swift build -c release"
    exit 1
fi

AIAGENTPM_DB_PATH="$AIAGENTPM_E2E_DB_PATH" \
AIAGENTPM_WEBSERVER_PORT="$E2E_REST_PORT" \
"$REST_SERVER_BIN" &
REST_SERVER_PID=$!

echo "REST server started (PID: $REST_SERVER_PID)"

# Wait for server to be ready
echo "Waiting for server to be ready..."
for i in {1..30}; do
    if curl -s "http://localhost:$E2E_REST_PORT/health" > /dev/null 2>&1; then
        echo "Server is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Error: Server failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done
echo ""

# Step 3: Run E2E tests
echo "Step 3: Running E2E tests..."
cd "$WEB_UI_DIR"

# Run Playwright tests
npx playwright test "$@"
TEST_EXIT_CODE=$?

echo ""
echo "=== E2E Tests Complete ==="
exit $TEST_EXIT_CODE
