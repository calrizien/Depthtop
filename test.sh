#!/bin/bash

# Depthtop Test Runner
# Uses Xcode 16 best practices for command-line testing

set -e  # Exit on error

echo "🧪 Depthtop Shader Test Runner"
echo "=============================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
TEST_FILTER=""
QUIET_MODE=""
PARALLEL=""
OUTPUT_FORMAT="human"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --diagnostic|-d)
            TEST_FILTER="-only-testing:DepthtopTests/WindowShaderDiagnosticTests"
            echo -e "${BLUE}Running diagnostic tests only...${NC}"
            ;;
        --quiet|-q)
            QUIET_MODE="-quiet"
            OUTPUT_FORMAT="json"
            ;;
        --parallel|-p)
            PARALLEL="-parallel-testing-enabled YES"
            ;;
        --verbose|-v)
            OUTPUT_FORMAT="verbose"
            ;;
        --help|-h)
            echo "Usage: ./test.sh [options]"
            echo ""
            echo "Options:"
            echo "  -d, --diagnostic    Run only diagnostic shader tests"
            echo "  -q, --quiet         Quiet mode with JSON output"
            echo "  -v, --verbose       Show detailed test output"
            echo "  -p, --parallel      Enable parallel test execution"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./test.sh                  # Run all tests"
            echo "  ./test.sh -d               # Run shader diagnostic tests"
            echo "  ./test.sh -d -v            # Diagnostic tests with verbose output"
            echo "  ./test.sh -p               # Run tests in parallel"
            echo ""
            echo "Quick Commands:"
            echo "  make test                  # Run all tests (if Makefile exists)"
            echo "  make test-diagnostic       # Run diagnostic tests only"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Function to format output based on mode
format_output() {
    if [ "$OUTPUT_FORMAT" == "json" ]; then
        # Let JSON through
        cat
    elif [ "$OUTPUT_FORMAT" == "verbose" ]; then
        # Show everything
        cat
    else
        # Human-readable filtering
        grep -E '(Test Suite|Test Case|passed|failed|error|✅|❌|🔍|📝|💡|📊|Executed|Testing started|Testing complete)' || true
    fi
}

# Build tests first
echo -e "${BLUE}📦 Building test target...${NC}"
if xcodebuild build-for-testing \
    -scheme Depthtop \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ./DerivedData \
    $QUIET_MODE; then
    echo -e "${GREEN}✅ Build successful${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🏃 Running tests...${NC}"
echo ""

# Run tests with proper Xcode 16 flags
xcodebuild test-without-building \
    -scheme Depthtop \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ./DerivedData \
    $TEST_FILTER \
    $PARALLEL \
    -resultBundlePath ./TestResults \
    $QUIET_MODE \
    2>&1 | format_output

TEST_RESULT=${PIPESTATUS[0]}

echo ""
echo "=============================="

if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    
    # Show diagnostic hints if running diagnostic tests
    if [[ "$TEST_FILTER" == *"WindowShaderDiagnosticTests"* ]]; then
        echo ""
        echo -e "${YELLOW}📋 Diagnostic Summary:${NC}"
        echo ""
        echo "Based on test results, check the following:"
        echo ""
        echo "1. ${BLUE}Shader Compilation:${NC}"
        echo "   - If passed: Shaders are valid Metal code"
        echo "   - If failed: Check Shaders.metal for syntax errors"
        echo ""
        echo "2. ${BLUE}Pipeline State:${NC}"
        echo "   - If passed: Render pipeline configuration is correct"
        echo "   - If failed: Check vertex/fragment shader compatibility"
        echo ""
        echo "3. ${BLUE}Next Debugging Steps:${NC}"
        echo "   - Temporarily modify windowFragmentShader to output solid red:"
        echo "     ${YELLOW}return float4(1.0, 0.0, 0.0, 1.0);${NC}"
        echo "   - If screen stays black → pipeline not being used"
        echo "   - If screen turns red → texture binding issue"
        echo ""
        echo "Run ${YELLOW}./test.sh -v${NC} for detailed output"
    fi
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo ""
    echo "To see detailed results:"
    echo "  ${YELLOW}./test.sh -v${NC}              # Verbose output"
    echo "  ${YELLOW}./test.sh -d${NC}              # Run diagnostic tests only"
    echo ""
    echo "View test results bundle:"
    echo "  ${YELLOW}open TestResults.xcresult${NC}  # Open in Xcode"
fi

# Clean up derived data if successful (optional)
if [ $TEST_RESULT -eq 0 ] && [ "$QUIET_MODE" != "-quiet" ]; then
    echo ""
    echo -e "${BLUE}Cleaning up derived data...${NC}"
    rm -rf ./DerivedData
fi

exit $TEST_RESULT