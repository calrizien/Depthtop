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
        
        while renderer.state != .invalidated {
            guard let frame = renderer.queryNextFrame() else { 
                logger.debug("[RENDERLOOP] No frame available, continuing")
                continue 
            }
            frame.startUpdate()
            frame.endUpdate()

            guard let timing = frame.predictTiming() else { continue }
            do {
                try await LayerRenderer.Clock().sleep(until: timing.optimalInputTime, tolerance: nil)
            } catch {
                logger.log(level: .error, "Unable to sleep frame loop: \(error)")
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
                frame.endSubmission()
                continue 
            }
            
            let commandBuffer = queue.makeCommandBuffer()!
            for (index, drawable) in drawables.enumerated() {
                await renderFrame(drawable: drawable, commandBuffer: commandBuffer)
            }
           
            commandBuffer.commit()
            frame.endSubmission()
        }
    }
    
    /// Renders a single frame
    private func renderFrame(drawable: LayerRenderer.Drawable, commandBuffer: MTLCommandBuffer) async {
        commandBuffer.label = "Window Render"
        
        // Get the drawable's render targets
        guard let colorTexture = drawable.colorTextures.first,
              let depthTexture = drawable.depthTextures.first else {
            logger.error("No render textures available")
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
        
        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            logger.error("Failed to create render encoder")
            return
        }
        renderEncoder.label = "Window Render Encoder"
        
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
        
        // End encoding
        renderEncoder.endEncoding()
        
        // Encode drawable presentation
        drawable.encodePresent(commandBuffer: commandBuffer)
        
        // Commit the command buffer
        commandBuffer.commit()
    }
    
    /// Renders all captured windows
    private func renderWindows(
        encoder: MTLRenderCommandEncoder,
        drawable: LayerRenderer.Drawable,
        viewMatrices: [simd_float4x4],
        projectionMatrices: [simd_float4x4]
    ) async {
        // Get captured windows from the app model
        guard let model = _appModel else { return }
        let capturedWindows = await MainActor.run { model.capturedWindows }
        
        for (index, capturedWindow) in capturedWindows.enumerated() {
            // Get the window's texture (using the stored Metal texture)
            let texture = await MainActor.run { capturedWindow.texture }
            guard let texture = texture else {
                continue
            }
            
            // Calculate window position in 3D space
            let position = await getWindowPosition(index: index, total: capturedWindows.count)
            let modelMatrix = matrix4x4_translation(position.x, position.y, position.z) * rootTransform
            
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
            
            // Set uniforms for both vertex and fragment shaders
            encoder.setVertexBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.size, index: 0)
            encoder.setFragmentBytes(&uniformsArray, length: MemoryLayout<WindowUniformsArray>.size, index: 0)
            
            // Set texture
            encoder.setFragmentTexture(texture, index: 0)
            
            // Draw window quad (6 vertices for a quad)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    /// Gets the window position in 3D space based on arrangement
    private func getWindowPosition(index: Int, total: Int) async -> SIMD3<Float> {
        guard let model = _appModel else { return SIMD3<Float>(0, 0, 0) }
        let arrangement = await MainActor.run { model.windowArrangement }
        
        switch arrangement {
        case .grid:
            // Arrange in a grid
            let cols = 3
            let row = index / cols
            let col = index % cols
            return SIMD3<Float>(
                Float(col - 1) * 2.5,  // X spacing
                Float(1 - row) * 2.0,   // Y spacing
                0                       // Z (all at same depth)
            )
            
        case .curved:
            // Arrange in a curve around the user
            let angleStep = Float.pi / 6  // 30 degrees
            let angle = Float(index - total/2) * angleStep
            let radius: Float = 3.0
            return SIMD3<Float>(
                sin(angle) * radius,    // X
                0,                      // Y (all at same height)
                -cos(angle) * radius    // Z
            )
            
        case .stack:
            // Stack windows with depth
            return SIMD3<Float>(
                0,                      // X (centered)
                0,                      // Y (centered)
                Float(index) * -0.5     // Z (stacked in depth)
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
        
        for viewIndex in 0..<drawable.views.count {
            let view = drawable.views[viewIndex]
            
            // Get device anchor if available
            let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
            if let deviceAnchor = deviceAnchor {
                // Use device transform for view matrix
                let transform = deviceAnchor.originFromAnchorTransform
                matrices.append(transform.inverse)
            } else {
                // Use view transform from drawable
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


