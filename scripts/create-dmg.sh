#!/bin/bash
# scripts/create-dmg.sh
# AIAgentPM DMG Creation Script
#
# Creates a distributable DMG file with the app and Applications symlink

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
DMG_DIR="${DIST_DIR}/dmg"
APP_NAME="AIAgentPM"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"

echo -e "${GREEN}=== AIAgentPM DMG Creator ===${NC}"
echo ""

# Step 1: Build Release App
echo -e "${YELLOW}Step 1: Building release app...${NC}"

# Clean dist directory manually
rm -rf "${DIST_DIR}/${APP_NAME}.app"
rm -rf "${DIST_DIR}/${APP_NAME}.app.dSYM"

# Use xcodebuild to create proper app bundle (without clean to avoid directory issues)
xcodebuild -scheme AIAgentPM \
    -configuration Release \
    -derivedDataPath "${PROJECT_ROOT}/.build/DerivedData" \
    -destination 'platform=macOS,arch=arm64' \
    build \
    CONFIGURATION_BUILD_DIR="${DIST_DIR}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES

if [ ! -d "${DIST_DIR}/${APP_NAME}.app" ]; then
    echo -e "${RED}Error: App build failed - ${APP_NAME}.app not found${NC}"
    exit 1
fi

echo -e "${GREEN}App built successfully${NC}"

# Step 2: Prepare DMG staging directory
echo -e "${YELLOW}Step 2: Preparing DMG contents...${NC}"
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"

# Copy app
cp -R "${DIST_DIR}/${APP_NAME}.app" "${DMG_DIR}/"

# Create Applications symlink
ln -s /Applications "${DMG_DIR}/Applications"

# Copy README if exists
if [ -f "${PROJECT_ROOT}/README.md" ]; then
    cp "${PROJECT_ROOT}/README.md" "${DMG_DIR}/README.md"
fi

echo -e "${GREEN}DMG contents prepared${NC}"

# Step 3: Create DMG
echo -e "${YELLOW}Step 3: Creating DMG...${NC}"

# Remove old DMG if exists
rm -f "${DIST_DIR}/${DMG_NAME}"

# Create DMG using hdiutil
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${DIST_DIR}/${DMG_NAME}"

echo -e "${GREEN}DMG created successfully${NC}"

# Step 4: Cleanup
echo -e "${YELLOW}Step 4: Cleaning up...${NC}"
rm -rf "${DMG_DIR}"

# Summary
echo ""
echo -e "${GREEN}=== DMG Creation Complete ===${NC}"
echo ""
echo -e "DMG file: ${BLUE}${DIST_DIR}/${DMG_NAME}${NC}"
echo ""

# Show DMG info
ls -lh "${DIST_DIR}/${DMG_NAME}"

echo ""
echo -e "${YELLOW}Installation instructions:${NC}"
echo "1. Open ${DMG_NAME}"
echo "2. Drag ${APP_NAME}.app to Applications folder"
echo "3. Eject the disk image"
echo "4. Launch ${APP_NAME} from Applications"
echo ""
echo -e "${YELLOW}To test the DMG:${NC}"
echo "  open ${DIST_DIR}/${DMG_NAME}"
