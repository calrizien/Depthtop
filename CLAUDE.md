# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Depthtop - Spatial Window Rendering for Vision Pro

A macOS application that captures individual desktop windows and renders them as spatial content in Apple Vision Pro, providing an alternative to the single-screen Mac Virtual Display by allowing users to position windows independently in 3D space.

## Current Architecture

Built using the **Spatial Rendering App** template in Xcode 26 beta with:
- **macOS Tahoe 26.0** deployment target
- **RemoteImmersiveSpace** for Mac-to-Vision Pro rendering
- **CompositorServices** for stereoscopic frame streaming
- **ARKit** for head tracking data from Vision Pro
- **Metal** for GPU-accelerated rendering

## Build Commands

```bash
# Open project in Xcode
open Depthtop.xcodeproj

# Build from command line
xcodebuild -scheme Depthtop -configuration Debug

# Clean build
xcodebuild clean -scheme Depthtop

# Run tests
xcodebuild test -scheme Depthtop -destination 'platform=macOS'
```

## Accessing Xcode Console Output from Terminal

To monitor console output outside of Xcode (useful for debugging when Xcode console is problematic):

### Method 1: Run the built app directly
```bash
# After building in Xcode or via xcodebuild, run the executable directly:
./DerivedData/Depthtop/Build/Products/Debug/Depthtop.app/Contents/MacOS/Depthtop

# Or if you know the full path:
/Users/brandonwinston/Library/Developer/Xcode/DerivedData/Depthtop-*/Build/Products/Debug/Depthtop.app/Contents/MacOS/Depthtop
```

### Method 2: Stream logs for the running app
```bash
# Monitor logs from the running Depthtop process
log stream --predicate 'process == "Depthtop"' --level debug

# Or filter for specific subsystems
log stream --predicate 'subsystem == "com.yourcompany.Depthtop"'
```

### Method 3: Build and run in one command
```bash
# Build and immediately run with console output
xcodebuild -scheme Depthtop -configuration Debug && \
./DerivedData/Depthtop/Build/Products/Debug/Depthtop.app/Contents/MacOS/Depthtop
```

This approach is particularly useful when:
- Xcode's console is unresponsive or overwhelming
- You need to pipe output to other tools (grep, tee, etc.)
- You want to save logs to a file: `./path/to/Depthtop 2>&1 | tee debug.log`

## Implementation Plan

### Phase 1: Window Capture (Current Focus)

**Goal**: Capture individual application windows from the Mac desktop

1. **ScreenCaptureKit Integration**
   - Query `SCShareableContent` for available windows
   - Filter to exclude our own app's windows
   - Allow user to select specific windows to capture
   - Create `SCStream` for each selected window

2. **Texture Pipeline**
   - Convert captured `CMSampleBuffer` to `CVPixelBuffer`
   - Create `CVMetalTextureCache` for efficient texture conversion
   - Generate `MTLTexture` from pixel buffers for Metal rendering

3. **Window Management**
   - Track multiple window captures simultaneously
   - Handle window lifecycle (minimize, close, resize)
   - Update capture configuration when windows change

### Phase 2: Spatial Rendering

**Goal**: Display captured windows as floating panels in Vision Pro's immersive space

1. **Geometry Setup**
   - Create textured quads for each window
   - Size quads to match window aspect ratios
   - Position windows at different Z-depths

2. **Stereoscopic Rendering**
   - Use Metal's vertex amplification (`[[amplification_id]]`)
   - Generate left/right eye views with IPD separation
   - Apply asymmetric frustum projection matrices
   - Set convergence plane at comfortable viewing distance

3. **Head Tracking Integration**
   - Query `WorldTrackingProvider` for `DeviceAnchor`
   - Use predicted poses to minimize latency
   - Update view matrices based on head position/rotation

4. **Render Loop**
   - Call `queryNextFrame()` on `LayerRenderer`
   - Render each window twice (once per eye)
   - Submit frames to CompositorServices
   - Let visionOS handle late-stage reprojection

### Phase 3: 3D Enhancement Experiments (Future)

