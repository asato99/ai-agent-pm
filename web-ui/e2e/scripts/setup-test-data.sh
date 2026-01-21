#!/bin/bash
# Setup test data for E2E tests
#
# IMPORTANT: This script uses a dedicated test database to avoid polluting production data.
# The REST server must be started with AIAGENTPM_DB_PATH pointing to the same test database.
#
# Usage:
#   1. Run this script to seed test data
#   2. Start REST server with: AIAGENTPM_DB_PATH=/tmp/AIAgentPM_E2ETest.db rest-server-pm
#   3. Run E2E tests

set -e

# Use dedicated test database path (NOT production!)
# This can be overridden via environment variable for CI/CD
E2E_TEST_DB_PATH="${AIAGENTPM_E2E_DB_PATH:-/tmp/AIAgentPM_E2ETest.db}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/seed-test-data.sql"
PROJECT_ROOT="$SCRIPT_DIR/../../.."

echo "=== Web-UI E2E Test Data Setup ==="
echo "Test DB Path: $E2E_TEST_DB_PATH"
echo ""

# Remove existing test database for clean state
if [ -f "$E2E_TEST_DB_PATH" ]; then
    echo "Removing existing test database..."
    rm -f "$E2E_TEST_DB_PATH"
    rm -f "${E2E_TEST_DB_PATH}-shm"
    rm -f "${E2E_TEST_DB_PATH}-wal"
fi

# Create fresh test database using the MCP server's auto-setup
# This ensures the schema is correct and matches what the app expects
echo "Creating fresh test database with schema..."
AIAGENTPM_DB_PATH="$E2E_TEST_DB_PATH" "$PROJECT_ROOT/.build/release/mcp-server-pm" setup 2>/dev/null || {
    echo "Note: mcp-server-pm setup command not available, trying alternative..."
    # Alternative: Start and immediately stop the server to create schema
    timeout 2 bash -c "AIAGENTPM_DB_PATH='$E2E_TEST_DB_PATH' '$PROJECT_ROOT/.build/release/mcp-server-pm' serve" 2>/dev/null || true
}

if [ ! -f "$E2E_TEST_DB_PATH" ]; then
    echo "Error: Failed to create test database."
    echo "Please build the project first: swift build -c release"
    echo "Or run: AIAGENTPM_DB_PATH=$E2E_TEST_DB_PATH mcp-server-pm serve (and stop it)"
    exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found at $SQL_FILE"
    exit 1
fi

echo "Seeding test data..."
sqlite3 "$E2E_TEST_DB_PATH" < "$SQL_FILE"
echo "Test data inserted successfully!"

# Verify the data
echo ""
echo "=== Verification ==="
echo ""
echo "Agents:"
sqlite3 "$E2E_TEST_DB_PATH" "SELECT id, name, hierarchy_type FROM agents WHERE id IN ('owner-1', 'manager-1', 'worker-1', 'worker-2');"
echo ""
echo "Projects:"
sqlite3 "$E2E_TEST_DB_PATH" "SELECT id, name FROM projects WHERE id IN ('project-1', 'project-2');"
echo ""
echo "Task counts:"
sqlite3 "$E2E_TEST_DB_PATH" "SELECT project_id, COUNT(*) as task_count FROM tasks WHERE project_id IN ('project-1', 'project-2') GROUP BY project_id;"
echo ""
echo "Credentials:"
sqlite3 "$E2E_TEST_DB_PATH" "SELECT agent_id, raw_passkey FROM agent_credentials WHERE agent_id IN ('manager-1', 'worker-1');"
echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run E2E tests, start the REST server with:"
echo "  AIAGENTPM_DB_PATH=$E2E_TEST_DB_PATH rest-server-pm"
echo ""
echo "Or use the run-e2e-tests.sh script which handles this automatically."
