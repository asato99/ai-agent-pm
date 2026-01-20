#!/bin/bash
# Setup test data for E2E tests

set -e

DB_PATH="$HOME/Library/Application Support/AIAgentPM/pm.db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/seed-test-data.sql"

if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found at $DB_PATH"
    echo "Please run the macOS app first to create the database."
    exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found at $SQL_FILE"
    exit 1
fi

echo "Seeding test data into database..."
sqlite3 "$DB_PATH" < "$SQL_FILE"
echo "Test data inserted successfully!"

# Verify the data
echo ""
echo "Verifying test data:"
echo ""
echo "Agents:"
sqlite3 "$DB_PATH" "SELECT id, name, hierarchy_type FROM agents WHERE id IN ('owner-1', 'manager-1', 'worker-1', 'worker-2');"
echo ""
echo "Projects:"
sqlite3 "$DB_PATH" "SELECT id, name FROM projects WHERE id IN ('project-1', 'project-2');"
echo ""
echo "Task counts:"
sqlite3 "$DB_PATH" "SELECT project_id, COUNT(*) as task_count FROM tasks WHERE project_id IN ('project-1', 'project-2') GROUP BY project_id;"
echo ""
echo "Credentials:"
sqlite3 "$DB_PATH" "SELECT agent_id, raw_passkey FROM agent_credentials WHERE agent_id IN ('manager-1', 'worker-1');"
