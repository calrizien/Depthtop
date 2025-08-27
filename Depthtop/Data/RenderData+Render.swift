//
//  RenderData+Render.swift
//  Depthtop
//
//  Render loop implementation for window rendering
//

import SwiftUI
import RealityKit
import CompositorServices
import ModelIO
import ARKit
@preconcurrency import MetalKit
import Spatial
import os.log

extension RenderData {
    
    /// The main render loop
    func renderLoop() async {
        logger.info("[RENDERLOOP] Starting main render loop")
        
        // Verify pipeline is ready before starting loop
        guard windowPipeline != nil else {
            logger.error("[RENDERLOOP CRITICAL] Cannot start render loop - pipeline not initialized")
            return
        }
        
        logger.info("[RENDERLOOP] Pipeline verified, entering main loop")
        
        var frameCount = 0
        while renderer.state != .invalidated {
            // Check renderer state before querying frame
            guard self.renderer.state == .paused || self.renderer.state == .running else {
                logger.info("[RENDERLOOP] Renderer not in valid state: \(String(describing: self.renderer.state))")
                break
            }
            
            guard let frame = renderer.queryNextFrame() else { 
                logger.debug("[RENDERLOOP] No frame available, continuing")
                continue 
            }
            
            frameCount += 1
            if frameCount % 60 == 0 {  // Log every 60 frames (about 1 second)
                logger.info("[RENDERLOOP] Frame \(frameCount) rendering...")
            }
            
            // Check again before frame operations
            guard self.renderer.state != .invalidated else {
                logger.info("[RENDERLOOP] Renderer invalidated during frame, exiting cleanly")
                break
            }
            
            frame.startUpdate()
            frame.endUpdate()

            guard let timing = frame.predictTiming() else {
                // If timing prediction fails, we must still end the frame properly
                frame.startSubmission()
                frame.endSubmission()
                continue
            }
            
            // Check if we should continue before sleeping
            guard self.renderer.state != .invalidated else {
                frame.startSubmission()
                frame.endSubmission()
                break
            }
            
            do {
                try await LayerRenderer.Clock().sleep(until: timing.optimalInputTime, tolerance: nil)
            } catch {
                logger.log(level: .error, "Unable to sleep frame loop: \(error)")
                // If sleep is interrupted, check if we should exit
                if self.renderer.state == .invalidated {
                    frame.startSubmission()
                    frame.endSubmission()
                    break
                }
            }
            
            // Final check before submission
            guard self.renderer.state != .invalidated else {
                logger.info("[RENDERLOOP] Renderer invalidated before submission, exiting cleanly")
                break
            }
            
            frame.startSubmission()

            let drawables = {
                #if os(visionOS)
                if #available(visionOS 26.0, *) {
                    return frame.queryDrawables()
                } else {
                    return frame.queryDrawable().map { [$0] } ?? []
                }
                #else
                return frame.queryDrawables()
                #endif
            }()
            
            if drawables.isEmpty { 
                logger.warning("[RENDERLOOP] No drawables available for frame \(frameCount)")
                frame.endSubmission()
                continue 
            }
            
            logger.debug("[RENDERLOOP] Got \(drawables.count) drawable(s) for frame \(frameCount)")
            let commandBuffer = queue.makeCommandBuffer()!
            
            // Render all drawables
            for (index, drawable) in drawables.enumerated() {
                await renderFrame(drawable: drawable, commandBuffer: commandBuffer)
            }
            
            // Commit and end submission only if renderer is still valid
            if self.renderer.state != .invalidated {
                commandBuffer.commit()
                frame.endSubmission()
            } else {
                logger.info("[RENDERLOOP] Renderer invalidated before commit, discarding frame")
                // Don't commit or end submission if renderer is invalidated
            }
        }
        
