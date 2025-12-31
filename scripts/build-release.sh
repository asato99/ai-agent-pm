#!/bin/bash
# scripts/build-release.sh
# AIAgentPM Release Build Script
#
# This script builds both the MCP server and the macOS app for distribution.
# Note: Code signing and notarization require manual Xcode configuration.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project paths
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
DIST_DIR="${PROJECT_ROOT}/dist"

echo -e "${GREEN}=== AIAgentPM Release Build ===${NC}"
echo "Project root: ${PROJECT_ROOT}"
echo ""

# Step 1: Clean previous builds
echo -e "${YELLOW}Step 1: Cleaning previous builds...${NC}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# Step 2: Build MCP Server
echo -e "${YELLOW}Step 2: Building MCP Server (release)...${NC}"
cd "${PROJECT_ROOT}"
swift build -c release --product mcp-server-pm

if [ ! -f "${BUILD_DIR}/mcp-server-pm" ]; then
    echo -e "${RED}Error: MCP server build failed${NC}"
    exit 1
fi
echo -e "${GREEN}MCP Server build successful${NC}"

# Step 3: Build App (if using SPM)
echo -e "${YELLOW}Step 3: Building App (release)...${NC}"
swift build -c release --product AIAgentPM 2>/dev/null || {
    echo -e "${YELLOW}Note: App target may require Xcode for full build${NC}"
    echo "For macOS app bundle, use: scripts/build-xcode.sh or Xcode directly"
}

# Step 4: Create distribution structure
echo -e "${YELLOW}Step 4: Creating distribution structure...${NC}"
mkdir -p "${DIST_DIR}/bin"
mkdir -p "${DIST_DIR}/docs"

# Copy MCP server binary
cp "${BUILD_DIR}/mcp-server-pm" "${DIST_DIR}/bin/"
chmod +x "${DIST_DIR}/bin/mcp-server-pm"

# Copy documentation
if [ -f "${PROJECT_ROOT}/README.md" ]; then
    cp "${PROJECT_ROOT}/README.md" "${DIST_DIR}/docs/"
fi

if [ -f "${PROJECT_ROOT}/docs/SETUP_GUIDE.md" ]; then
    cp "${PROJECT_ROOT}/docs/SETUP_GUIDE.md" "${DIST_DIR}/docs/"
fi

# Step 5: Generate Claude Code configuration
echo -e "${YELLOW}Step 5: Generating sample Claude Code configuration...${NC}"
MCP_PATH="${DIST_DIR}/bin/mcp-server-pm"
DB_PATH="\$HOME/Library/Application Support/AIAgentPM/pm.db"

cat > "${DIST_DIR}/claude-code-config.json" << EOF
{
  "mcpServers": {
    "agent-pm": {
      "command": "${MCP_PATH}",
      "args": [
        "--db", "${DB_PATH}"
      ]
    }
  }
}
EOF

echo -e "${GREEN}Sample config created: ${DIST_DIR}/claude-code-config.json${NC}"

# Step 6: Create install script
echo -e "${YELLOW}Step 6: Creating install script...${NC}"
cat > "${DIST_DIR}/install.sh" << 'EOF'
#!/bin/bash
# AIAgentPM Installation Script

set -e

INSTALL_DIR="/usr/local/bin"
APP_SUPPORT_DIR="$HOME/Library/Application Support/AIAgentPM"
CLAUDE_CONFIG_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== AIAgentPM Installation ==="

# Create directories
mkdir -p "${APP_SUPPORT_DIR}"
mkdir -p "${CLAUDE_CONFIG_DIR}"

# Install MCP server
if [ -f "${SCRIPT_DIR}/bin/mcp-server-pm" ]; then
    echo "Installing MCP server to ${INSTALL_DIR}..."
    sudo cp "${SCRIPT_DIR}/bin/mcp-server-pm" "${INSTALL_DIR}/"
    sudo chmod +x "${INSTALL_DIR}/mcp-server-pm"
    echo "MCP server installed successfully"
else
    echo "Error: mcp-server-pm not found in ${SCRIPT_DIR}/bin/"
    exit 1
fi

# Merge Claude Code configuration
CLAUDE_CONFIG="${CLAUDE_CONFIG_DIR}/claude_desktop_config.json"
if [ -f "${CLAUDE_CONFIG}" ]; then
    echo "Merging with existing Claude Code configuration..."
    # Use jq if available, otherwise manual merge required
    if command -v jq &> /dev/null; then
        jq -s '.[0] * .[1]' "${CLAUDE_CONFIG}" "${SCRIPT_DIR}/claude-code-config.json" > "${CLAUDE_CONFIG}.tmp"
        mv "${CLAUDE_CONFIG}.tmp" "${CLAUDE_CONFIG}"
    else
        echo "Warning: jq not installed. Please manually merge claude-code-config.json"
        echo "into ${CLAUDE_CONFIG}"
    fi
else
    echo "Creating new Claude Code configuration..."
    # Update paths in config
    sed "s|\${DIST_DIR}/bin/mcp-server-pm|/usr/local/bin/mcp-server-pm|g" \
        "${SCRIPT_DIR}/claude-code-config.json" > "${CLAUDE_CONFIG}"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Restart Claude Code to load the MCP server"
echo "2. Verify with: claude --mcp-list"
echo "3. Test with: mcp__agent-pm__get_my_profile"
EOF

chmod +x "${DIST_DIR}/install.sh"

# Summary
echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Distribution files created in: ${DIST_DIR}"
echo ""
echo "Contents:"
ls -la "${DIST_DIR}"
echo ""
echo "bin/"
ls -la "${DIST_DIR}/bin"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. For CLI-only distribution: Run ./dist/install.sh"
echo "2. For macOS app bundle: See docs/SETUP_GUIDE.md"
echo "3. For DMG creation: Use Disk Utility or create-dmg tool"
