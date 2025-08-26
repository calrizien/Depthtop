# RemoteImmersiveSpace Implementation Guide

## Overview

RemoteImmersiveSpace is the centerpiece of Depthtop, enabling a macOS application to render spatial windows directly on Apple Vision Pro. This document provides comprehensive technical documentation for implementing and maintaining the RemoteImmersiveSpace feature.

### What is RemoteImmersiveSpace?

RemoteImmersiveSpace is a SwiftUI scene type introduced in macOS 26 (Tahoe) that allows Mac apps to present immersive content on a connected Vision Pro device. It leverages the Mac's computational power to render complex spatial experiences while displaying them in the Vision Pro's immersive environment.

### Key Technologies

- **CompositorContent Protocol**: SwiftUI protocol for custom Metal rendering in spatial contexts
- **CompositorLayer**: The rendering surface that handles Metal draw calls
- **RemoteDeviceIdentifier**: Links the Mac's rendering to Vision Pro's display
- **ARKitSession**: Provides head tracking and spatial awareness from Vision Pro

## Architecture

### Component Hierarchy

```
RemoteImmersiveSpace (Scene)
    └── ImmersiveSpaceContent (CompositorContent)
        └── CompositorLayer
            └── Metal Render Loop (Renderer.swift)
                └── Window Texture Rendering
```

## Technical Implementation

### 1. CompositorContent Protocol

The `CompositorContent` protocol is the foundation for custom rendering in RemoteImmersiveSpace. It's similar to SwiftUI's `View` protocol but designed for frame-by-frame Metal rendering.

```swift
import SwiftUI
import CompositorServices

struct ImmersiveSpaceContent: CompositorContent {
    @Environment(\.remoteDeviceIdentifier) private var remoteDeviceIdentifier
    @State private var appModel: AppModel
    
    var body: some CompositorContent {
        CompositorLayer(configuration: self) { layerRenderer in
            // Metal render loop initialization
            guard let deviceID = remoteDeviceIdentifier else {
                print("⚠️ No Vision Pro connected")
                return
            }
            
            let arSession = ARKitSession(device: deviceID)
            Renderer.startRenderLoop(layerRenderer, appModel: appModel, arSession: arSession)
        }
    }
}
```

#### Key Features of CompositorContent

- **Environment Access**: Can use `@Environment` to access SwiftUI environment values
- **State Management**: Supports `@State` for managing local state
- **SwiftUI Modifiers**: Can use modifiers like `.onChange()`, `.onAppear()`, etc.
- **Thread Safety**: Automatically handles thread boundaries between SwiftUI and Metal

### 2. CompositorLayer Configuration

CompositorLayer is configured through the `CompositorLayerConfiguration` protocol:

```swift
extension ImmersiveSpaceContent: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities, 
                          configuration: inout LayerRenderer.Configuration) {
        let device = MTLCreateSystemDefaultDevice()!
        
        // Configure rendering parameters
        configuration.colorFormat = .bgra8Unorm_srgb
        configuration.depthFormat = .depth32Float_stencil8
        
        // Enable foveation for performance
        if capabilities.supportsFoveation {
            configuration.isFoveationEnabled = true
        }
        
        // Choose layout based on capabilities
        let supportedLayouts = capabilities.supportedLayouts(options: [.foveationEnabled])
        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
    }
}
```

### 3. Window Texture Pipeline

The pipeline for getting window content to the Vision Pro display:

#### Step 1: Capture (ScreenCaptureKit)
```swift
// In WindowCaptureManager
func captureOutput(_ output: SCStreamOutput, 
                  didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    
    // Convert to IOSurface
    let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
    
    // Pass to texture conversion...
}
```

#### Step 2: Convert to MTLTexture
```swift
// Using CVMetalTextureCache for zero-copy conversion
private func createTextureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
    var cvTexture: CVMetalTexture?
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    let status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        textureCache,
        pixelBuffer,
        nil,
        .bgra8Unorm,
        width,
        height,
        0,
        &cvTexture
    )
    
    guard status == kCVReturnSuccess,
          let texture = cvTexture,
          let metalTexture = CVMetalTextureGetTexture(texture) else {
        return nil
    }
    
    return metalTexture
}
```

