#!/bin/bash
# extract-screenshots.sh - UIテストスクリーンショット自動抽出（Xcode 16対応）
#
# Usage:
#   ./extract-screenshots.sh [xcresult_path] [output_dir]
#   ./extract-screenshots.sh                              # 最新のxcresultを自動検出
#   ./extract-screenshots.sh /path/to/Test.xcresult       # 指定パス
#   ./extract-screenshots.sh /path/to/Test.xcresult ./out # 出力先指定

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

XCRESULT_PATH="$1"
OUTPUT_DIR="${2:-/tmp/uitest-screenshots}"

# Auto-detect latest xcresult if not specified
if [ -z "$XCRESULT_PATH" ]; then
    echo -e "${BLUE}Auto-detecting latest xcresult...${NC}"

    # Check DerivedData locations
    LATEST=$(ls -dt ~/Library/Developer/Xcode/DerivedData/VocalisStudio-*/Logs/Test/*.xcresult 2>/dev/null | head -1)

    if [ -z "$LATEST" ]; then
        # Fallback: local DerivedData
        LATEST=$(ls -dt ./DerivedData/VocalisStudio/Logs/Test/*.xcresult 2>/dev/null | head -1)
    fi

    if [ -z "$LATEST" ]; then
        echo -e "${RED}Error: No xcresult found. Run UI tests first or specify path.${NC}"
        echo "Usage: $0 <path_to_xcresult> [output_dir]"
        exit 1
    fi

    XCRESULT_PATH="$LATEST"
    echo -e "${YELLOW}Found: ${XCRESULT_PATH}${NC}"
fi

# Validate path
if [ ! -d "$XCRESULT_PATH" ]; then
    echo -e "${RED}Error: xcresult not found: ${XCRESULT_PATH}${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}Extracting screenshots from:${NC}"
echo "  $XCRESULT_PATH"
echo ""

# Extract all attachments (Xcode 16+)
if xcrun xcresulttool export attachments --path "$XCRESULT_PATH" --output-path "$OUTPUT_DIR" 2>/dev/null; then
    echo ""

    # Count PNGs
    PNG_COUNT=$(ls "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')

    if [ "$PNG_COUNT" -gt 0 ]; then
        echo -e "${GREEN}Extracted ${PNG_COUNT} screenshots to: ${OUTPUT_DIR}${NC}"
        echo ""
        ls -lh "$OUTPUT_DIR"/*.png
    else
        echo -e "${YELLOW}No PNG screenshots found in xcresult.${NC}"
    fi

    # Show manifest if available
    if [ -f "$OUTPUT_DIR/manifest.json" ]; then
        echo ""
        echo -e "${BLUE}Manifest: ${OUTPUT_DIR}/manifest.json${NC}"
    fi
else
    echo -e "${YELLOW}Xcode 16 export failed, trying legacy method...${NC}"

    # Fallback: Legacy SQLite method (Xcode 15)
    DB="$XCRESULT_PATH/database.sqlite3"
    if [ ! -f "$DB" ]; then
        echo -e "${RED}Error: No database found in xcresult${NC}"
        exit 1
    fi

    sqlite3 "$DB" \
      "SELECT xcResultKitPayloadRefId, name FROM Attachments WHERE uniformTypeIdentifier = 'public.png';" 2>/dev/null | \
    while IFS='|' read -r id name; do
        output_file="$OUTPUT_DIR/${name}.png"
        echo "  -> $output_file"
        xcrun xcresulttool export --legacy --type file \
          --path "$XCRESULT_PATH" \
          --id "$id" \
          --output-path "$output_file"
    done

    PNG_COUNT=$(ls "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo -e "${GREEN}Extracted ${PNG_COUNT} screenshots to: ${OUTPUT_DIR}${NC}"
fi