**Goal**: Add depth and dimensionality to 2D window content

1. **Depth Layering**
   - Parse window content to identify UI layers
   - Separate foreground elements (buttons, text) from backgrounds
   - Render at slightly different depths for parallax

2. **Stereoscopic Effects**
   - Apply subtle horizontal offsets based on content depth
   - Implement chromatic aberration for depth cues
   - Add drop shadows that respect 3D positioning

3. **Interactive Positioning**
   - Allow users to grab and reposition windows in 3D
   - Implement smooth animations for window movements
   - Add snap-to-grid functionality for organization

## Key Files and Components

### Core Application Structure
- `DepthtopApp.swift`: Main app entry with `RemoteImmersiveSpace` scene
- `ImmersiveSpaceContent`: CompositorContent implementation
- `AppModel.swift`: State management for window captures and rendering
- `ContentView.swift`: Mac UI with window selection controls
- `ToggleImmersiveSpaceButton`: UI control to activate spatial rendering

### Rendering Pipeline
- `Renderer.swift`: Main render loop implementation
  - Manages `LayerRenderer` and `ARKitSession`
  - Handles frame timing and submission
  - Coordinates window texture updates
- `Shaders.metal`: Vertex and fragment shaders
  - Vertex amplification for stereo rendering
  - Texture sampling for window content
- `ShaderTypes.h`: Shared types between Swift and Metal

### Window Capture (To Be Implemented)
- `WindowCaptureManager.swift`: ScreenCaptureKit wrapper
  - Window enumeration and selection
  - Stream configuration and lifecycle
  - Texture conversion pipeline
- `CapturedWindow.swift`: Model for captured window data
  - Window metadata (title, app, size)
  - Current texture and update timestamp
  - Position in 3D space

## Technical Constraints & Considerations

1. **Performance**
   - Multiple window captures can be CPU/GPU intensive
   - Use efficient texture formats (BGRA8Unorm recommended)
   - Implement LOD for distant windows
   - Consider frame rate limiting for background windows

2. **Memory Management**
   - Window textures can consume significant memory
   - Implement texture pooling/recycling
   - Release textures for hidden windows
   - Monitor memory pressure notifications

3. **User Experience**
   - Maintain stable 90Hz rendering for comfort
   - Implement smooth window transitions
   - Provide clear visual feedback for window selection
   - Respect user's IPD settings

## RemoteImmersiveSpace - Core Feature Documentation

The RemoteImmersiveSpace is the centerpiece of Depthtop, enabling Mac-rendered content to appear as spatial windows in Vision Pro.

📖 **See [REMOTE_IMMERSIVE_SPACE_IMPLEMENTATION.md](./REMOTE_IMMERSIVE_SPACE_IMPLEMENTATION.md) for complete technical documentation**

### Quick Reference
- Uses CompositorContent protocol with CompositorLayer for Metal rendering
- Captures windows via ScreenCaptureKit and renders them as spatial panels
- Thread-safe texture pipeline: Capture → IOSurface → MTLTexture → GPU
- Positions windows in 3D space using Model-View-Projection matrices
- Leverages ARKit for head tracking and spatial awareness

### Current Implementation Status
- Window capture and texture conversion: ✅ Working
- RealityKit preview on Mac: ✅ Working  
- CVMetalTextureCache optimization: ✅ Implemented
- RemoteImmersiveSpace structure: ✅ Created
- CompositorContent conformance: 🚧 In Progress
- Metal window rendering pipeline: 🚧 Being enhanced
- Vision Pro streaming: ⏳ Ready for testing
- User interaction: ⏳ Planned

## Current Status

- ✅ Project created from Spatial Rendering App template
- ✅ RemoteImmersiveSpace and CompositorServices configured
- ✅ CS_HoverEffect rendering architecture integrated
- ✅ Metal shader pipeline established with stereoscopic support
- ✅ ScreenCaptureKit integration completed
- ✅ Window texture conversion working (proven in RealityKit preview)
- ✅ Window rendering in Metal render loop using LayerRenderer
- ✅ Thread-safe texture data passing via actor model
- ✅ Multi-window spatial management system (grid, curved, stack)
- ⏳ Vision Pro device testing pending
- ⏳ 3D enhancement experiments pending

