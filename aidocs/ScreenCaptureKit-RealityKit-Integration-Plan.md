# ScreenCaptureKit to RealityKit Integration Plan

## Executive Summary

Based on research into Apple's ScreenCaptureKit and RealityKit frameworks for macOS, it is **feasible** to capture a screen window using ScreenCaptureKit and present it inside a RealityKit scene. The solution involves converting CMSampleBuffers from ScreenCaptureKit to Metal textures, then mapping those textures to RealityKit materials using either LowLevelTexture or TextureResource APIs.

## Framework Overview

### ScreenCaptureKit (macOS 12.3+)
- High-performance screen capture framework introduced in macOS 12.3[1]
- Delivers hardware-accelerated capture with GPU-backed buffers[4]
- Provides CMSampleBuffers that are IOSurface-backed for efficient GPU access[22]
- Supports real-time capture at native resolution and frame rates[1]
- Offers advanced filtering by application and window[3]

### RealityKit (Cross-platform)
- Cross-platform 3D framework supporting iOS, macOS, tvOS, and visionOS[8]
- Entity Component System (ECS) architecture[11]
- Metal-based rendering with custom shader support[21]
- Dynamic texture updating capabilities through LowLevelTexture API[26]

## Technical Integration Approach

### Method 1: LowLevelTexture + Metal Compute (Recommended)

**Workflow:**
1. **Capture**: Use ScreenCaptureKit to capture window content as CMSampleBuffer
2. **Convert**: Extract CVImageBuffer from CMSampleBuffer and convert to Metal texture using CVMetalTextureCache[16][19]
3. **Process**: Use Metal compute shader to copy/process texture data into RealityKit's LowLevelTexture[26]
4. **Display**: Apply LowLevelTexture to RealityKit material and update in real-time[46]

**Key Code Components:**

```swift
// ScreenCaptureKit Setup
let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)
try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: queue)

// Metal Texture Conversion
func convertSampleBufferToMetalTexture(_ sampleBuffer: CMSampleBuffer) -> MTLTexture? {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
    
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)
    
    var textureRef: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, textureCache, imageBuffer, nil,
        .bgra8Unorm, width, height, 0, &textureRef
    )
    
    return CVMetalTextureGetTexture(textureRef!)
}

// RealityKit LowLevelTexture Update
func updateRealityKitTexture(metalTexture: MTLTexture) {
    let commandBuffer = metalDevice.makeCommandBuffer()!
    let lowLevelTexture = try! lowLevelTexture.replace(with: commandBuffer)
    
    // Use Metal compute shader to copy texture data
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    encoder.setTexture(metalTexture, index: 0)
    encoder.setTexture(lowLevelTexture, index: 1)
    // ... dispatch compute shader
    
    commandBuffer.commit()
}
```

### Method 2: TextureResource.replace() (Alternative)

**Workflow:**
1. Capture screen content with ScreenCaptureKit
2. Convert CMSampleBuffer to CGImage[18]
3. Use TextureResource.replace(withImage:) for updates[18]

**Limitations:**
- Less efficient due to CPU-GPU round trips
- Potential crashes with frequent updates[18]
- Not suitable for high-frequency updates

## Implementation Plan

### Phase 1: Basic Integration (Week 1-2)
- [ ] Set up ScreenCaptureKit capture pipeline
- [ ] Implement Metal texture cache for CMSampleBuffer conversion
- [ ] Create basic RealityKit scene with textured plane
- [ ] Establish Metal compute pipeline for texture copying

### Phase 2: Real-time Updates (Week 2-3)
- [ ] Implement LowLevelTexture dynamic updating
- [ ] Optimize Metal compute shaders for texture transfer
- [ ] Add frame synchronization to prevent tearing
- [ ] Performance testing and optimization

### Phase 3: Advanced Features (Week 3-4)
- [ ] Window selection UI integration
- [ ] Multiple window capture support
- [ ] Scaling and aspect ratio handling
- [ ] Error handling and edge cases

### Phase 4: Polish & Optimization (Week 4)
- [ ] Performance profiling and optimization
- [ ] Memory management improvements
- [ ] User experience enhancements
- [ ] Documentation and testing

## Technical Considerations

### Performance Optimization
- **GPU Memory Management**: Use IOSurface-backed buffers to minimize memory copies[4][22]
- **Frame Rate Synchronization**: Match capture rate with RealityKit rendering rate
- **Compute Shader Efficiency**: Optimize Metal compute kernels for texture copying[26]

### Memory Management
- Proper CVMetalTexture and Metal buffer lifecycle management
- Avoid memory leaks in high-frequency update scenarios
- Consider texture pooling for better performance

### Platform Requirements
- **Minimum**: macOS 12.3+ (ScreenCaptureKit), macOS 15+ (LowLevelTexture)[26]
- **Recommended**: Apple Silicon Macs for optimal Metal performance
- **Development**: Xcode 16.0+ for LowLevelTexture APIs[26]

## Potential Challenges & Solutions

### Challenge 1: Format Compatibility
**Issue**: ScreenCaptureKit outputs in various pixel formats, RealityKit expects specific formats
**Solution**: Use Metal compute shaders for format conversion when needed

### Challenge 2: Performance Bottlenecks
**Issue**: Real-time texture updates may cause frame drops
**Solution**: 
- Use triple buffering for smooth updates
- Optimize texture dimensions based on use case
- Consider downsampling for better performance

### Challenge 3: Window Tracking
**Issue**: Captured windows may move or resize
**Solution**: 
- Monitor window geometry changes via ScreenCaptureKit callbacks
- Dynamically adjust texture dimensions and UV mapping

## Alternative Approaches Considered

### Option A: CoreVideo → CIImage → TextureResource
- **Pros**: Simpler implementation using existing APIs
- **Cons**: CPU overhead, potential performance issues

### Option B: Direct Metal Integration
- **Pros**: Maximum performance control
- **Cons**: More complex implementation, requires deep Metal knowledge

### Option C: AVCaptureVideoDataOutput-style Pipeline
- **Pros**: Familiar pattern for video processing
- **Cons**: Unnecessary complexity for screen capture use case

## Conclusion

The integration of ScreenCaptureKit with RealityKit is technically sound and achievable using modern Apple frameworks. The LowLevelTexture approach provides the best balance of performance and implementation complexity. The key success factors are:

1. Efficient Metal texture handling and compute shader optimization
2. Proper synchronization between capture and rendering threads  
3. Robust memory management for high-frequency updates
4. Leveraging hardware-accelerated paths throughout the pipeline

With careful implementation following this plan, you can create a performant solution that displays captured macOS windows within RealityKit scenes in real-time.

## References

Key sources from research:
- [1] Meet ScreenCaptureKit - WWDC22
- [4] Take ScreenCaptureKit to the next level - WWDC22  
- [8] Discover RealityKit APIs for iOS, macOS, and visionOS - WWDC24
- [16] MTLTexture from CMSampleBuffer implementation details
- [18] Use Metal Texture in RealityKit - Stack Overflow discussion
- [19] Metal Camera Tutorial - CMSampleBuffer to Metal texture conversion
- [21] Explore advanced rendering with RealityKit 2 - WWDC21
- [22] Meet ScreenCaptureKit - CMSampleBuffer details
- [26] Dynamic RealityKit Meshes with LowLevelMesh - GitHub sample
- [46] RealityKit Morph implementation with LowLevelTexture