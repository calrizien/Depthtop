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

## Current Status

- ✅ Project created from Spatial Rendering App template
- ✅ RemoteImmersiveSpace and CompositorServices configured
- ✅ Basic Metal shader pipeline established
- ⏳ ScreenCaptureKit integration needed
- ⏳ Window texture rendering implementation needed
- ⏳ Multi-window management system needed
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