## Testing Approach

1. **Unit Tests**: Window capture logic, texture conversion
2. **Integration Tests**: End-to-end capture to render pipeline
3. **Performance Tests**: Frame timing, memory usage
4. **User Tests**: Comfort, usability in Vision Pro

## References

- [Apple's Spatial Rendering Documentation](https://developer.apple.com/documentation/compositorservices)
- [ScreenCaptureKit Guide](https://developer.apple.com/documentation/screencapturekit)
- [Metal Spatial Rendering Sample](https://github.com/metal-by-example/metal-spatial-rendering)
- Technical Report: "Stereoscopic Text Overlays for Mac Virtual Display"

## Recent Major Changes (August 26, 2024)

### CS_HoverEffect Integration
- Completely replaced rendering architecture with CS_HoverEffect's proven LayerRenderer system
- Added interactive hover effects for windows (scale, glow, edge highlighting)
- Implemented MSAA-based hover tracking with TileResolvePipeline
- Full spatial event handling for gaze-based interaction
- See `aidocs/CS_HOVEREFFECT_INTEGRATION_SUMMARY.md` for complete details

### Key Features Now Active
- **Hover Effects**: Windows respond to gaze with visual feedback
- **Tap Detection**: Ready for window interaction implementation
- **Debug Mode**: Set `AppModel.debugColors = true` to visualize hover areas
- **Window Arrangements**: Grid, curved, and stack layouts functional

## Critical Implementation Rules (MUST FOLLOW)

### 1. CompositorServices Command Buffer Order
**CRITICAL**: In `LayerRenderer.Drawable` rendering, the order MUST be:
1. `renderEncoder.endEncoding()` - End all encoding first
2. `drawableRenderContext.endEncoding(commandEncoder:)` - End drawable context
3. `drawable.encodePresent()` - Encode presentation BEFORE commit
4. `commandQueue.commit([commandBuffer])` - Commit is LAST

**Error if violated**: "BUG IN CLIENT: cannot present drawable: command buffer used by render context end encoding must be last commit command buffer to the command queue"

### 2. Metal Residency Set Scoping
When using `MTLResidencySet` with simulator conditionals:
- Declare variable OUTSIDE the `#if !targetEnvironment(simulator)` block as optional
- Only populate inside the conditional block
- Use optional chaining when accessing

```swift
var residencySet: MTLResidencySet?
#if !targetEnvironment(simulator)
residencySet = self.residencySets[uniformBufferIndex]
// ... populate
#endif
if let residencySet = residencySet {
    commandBuffer.useResidencySet(residencySet)
}
```

### 3. Metal Binary Archive Requirement
Always compile Metal shaders to a binary archive (`default-binaryarchive.metallib`) to avoid runtime compilation warnings:
- Use `xcrun metal -c` to compile to AIR
- Use `xcrun metallib` to create .metallib
- Add to bundle resources in Xcode
- Use `-std=metal3.0` for visionOS compatibility (not `-std=macos-metal3.0`)

### 4. RemoteImmersiveSpace Connection Handling
Always check for nil `remoteDeviceIdentifier` before using:
- Guard against nil device ID
- Provide user feedback when Vision Pro isn't connected
- Close immersive space gracefully on connection failure

### 5. Actor Isolation for Texture Passing
When passing textures between MainActor and renderer actor:
- Create immutable data structures (`WindowRenderData`) to pass across boundaries
- Don't block the render loop waiting for texture updates
- Continue rendering with available data

### 6. Window Capture Texture Lifecycle
- Keep strong references to `SCStreamOutput` objects to prevent deallocation
- Update textures asynchronously to avoid blocking capture
- Use `CVMetalTextureCache` for efficient texture conversion
- we are working with compiled metal shaders, so when rebuilding the app, run a clean first when altering them so old compiled versions do not stick around.