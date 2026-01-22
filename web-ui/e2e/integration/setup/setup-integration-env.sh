#!/bin/bash
# Setup Integration Test Environment
# Reference: docs/usecase/UC010_TaskInterruptByStatusChange.md
#
# This script sets up the complete environment for integration testing:
# 1. Creates test database with schema
# 2. Seeds integration test data
# 3. Starts required services (MCP server, REST server)
#
# Prerequisites:
#   - Swift project built: swift build -c release
#   - Node.js installed
#
# Usage:
#   ./setup-integration-env.sh         # Setup and start services
#   ./setup-integration-env.sh --seed  # Only seed data (services already running)
#   ./setup-integration-env.sh --stop  # Stop services

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../../.."
WEB_UI_ROOT="$SCRIPT_DIR/../../.."
INTEGRATION_DB_PATH="${AIAGENTPM_INTEGRATION_DB_PATH:-/tmp/AIAgentPM_Integration.db}"
MCP_SOCKET_PATH="${AIAGENTPM_INTEGRATION_SOCKET:-/tmp/aiagentpm_integration.sock}"
REST_PORT="${AIAGENTPM_INTEGRATION_REST_PORT:-8082}"
SQL_FILE="$SCRIPT_DIR/seed-integration-data.sql"
PID_FILE="/tmp/aiagentpm_integration_pids"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

stop_services() {
    log_info "Stopping integration test services..."

    if [ -f "$PID_FILE" ]; then
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                log_info "Stopping process $pid"
                kill "$pid" 2>/dev/null || true
            fi
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi

    # Also clean up socket file
    rm -f "$MCP_SOCKET_PATH"

    log_info "Services stopped"
}

seed_data() {
    log_info "Seeding integration test data..."

    if [ ! -f "$SQL_FILE" ]; then
        log_error "SQL file not found: $SQL_FILE"
        exit 1
    fi

    if [ ! -f "$INTEGRATION_DB_PATH" ]; then
        log_error "Database not found: $INTEGRATION_DB_PATH"
        log_error "Run without --seed first to create database"
        exit 1
    fi

    sqlite3 "$INTEGRATION_DB_PATH" < "$SQL_FILE"
    log_info "Integration test data seeded successfully"

    # Verify
    echo ""
    log_info "Verification:"
    echo "Integration Agents:"
    sqlite3 "$INTEGRATION_DB_PATH" "SELECT id, name, hierarchy_type FROM agents WHERE id LIKE 'integ-%';"
    echo ""
    echo "Integration Tasks:"
    sqlite3 "$INTEGRATION_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks WHERE id LIKE 'integ-%';"
}

setup_database() {
    log_info "Setting up integration test database..."

    # Remove existing database
    if [ -f "$INTEGRATION_DB_PATH" ]; then
        log_info "Removing existing database..."
        rm -f "$INTEGRATION_DB_PATH"
        rm -f "${INTEGRATION_DB_PATH}-shm"
        rm -f "${INTEGRATION_DB_PATH}-wal"
    fi

    # Create database with schema
    log_info "Creating database with schema..."
    if [ -x "$PROJECT_ROOT/.build/release/mcp-server-pm" ]; then
        AIAGENTPM_DB_PATH="$INTEGRATION_DB_PATH" "$PROJECT_ROOT/.build/release/mcp-server-pm" setup 2>/dev/null || {
            log_warn "mcp-server-pm setup failed, trying alternative..."
            timeout 2 bash -c "AIAGENTPM_DB_PATH='$INTEGRATION_DB_PATH' '$PROJECT_ROOT/.build/release/mcp-server-pm' serve" 2>/dev/null || true
        }
    else
        log_error "mcp-server-pm not found. Run: swift build -c release"
        exit 1
    fi

    if [ ! -f "$INTEGRATION_DB_PATH" ]; then
        log_error "Failed to create database"
        exit 1
    fi

    log_info "Database created at: $INTEGRATION_DB_PATH"
}

start_services() {
    log_info "Starting integration test services..."

    # Clean up old socket
    rm -f "$MCP_SOCKET_PATH"

    # Clear PID file
    > "$PID_FILE"

    # Start MCP server in daemon mode with Unix socket
    log_info "Starting MCP server on socket: $MCP_SOCKET_PATH"
    AIAGENTPM_DB_PATH="$INTEGRATION_DB_PATH" \
    "$PROJECT_ROOT/.build/release/mcp-server-pm" daemon \
        --socket-path "$MCP_SOCKET_PATH" \
        --foreground &
    MCP_PID=$!
    echo "$MCP_PID" >> "$PID_FILE"
    log_info "MCP server started (PID: $MCP_PID)"

    # Wait for socket to be created
    for i in {1..10}; do
        if [ -S "$MCP_SOCKET_PATH" ]; then
            break
        fi
        sleep 0.5
    done

    if [ ! -S "$MCP_SOCKET_PATH" ]; then
        log_error "MCP server failed to start (socket not created)"
        stop_services
        exit 1
    fi

    # Start REST server
    log_info "Starting REST server on port: $REST_PORT"
    AIAGENTPM_DB_PATH="$INTEGRATION_DB_PATH" \
    AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$PROJECT_ROOT/.build/release/rest-server-pm" &
    REST_PID=$!
    echo "$REST_PID" >> "$PID_FILE"
    log_info "REST server started (PID: $REST_PID)"

    # Wait for REST server
    for i in {1..10}; do
        if curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    if ! curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1; then
        log_warn "REST server health check failed, but continuing..."
    fi

    log_info "Services started successfully"
    echo ""
    log_info "Environment:"
    echo "  Database: $INTEGRATION_DB_PATH"
    echo "  MCP Socket: $MCP_SOCKET_PATH"
    echo "  REST Server: http://localhost:$REST_PORT"
    echo "  PIDs stored in: $PID_FILE"
}

# Parse arguments
case "${1:-}" in
    --stop)
        stop_services
        exit 0
        ;;
    --seed)
        seed_data
        exit 0
        ;;
    *)
        # Full setup
        stop_services
        setup_database
        seed_data
        start_services
        echo ""
        log_info "Integration test environment ready!"
        log_info "To run tests:"
        echo "  cd $WEB_UI_ROOT"
        echo "  AIAGENTPM_WEBSERVER_PORT=$REST_PORT npm run dev"
        echo "  npx playwright test --config=e2e/integration/playwright.integration.config.ts"
        echo ""
        log_info "To stop services: $0 --stop"
        ;;
esac
