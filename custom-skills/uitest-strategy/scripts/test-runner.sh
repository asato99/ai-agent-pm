#!/bin/bash

# VocalisStudio Test Runner Script
# Usage: ./scripts/test-runner.sh [all|ui|unit|critical|smoke] [test-name]
#
# Examples:
#   ./scripts/test-runner.sh ui                    # Run all UI tests
#   ./scripts/test-runner.sh unit                  # Run all Unit tests
#   ./scripts/test-runner.sh all                   # Run all tests
#   ./scripts/test-runner.sh critical              # Run critical UI tests only (~1 min)
#   ./scripts/test-runner.sh smoke                 # Run smoke UI tests (~3 min)
#   ./scripts/test-runner.sh ui PaywallUITests     # Run specific UI test class

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT="VocalisStudio.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro"

# Functions
print_usage() {
    echo -e "${BLUE}VocalisStudio Test Runner${NC}"
    echo ""
    echo "Usage: $0 [all|ui|unit|critical|smoke] [test-name]"
    echo ""
    echo "Test Types:"
    echo "  all      - Run all tests (Unit + UI)"
    echo "  ui       - Run all UI tests"
    echo "  unit     - Run Unit tests only"
    echo "  critical - Run critical UI tests only (~1 min)"
    echo "  smoke    - Run smoke UI tests (~3 min)"
    echo ""
    echo "Examples:"
    echo "  $0 ui                    # Run all UI tests"
    echo "  $0 unit                  # Run all Unit tests"
    echo "  $0 all                   # Run all tests"
    echo "  $0 critical              # Run critical tests (fastest)"
    echo "  $0 smoke                 # Run smoke tests (quick validation)"
    echo "  $0 ui PaywallUITests     # Run specific UI test class"
    echo ""
}

# Critical tests - minimum viable tests for core functionality
# Expected: ~1 minute
run_critical_tests() {
    echo -e "${BLUE}Running CRITICAL tests (core functionality)${NC}"
    echo ""

    local cmd="xcodebuild test \
        -project ${PROJECT} \
        -scheme VocalisStudio-UIOnly \
        -destination '${DESTINATION}' \
        -parallel-testing-enabled NO \
        -allowProvisioningUpdates \
        -only-testing:VocalisStudioUITests/RecordingFlowUITests/testBasicRecordingFlow \
        -only-testing:VocalisStudioUITests/RecordingListUITests/testDeleteRecording \
        -only-testing:VocalisStudioUITests/RecordingLimitUITests/testRecordingLimitAlert_shouldAppear_whenAtLimit \
        -only-testing:VocalisStudioUITests/PaywallUITests/testPurchase_shouldUpdateToPremiumStatus"

    echo -e "${YELLOW}Tests: testBasicRecordingFlow, testDeleteRecording, testRecordingLimitAlert, testPurchase${NC}"
    echo ""

    if eval $cmd; then
        echo ""
        echo -e "${GREEN}✅ CRITICAL Tests PASSED${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ CRITICAL Tests FAILED${NC}"
        return 1
    fi
}

# Smoke tests - quick validation of main features
# Expected: ~3 minutes
run_smoke_tests() {
    echo -e "${BLUE}Running SMOKE tests (main features validation)${NC}"
    echo ""

    local cmd="xcodebuild test \
        -project ${PROJECT} \
        -scheme VocalisStudio-UIOnly \
        -destination '${DESTINATION}' \
        -parallel-testing-enabled NO \
        -allowProvisioningUpdates \
        -only-testing:VocalisStudioUITests/RecordingFlowUITests/testBasicRecordingFlow \
        -only-testing:VocalisStudioUITests/RecordingListUITests/testDeleteRecording \
        -only-testing:VocalisStudioUITests/RecordingLimitUITests/testRecordingLimitAlert_shouldAppear_whenAtLimit \
        -only-testing:VocalisStudioUITests/PaywallUITests/testPurchase_shouldUpdateToPremiumStatus \
        -only-testing:VocalisStudioUITests/NavigationUITests/testMultipleRecordings \
        -only-testing:VocalisStudioUITests/PlaybackUITests/testPlaybackFullCompletion \
        -only-testing:VocalisStudioUITests/AnalysisUITests/testAnalysisViewDisplay"

    echo -e "${YELLOW}Tests: Critical + testMultipleRecordings, testPlaybackFullCompletion, testAnalysisViewDisplay${NC}"
    echo ""

    if eval $cmd; then
        echo ""
        echo -e "${GREEN}✅ SMOKE Tests PASSED${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ SMOKE Tests FAILED${NC}"
        return 1
    fi
}

run_tests() {
    local scheme=$1
    local test_target=$2
    local test_filter=$3

    echo -e "${BLUE}Running tests with scheme: ${scheme}${NC}"

    local cmd="xcodebuild test \
        -project ${PROJECT} \
        -scheme ${scheme} \
        -destination '${DESTINATION}' \
        -parallel-testing-enabled NO \
        -allowProvisioningUpdates"

    # Add test filter if specified
    if [ -n "$test_filter" ]; then
        cmd="${cmd} -only-testing:${test_target}/${test_filter}"
        echo -e "${YELLOW}Filter: ${test_filter}${NC}"
    fi

    echo -e "${YELLOW}Executing: ${cmd}${NC}"
    echo ""

    # Run tests
    if eval $cmd; then
        echo ""
        echo -e "${GREEN}✅ Tests PASSED${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ Tests FAILED${NC}"
        return 1
    fi
}

list_schemes() {
    echo -e "${BLUE}Available schemes:${NC}"
    ls -1 VocalisStudio.xcodeproj/xcshareddata/xcschemes/ | grep "\.xcscheme$" | sed 's/\.xcscheme$//' | while read scheme; do
        echo "  - $scheme"
    done
    echo ""
}

# Main script
main() {
    local test_type=$1
    local test_name=$2

    # Check if we're in the right directory
    if [ ! -d "$PROJECT" ]; then
        echo -e "${RED}Error: VocalisStudio.xcodeproj not found${NC}"
        echo "Please run this script from the VocalisStudio directory"
        exit 1
    fi

    # If no arguments, show usage
    if [ -z "$test_type" ]; then
        print_usage
        list_schemes
        exit 0
    fi

    # Select scheme and target based on test type
    case "$test_type" in
        all)
            run_tests "VocalisStudio-All" "" "$test_name"
            ;;
        ui)
            run_tests "VocalisStudio-UIOnly" "VocalisStudioUITests" "$test_name"
            ;;
        unit)
            run_tests "VocalisStudio-UnitOnly" "VocalisStudioTests" "$test_name"
            ;;
        critical)
            run_critical_tests
            ;;
        smoke)
            run_smoke_tests
            ;;
        help|--help|-h)
            print_usage
            list_schemes
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown test type '${test_type}'${NC}"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