        logger.info("[RENDERLOOP] Render loop ended - renderer invalidated")
    }
    
    /// Renders a single frame
    private func renderFrame(drawable: LayerRenderer.Drawable, commandBuffer: MTLCommandBuffer) async {
        commandBuffer.label = "Window Render"
        
        // Query and set device anchor for head tracking
        let time = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval
        
        // Check immersion style early to determine anchor requirements
        var immersionStyle = AppModel.ImmersionStylePreference.full
        if let model = _appModel {
            immersionStyle = await MainActor.run { model.selectedImmersionStyle }
        }
        
        // Set device anchor for both macOS (RemoteImmersiveSpace) and visionOS
        // Try to get device anchor - it might not be available immediately
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        if let deviceAnchor = deviceAnchor {
            drawable.deviceAnchor = deviceAnchor
            logger.debug("[RENDER] Device anchor set for frame")
        } else {
            // Device anchor is REQUIRED for mixed/progressive modes
            // Without it, the drawable won't be presented
            logger.warning("[RENDER] No device anchor available yet")
            
            // For mixed/progressive modes, we must skip this frame if no anchor
            if immersionStyle == .mixed || immersionStyle == .progressive {
                logger.warning("[RENDER] Skipping frame - device anchor required for \(immersionStyle.rawValue) mode")
                // Still need to properly end the frame
                drawable.encodePresent(commandBuffer: commandBuffer)
                return
            }
        }
        
        // Get the drawable's render targets
        guard let colorTexture = drawable.colorTextures.first,
              let depthTexture = drawable.depthTextures.first else {
            logger.error("No render textures available")
            drawable.encodePresent(commandBuffer: commandBuffer)
            return
        }
        
        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        
        // Set render target array length for stereoscopic rendering if needed
        if renderer.configuration.layout == .layered {
            renderPassDescriptor.renderTargetArrayLength = drawable.views.count
        }
        
        // We already checked immersion style earlier for anchor requirements
        // Now determine if we need render context
        let requiresRenderContext = (immersionStyle == .progressive || immersionStyle == .mixed)
        logger.info("[RENDER] Immersion mode: \(immersionStyle.rawValue)")
        
        // IMPORTANT: Render context is REQUIRED for progressive and mixed immersion
        // Progressive immersion allows the user to control immersion level with the Digital Crown,
        // Mixed immersion blends virtual content with passthrough environment.
        // Both require special frame composition handled by the render context.
        // The render context will take ownership of the encoder's lifecycle.
        // For full immersion, we use the command buffer directly without a render context.
        let renderContext = requiresRenderContext ? drawable.addRenderContext(commandBuffer: commandBuffer) : nil
        if requiresRenderContext {
            logger.info("[RENDER] Created render context for \(immersionStyle.rawValue) immersion")
        }
        
        // Create render command encoder from the command buffer
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            logger.error("Failed to create render encoder")
            return
        }
        renderEncoder.label = "Window Render Encoder"
        
        // Set up viewports for stereoscopic rendering
        let viewports = drawable.views.map { $0.textureMap.viewport }
        renderEncoder.setViewports(viewports)
        
        // Set up vertex amplification for multiple views if needed
        if drawable.views.count > 1 {
            var viewMappings = (0..<drawable.views.count).map {
                MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0),
                                                  renderTargetArrayIndexOffset: UInt32($0))
            }
            renderEncoder.setVertexAmplificationCount(viewports.count, viewMappings: &viewMappings)
        }
        
        // Set up render state
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setRenderPipelineState(windowPipeline)
        
        // Get view and projection matrices
        let viewMatrices = await getViewMatrices(drawable: drawable)
        let projectionMatrices = await getProjectionMatrices(drawable: drawable)
        
        // Render each captured window
        await renderWindows(
            encoder: renderEncoder,
            drawable: drawable,
            viewMatrices: viewMatrices,
            projectionMatrices: projectionMatrices
        )
        
        // CRITICAL: Encoder lifecycle differs between immersion modes
        // This MUST be handled correctly or Metal will crash with "encoding has ended" errors
        if let renderContext = renderContext {
            // PROGRESSIVE IMMERSION: The render context takes ownership of the encoder
            // and will call endEncoding() internally. We must NOT call it ourselves.
            // The render context manages the encoder's lifecycle for proper frame composition.
            renderContext.endEncoding(commandEncoder: renderEncoder)
        } else {
            // FULL IMMERSION: We directly manage the encoder lifecycle.
            // We must explicitly end encoding before presenting the drawable.
            renderEncoder.endEncoding()
        }
        
        // Encode drawable presentation
        drawable.encodePresent(commandBuffer: commandBuffer)
    }
    
    /// Renders all captured windows
    private func renderWindows(
        encoder: MTLRenderCommandEncoder,
        drawable: LayerRenderer.Drawable,
        viewMatrices: [simd_float4x4],
        projectionMatrices: [simd_float4x4]
    ) async {
        // Get captured windows from the app model
        guard let model = _appModel else { 
            logger.warning("[RENDER] No app model available")
            return 
        }
        let capturedWindows = await MainActor.run { model.capturedWindows }
        
        if capturedWindows.isEmpty {
            logger.warning("[RENDER] No captured windows to render")
            // Render a debug quad to verify pipeline is working
            await renderDebugQuad(encoder: encoder, viewMatrices: viewMatrices, projectionMatrices: projectionMatrices)
            return
        }
        
        logger.info("[RENDER] Rendering \(capturedWindows.count) window(s)")
        
        for (index, capturedWindow) in capturedWindows.enumerated() {
            // Get the window's texture (using the stored Metal texture)
            let texture = await MainActor.run { capturedWindow.texture }
            guard let texture = texture else {
                continue
            }
            
            // Calculate window position in 3D space
            let position = await getWindowPosition(index: index, total: capturedWindows.count)
            // Don't multiply by rootTransform - it already positions at -2.0 Z
            let modelMatrix = matrix4x4_translation(position.x, position.y, position.z)
            
            // Create WindowUniformsArray with data for both eyes
            var uniformsArray = WindowUniformsArray()
            
            // Fill uniforms for each eye
            for eyeIndex in 0..<min(viewMatrices.count, 2) {
                uniformsArray.setUniforms(at: eyeIndex, uniforms: WindowUniforms(
                    modelMatrix: modelMatrix,
                    viewMatrix: viewMatrices[eyeIndex],
                    projectionMatrix: projectionMatrices[eyeIndex]
                ))
            }
            
            // Set hover tracking data
            uniformsArray.windowID = UInt16(index)  // Use index as window ID for now
            uniformsArray.isHovered = 0  // Not hovered for now
            uniformsArray.hoverProgress = 0.0
            
            // Set uniforms for both vertex and fragment shaders (use stride for proper alignment)
            encoder.setVertexBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.stride, index: 0)
            encoder.setFragmentBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.stride, index: 0)
            
            // Set texture
            encoder.setFragmentTexture(texture, index: 0)
            
            // Draw window quad (6 vertices for a quad)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    /// Gets the window position in 3D space based on arrangement
    private func getWindowPosition(index: Int, total: Int) async -> SIMD3<Float> {
        guard let model = _appModel else { return SIMD3<Float>(0, 0, -2.0) }
        let arrangement = await MainActor.run { model.windowArrangement }
        
        // Base distance from viewer - INCREASED for comfortable viewing
        let baseDistance: Float = -5.0  // 5 meters away for comfortable viewing
        
        switch arrangement {
        case .grid:
            // Arrange in a grid
            let cols = 3
            let row = index / cols
            let col = index % cols
            return SIMD3<Float>(
                Float(col - 1) * 2.5,   // X spacing (increased for comfortable viewing)
                Float(1 - row) * 1.8,   // Y spacing (increased)
                baseDistance            // Z (5 meters in front)
            )
            
        case .curved:
            // Arrange in a curve around the user
            let angleStep = Float.pi / 8  // 22.5 degrees
            let angle = Float(index - total/2) * angleStep
            let radius: Float = 5.0  // Increased radius for comfortable viewing
            return SIMD3<Float>(
                sin(angle) * radius,         // X
                0,                          // Y (all at same height)
                baseDistance - cos(angle) * 1.0  // Z (slight curve depth)
            )
            
        case .stack:
            // Stack windows with depth
            return SIMD3<Float>(
                0,                          // X (centered)
                0,                          // Y (centered)
                baseDistance + Float(index) * -0.8  // Z (stacked from -5.0 backwards with more spacing)
            )
        }
    }
    
    /// Updates window transforms for animations
    private func updateWindowTransforms(deltaTime: TimeInterval) async {
        // TODO: Add window animation logic here if needed
        // For now, windows are static
    }
    
    /// Gets view matrices for stereoscopic rendering
    private func getViewMatrices(drawable: LayerRenderer.Drawable) async -> [simd_float4x4] {
        var matrices: [simd_float4x4] = []
        
        // Check if we have a device anchor set on the drawable
        if let deviceAnchor = drawable.deviceAnchor {
            // Use device anchor transform for all views
            for view in drawable.views {
                // Combine the device anchor transform with view-specific transform
                let deviceTransform = deviceAnchor.originFromAnchorTransform
                let viewTransform = view.transform
                // The view matrix is the inverse of the combined transform
                matrices.append((deviceTransform * viewTransform).inverse)
            }
        } else {
            // Fallback: use view transforms directly
            for view in drawable.views {
                matrices.append(view.transform.inverse)
            }
        }
        
        return matrices
    }
    
    /// Gets projection matrices for stereoscopic rendering
    private func getProjectionMatrices(drawable: LayerRenderer.Drawable) async -> [simd_float4x4] {
        return drawable.views.indices.map { viewIndex in
            return drawable.computeProjection(viewIndex: viewIndex)
        }
    }
}

