# Depthtop Shader Testing Guide

## Quick Start

Run the diagnostic tests to troubleshoot rendering issues:

```bash
# Run shader diagnostic tests
./test.sh -d

# Run with verbose output
./test.sh -d -v

# Run all tests
./test.sh
```

## What These Tests Do

The diagnostic tests help identify where the rendering pipeline is failing:

1. **Shader Compilation Test** - Verifies that `windowVertexShader` and `windowFragmentShader` compile
2. **Pipeline State Test** - Checks if Metal can create a valid render pipeline
3. **Force Color Test** - Tests if the shader pipeline executes at all
4. **Texture Binding Test** - Verifies texture binding and sampling work
5. **Nil Texture Test** - Checks how shaders handle missing textures
6. **BGRA Format Test** - Tests the pixel format from ScreenCaptureKit

## Interpreting Results

### If All Tests Pass ✅

The shaders are working correctly in isolation. The issue is likely:
- Textures not being captured from ScreenCaptureKit
- Render loop not calling the window pipeline
- Wrong pipeline state being used (cube vs window)

### If Shader Compilation Fails ❌

- Check `Shaders.metal` for syntax errors
- Verify `ShaderTypes.h` has correct struct definitions
- Ensure Metal shaders are included in the app bundle

### If Pipeline State Fails ❌

- Vertex and fragment shaders have incompatible signatures
- Check that vertex output matches fragment input
- Verify buffer indices match between Swift and Metal

## Debugging Steps

### 1. Test if Shaders Are Running

Edit `Shaders.metal` and change `windowFragmentShader`:

```metal
fragment float4 windowFragmentShader(ColorInOut in [[stage_in]],
                                     texture2d<float> windowTexture [[ texture(TextureIndexColor) ]]) {
    // Force output red to test if shader runs
    return float4(1.0, 0.0, 0.0, 1.0);
}
```

- **Screen stays BLACK** → Pipeline not being used
- **Screen turns RED** → Shaders work, texture binding is the issue

### 2. Check Window Capture

Look for these console messages when running the app:

```
Starting capture for window: Safari - ID: 1234
Successfully created texture for window Safari - size: 1920x1080
StreamOutput: Received frame 60 for window: Safari
```

No messages = ScreenCaptureKit isn't capturing

### 3. Verify Render Loop

Add to `Renderer.renderLoop()`:

```swift
print("Render loop frame: \(frameCount)")
frameCount += 1
```

Should print 90 times per second for Vision Pro

## Test Command Options

```bash
./test.sh [options]

Options:
  -d, --diagnostic    Run only diagnostic shader tests
  -q, --quiet         Quiet mode with JSON output  
  -v, --verbose       Show detailed test output
  -p, --parallel      Enable parallel test execution
  -h, --help          Show this help message
```

## Test Files

- `DepthtopTests/ShaderTestBase.swift` - Base test infrastructure
- `DepthtopTests/WindowShaderDiagnosticTests.swift` - Diagnostic tests
- `test.sh` - Test runner script

## Adding New Tests

Create new test files in `DepthtopTests/` directory:

```swift
class MyNewTests: ShaderTestBase {
    func testSomething() throws {
        // Your test code
    }
}
```

## CI/CD Integration

For GitHub Actions or Xcode Cloud:

```yaml
- name: Run Tests
  run: |
    xcodebuild test \
      -scheme Depthtop \
      -destination 'platform=macOS,arch=arm64' \
      -resultBundlePath TestResults.xcresult
```

## Troubleshooting

### Tests Won't Compile

1. Ensure test target is added to the Xcode project
2. Check that `@testable import Depthtop` works
3. Verify Metal device is available on test machine

### Tests Pass But App Doesn't Work

This means shaders work in isolation but fail in the app context:
1. Check actor isolation between capture and render
2. Verify textures are passed correctly across actor boundaries
3. Ensure correct pipeline state is selected during rendering

### Performance Issues

If tests are slow:
- Use `-p` flag for parallel execution
- Run specific tests with `-d` for diagnostics only
- Check if Metal API Validation is enabled (slows tests)

## Next Steps

Once diagnostic tests pass:
1. Fix any issues identified by the tests
2. Add integration tests for the full capture → render pipeline
3. Add performance tests to ensure 90Hz target
4. Set up continuous integration