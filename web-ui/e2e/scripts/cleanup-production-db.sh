#!/bin/bash
# Cleanup test data from production database
#
# This script removes test data that was accidentally inserted into the production database.
# Run this ONCE to clean up, then use setup-test-data.sh with the test database.

set -e

PROD_DB_PATH="$HOME/Library/Application Support/AIAgentPM/pm.db"

if [ ! -f "$PROD_DB_PATH" ]; then
    echo "Production database not found at: $PROD_DB_PATH"
    exit 0
fi

echo "=== Cleanup Test Data from Production DB ==="
echo "DB Path: $PROD_DB_PATH"
echo ""

# Show what will be deleted
echo "Test data to be removed:"
echo ""
echo "Agents:"
sqlite3 "$PROD_DB_PATH" "SELECT id, name FROM agents WHERE id IN ('owner-1', 'manager-1', 'worker-1', 'worker-2');" 2>/dev/null || echo "  (none)"
echo ""
echo "Projects:"
sqlite3 "$PROD_DB_PATH" "SELECT id, name FROM projects WHERE id IN ('project-1', 'project-2');" 2>/dev/null || echo "  (none)"
echo ""
echo "Tasks (sample):"
sqlite3 "$PROD_DB_PATH" "SELECT id, title FROM tasks WHERE id LIKE 'task-%' LIMIT 5;" 2>/dev/null || echo "  (none)"
echo ""

read -p "Remove this test data from production? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Removing test data..."

# Delete in correct order (foreign key constraints)
sqlite3 "$PROD_DB_PATH" "DELETE FROM tasks WHERE id LIKE 'task-%' OR id LIKE 'task-2%';"
sqlite3 "$PROD_DB_PATH" "DELETE FROM agent_credentials WHERE agent_id IN ('manager-1', 'worker-1', 'worker-2', 'owner-1');"
sqlite3 "$PROD_DB_PATH" "DELETE FROM agents WHERE id IN ('manager-1', 'worker-1', 'worker-2', 'owner-1');"
sqlite3 "$PROD_DB_PATH" "DELETE FROM projects WHERE id IN ('project-1', 'project-2');"

echo "Test data removed successfully!"
echo ""
echo "Remaining data:"
echo "Projects: $(sqlite3 "$PROD_DB_PATH" "SELECT COUNT(*) FROM projects;")"
echo "Agents: $(sqlite3 "$PROD_DB_PATH" "SELECT COUNT(*) FROM agents;")"
echo "Tasks: $(sqlite3 "$PROD_DB_PATH" "SELECT COUNT(*) FROM tasks;")"