// MARK: - Helper Functions

/// Creates a translation matrix
private func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [x, y, z, 1]
    )
}

extension RenderData {
    /// Renders a debug quad to verify the render pipeline is working
    private func renderDebugQuad(
        encoder: MTLRenderCommandEncoder,
        viewMatrices: [simd_float4x4],
        projectionMatrices: [simd_float4x4]
    ) async {
        logger.info("[DEBUG] Rendering debug quad")
        
        // Position the debug quad in front of the viewer
        let position = SIMD3<Float>(0, 0, -5.0)  // 5 meters in front for comfortable viewing
        let modelMatrix = matrix4x4_translation(position.x, position.y, position.z)
        
        // Create WindowUniformsArray for the debug quad
        var uniformsArray = WindowUniformsArray()
        
        // Fill uniforms for each eye
        for eyeIndex in 0..<min(viewMatrices.count, 2) {
            uniformsArray.setUniforms(at: eyeIndex, uniforms: WindowUniforms(
                modelMatrix: modelMatrix,
                viewMatrix: viewMatrices[eyeIndex],
                projectionMatrix: projectionMatrices[eyeIndex]
            ))
        }
        
        // Set debug data
        uniformsArray.windowID = 9999  // Debug ID
        uniformsArray.isHovered = 0
        uniformsArray.hoverProgress = 0.0
        
        // Set uniforms (use stride for proper alignment)
        encoder.setVertexBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.stride, index: 0)
        encoder.setFragmentBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.stride, index: 0)
        
        // No texture for debug quad - shader will use a solid color
        
        // Draw the debug quad
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        logger.info("[DEBUG] Debug quad drawn")
    }
}