#### Step 3: Thread-Safe Storage in AppModel
```swift
// WindowRenderData for passing to render thread
struct WindowRenderData {
    let windowID: CGWindowID
    let texture: MTLTexture
    var transform: simd_float4x4  // 3D position/rotation/scale
    let aspectRatio: Float
    let title: String
}

@MainActor
class AppModel: ObservableObject {
    private let renderDataLock = NSLock()
    private var _windowRenderData: [CGWindowID: WindowRenderData] = [:]
    
    // Thread-safe accessor for render thread
    var windowRenderData: [WindowRenderData] {
        renderDataLock.withLock {
            Array(_windowRenderData.values)
        }
    }
    
    // Called from capture thread
    func updateWindowTexture(windowID: CGWindowID, texture: MTLTexture) {
        renderDataLock.withLock {
            if var data = _windowRenderData[windowID] {
                data.texture = texture
                _windowRenderData[windowID] = data
            } else {
                // Create new window data with initial position
                let transform = calculateWindowTransform(index: _windowRenderData.count)
                _windowRenderData[windowID] = WindowRenderData(
                    windowID: windowID,
                    texture: texture,
                    transform: transform,
                    aspectRatio: Float(texture.width) / Float(texture.height),
                    title: "Window \(windowID)"
                )
            }
        }
    }
}
```

### 4. Metal Rendering in Renderer.swift

The Renderer draws windows each frame using the captured textures:

```swift
// In Renderer.swift
func draw(frame: LayerRenderer.Frame, drawable: LayerRenderer.Drawable, 
         targetDrawableRenderContext: LayerRenderer.DrawableRenderContext,
         viewer: LayerRenderer.Clock.Instant.Event.Viewer?) {
    
    // Get window data from AppModel
    let windows = appModel.windowRenderData
    
    // Get view and projection matrices from ARKit
    let viewMatrix = viewer?.viewMatrix ?? matrix_identity_float4x4
    let projectionMatrix = viewer?.projectionMatrix ?? matrix_identity_float4x4
    
    // Set up Metal command encoder
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
        return
    }
    
    // Render each window
    for window in windows {
        // Set per-window uniforms
        var uniforms = WindowUniforms(
            modelMatrix: window.transform,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )
        
        renderEncoder.setVertexBytes(&uniforms, 
                                     length: MemoryLayout<WindowUniforms>.size,
                                     index: 1)
        
        // Bind the window texture
        renderEncoder.setFragmentTexture(window.texture, index: 0)
        
        // Draw the window quad (6 vertices for 2 triangles)
        renderEncoder.drawPrimitives(type: .triangle, 
                                    vertexStart: 0, 
                                    vertexCount: 6)
    }
    
    renderEncoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
}
```

### 5. Shader Implementation

Metal shaders for rendering textured window quads:

```metal
// In Shaders.metal

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct WindowUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

// Vertex shader - transforms window quad to 3D position
vertex VertexOut window_vertex(VertexIn in [[stage_in]],
                               constant WindowUniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Apply Model-View-Projection transformation
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    
    // Pass through texture coordinates
    out.texCoord = in.texCoord;
    
    return out;
}

// Fragment shader - samples window texture
fragment float4 window_fragment(VertexOut in [[stage_in]],
                               texture2d<float> windowTexture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]]) {
    // Sample the window texture
    float4 color = windowTexture.sample(textureSampler, in.texCoord);
    
    // Apply any post-processing (e.g., slight transparency for depth cues)
    color.a *= 0.95;
    
    return color;
}
```

### 6. Spatial Window Positioning

Windows are positioned in 3D space using transformation matrices:

```swift
// Window arrangement algorithms
extension AppModel {
    
    enum WindowArrangement {
        case curved  // Arc around user
        case grid    // Grid layout
        case stack   // Depth layers
    }
    
    func calculateWindowTransform(index: Int) -> simd_float4x4 {
        switch windowArrangement {
        case .curved:
            return curvedArrangement(index: index)
        case .grid:
            return gridArrangement(index: index)
        case .stack:
            return stackArrangement(index: index)
        }
    }
    
    private func curvedArrangement(index: Int) -> simd_float4x4 {
        let angleStep: Float = .pi / 6  // 30 degrees between windows
        let radius: Float = 2.0          // 2 meters from user
        let angle = Float(index - 2) * angleStep  // Center around user
        
        let x = radius * sin(angle)
        let z = -radius * cos(angle)
        let y: Float = 1.5  // Eye level
        
        // Create transform matrix
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(x, y, z, 1.0)
        
        // Rotate to face user
        let rotation = simd_quatf(angle: -angle, axis: [0, 1, 0])
        transform *= simd_float4x4(rotation)
        
        return transform
    }
    
    private func gridArrangement(index: Int) -> simd_float4x4 {
        let columns = 3
        let row = index / columns
        let col = index % columns
        
        let x = Float(col - 1) * 1.2   // 1.2m spacing
        let y = Float(1 - row) * 0.8 + 1.5  // 0.8m vertical spacing
        let z: Float = -2.5  // 2.5m from user
        
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(x, y, z, 1.0)
        return transform
    }
    
    private func stackArrangement(index: Int) -> simd_float4x4 {
        let x: Float = 0
        let y: Float = 1.5
        let z = Float(index) * -0.5 - 2.0  // Stack in depth
        
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(x, y, z, 1.0)
        return transform
    }
}
```

## Implementation Status

### ✅ Completed
- Window capture via ScreenCaptureKit
- IOSurface to MTLTexture conversion  
- CVMetalTextureCache setup
- RealityKit preview on Mac (proof of concept)
- RemoteImmersiveSpace structure with CS_HoverEffect architecture
- ARKit session initialization
- Window rendering in Metal render loop using LayerRenderer
- Thread-safe texture data passing via actor model
- Window positioning algorithms (grid, curved, stack arrangements)
- Shader implementation for textured window quads
- Stereoscopic rendering with vertex amplification
- CompositorLayer integration with proper frame submission

### ⏳ Planned
- User interaction (grab and move windows)
- Window resize and scale
- Opacity and focus management
- Performance optimizations
- Multi-window layout persistence
- Vision Pro device testing

## Debugging Tips

### Common Issues and Solutions

1. **remoteDeviceIdentifier is nil**
   - Ensure Vision Pro is connected via Mac Virtual Display
   - Check Settings > General > Remote Devices on Vision Pro
   - Verify both devices are on same Wi-Fi network
   - Disable VPN if active

2. **Windows not appearing**
   - Check Metal shader compilation (no errors in console)
   - Verify texture format matches (BGRA8Unorm)
   - Ensure window transforms place them in view frustum
   - Add debug spheres to verify rendering pipeline

3. **Performance issues**
   - Enable foveation in CompositorLayer configuration
   - Reduce texture resolution for distant windows
   - Implement LOD (Level of Detail) system
   - Use Metal performance shaders for optimization

### Debug Logging

Add comprehensive logging at each stage:

```swift
// Capture stage
print("📸 Captured window \(windowID): \(width)x\(height)")

// Texture conversion
print("🎨 Created texture: \(texture.width)x\(texture.height)")

// Render stage
print("🖼️ Rendering \(windows.count) windows")

// ARKit tracking
print("📍 Head position: \(devicePose.position)")
```

## References

- [Apple: Building Immersive Apps with SwiftUI (WWDC 2024)](https://developer.apple.com/videos/play/wwdc2024/)
- [CompositorServices Framework Documentation](https://developer.apple.com/documentation/compositorservices)
- [RemoteImmersiveSpace Documentation](https://developer.apple.com/documentation/swiftui/remoteimmersivespace)
- [Metal Best Practices for visionOS](https://developer.apple.com/documentation/metal)

## Next Steps

1. Complete Metal rendering pipeline for windows
2. Test with Vision Pro device
3. Implement user interaction for window manipulation
4. Add visual effects (shadows, transparency)
5. Optimize performance for multiple windows
6. Create user preferences for layout customization

---

*Last Updated: December 2024*
*This document is continuously updated as implementation progresses*