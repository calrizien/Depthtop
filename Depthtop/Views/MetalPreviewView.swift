//
//  MetalPreviewView.swift
//  Depthtop
//
//  Metal-based preview of captured windows rendered as textured quads
//

import SwiftUI
import MetalKit
import Metal
import simd

struct MetalPreviewView: NSViewRepresentable {
    @Environment(AppModel.self) private var appModel
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        
        context.coordinator.setupMetal(mtkView: mtkView)
        mtkView.delegate = context.coordinator
        
        return mtkView
    }
    
    func updateNSView(_ mtkView: MTKView, context: Context) {
        context.coordinator.appModel = appModel
        
        // Pause/resume rendering based on immersive space state
        if appModel.immersiveSpaceState != .closed {
            mtkView.isPaused = true
            mtkView.enableSetNeedsDisplay = true  // Stop automatic rendering
        } else {
            mtkView.isPaused = false
            mtkView.enableSetNeedsDisplay = false  // Resume automatic rendering
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(appModel: appModel)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var appModel: AppModel
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?
        
        // Vertex buffer for a simple quad
        private var quadVertexBuffer: MTLBuffer?
        private var quadIndexBuffer: MTLBuffer?
        
        // Camera uniforms
        private var uniformBuffer: MTLBuffer?
        private var viewMatrix = matrix_identity_float4x4
        private var projectionMatrix = matrix_identity_float4x4
        
        // Camera control
        private var cameraDistance: Float = 5.0
        private var cameraRotation: Float = 0.0
        
        init(appModel: AppModel) {
            self.appModel = appModel
            super.init()
        }
        
        func setupMetal(mtkView: MTKView) {
            guard let device = mtkView.device else {
                print("Metal device not available")
                return
            }
            
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            
            // Create pipeline state
            do {
                let library = device.makeDefaultLibrary()
                let vertexFunction = library?.makeFunction(name: "metalPreviewVertexShader")
                let fragmentFunction = library?.makeFunction(name: "metalPreviewFragmentShader")
                
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.label = "Metal Preview Pipeline"
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunction
                pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
                pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
                
                // Enable alpha blending
                pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                
                // Configure vertex descriptor
                let vertexDescriptor = MTLVertexDescriptor()
                // Position attribute
                vertexDescriptor.attributes[0].format = .float3
                vertexDescriptor.attributes[0].offset = 0
                vertexDescriptor.attributes[0].bufferIndex = 0
                // TexCoord attribute
                vertexDescriptor.attributes[1].format = .float2
                vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
                vertexDescriptor.attributes[1].bufferIndex = 0
                // Layout
                vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 5
                vertexDescriptor.layouts[0].stepFunction = .perVertex
                
                pipelineDescriptor.vertexDescriptor = vertexDescriptor
                
                self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("Failed to create pipeline state: \(error)")
                return
            }
            
            // Create depth stencil state
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .less
            depthDescriptor.isDepthWriteEnabled = true
            self.depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
            
            // Create quad geometry
            setupQuadGeometry()
            
            // Create uniform buffer
            let uniformSize = MemoryLayout<MetalPreviewUniforms>.size
            uniformBuffer = device.makeBuffer(length: uniformSize, options: .storageModeShared)
            
            // Setup initial camera
            updateCamera(viewSize: mtkView.drawableSize)
        }
        
        private func setupQuadGeometry() {
            guard let device = device else { return }
            
            // Define vertices for a quad (position x, y, z, texCoord u, v)
            let vertices: [Float] = [
                // Position         TexCoord
                -0.5, -0.5, 0.0,   0.0, 1.0,  // Bottom-left
                 0.5, -0.5, 0.0,   1.0, 1.0,  // Bottom-right
                 0.5,  0.5, 0.0,   1.0, 0.0,  // Top-right
                -0.5,  0.5, 0.0,   0.0, 0.0,  // Top-left
            ]
            
            // Define indices for two triangles
            let indices: [UInt16] = [
                0, 1, 2,  // First triangle
                2, 3, 0,  // Second triangle
            ]
            
            quadVertexBuffer = device.makeBuffer(bytes: vertices,
                                                 length: vertices.count * MemoryLayout<Float>.size,
                                                 options: .storageModeShared)
            
            quadIndexBuffer = device.makeBuffer(bytes: indices,
                                               length: indices.count * MemoryLayout<UInt16>.size,
                                               options: .storageModeShared)
        }
        
        private func updateCamera(viewSize: CGSize) {
            guard viewSize.width > 0, viewSize.height > 0 else { return }
            
            // Slowly rotate camera
            cameraRotation += 0.005
            
            // Create view matrix (camera looking at origin from a distance)
            let eye = SIMD3<Float>(
                sin(cameraRotation) * cameraDistance,
                2.0,
                cos(cameraRotation) * cameraDistance
            )
            let center = SIMD3<Float>(0, 0, 0)
            let up = SIMD3<Float>(0, 1, 0)
            viewMatrix = lookAt(eye: eye, center: center, up: up)
            
            // Create projection matrix
            let aspect = Float(viewSize.width / viewSize.height)
            projectionMatrix = perspective(fovyRadians: Float.pi / 4,
                                          aspect: aspect,
                                          nearZ: 0.1,
                                          farZ: 100.0)
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            updateCamera(viewSize: size)
        }
        
        func draw(in view: MTKView) {
            // Stop rendering when immersive space is active
            if appModel.immersiveSpaceState != .closed {
                return
            }
            
            guard let device = device,
                  let commandQueue = commandQueue,
                  let pipelineState = pipelineState,
                  let depthState = depthState,
                  let quadVertexBuffer = quadVertexBuffer,
                  let quadIndexBuffer = quadIndexBuffer,
                  let uniformBuffer = uniformBuffer else {
                return
            }
            
            // Update camera
            updateCamera(viewSize: view.drawableSize)
            
            // Create command buffer
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            // Get current drawable and render pass descriptor
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
            
            // Clear to dark background
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.05, 0.1, 1.0)
            
            // Create render encoder
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthState)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            
            // Render each captured window
            let windows = appModel.capturedWindows
            for (index, window) in windows.enumerated() {
                guard let texture = window.texture else { continue }
                
                // Calculate window position
                let position = layoutWindows(index: index, total: windows.count)
                
                // Update uniforms
                var uniforms = MetalPreviewUniforms()
                uniforms.modelMatrix = matrix_multiply(
                    translation(position.x, position.y, position.z),
                    scale(2.0, 1.5, 1.0)  // Scale the quad to window aspect ratio
                )
                uniforms.viewMatrix = viewMatrix
                uniforms.projectionMatrix = projectionMatrix
                
                uniformBuffer.contents().copyMemory(from: &uniforms,
                                                   byteCount: MemoryLayout<MetalPreviewUniforms>.size)
                
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                renderEncoder.setFragmentTexture(texture, index: 0)
                
                // Draw the quad
                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                   indexCount: 6,
                                                   indexType: .uint16,
                                                   indexBuffer: quadIndexBuffer,
                                                   indexBufferOffset: 0)
            }
            
            // If no windows, draw a placeholder
            if windows.isEmpty {
                var uniforms = MetalPreviewUniforms()
                uniforms.modelMatrix = matrix_identity_float4x4
                uniforms.viewMatrix = viewMatrix
                uniforms.projectionMatrix = projectionMatrix
                
                uniformBuffer.contents().copyMemory(from: &uniforms,
                                                   byteCount: MemoryLayout<MetalPreviewUniforms>.size)
                
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                
                // Draw without texture (will show as gray in shader)
                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                   indexCount: 6,
                                                   indexType: .uint16,
                                                   indexBuffer: quadIndexBuffer,
                                                   indexBufferOffset: 0)
            }
            
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func layoutWindows(index: Int, total: Int) -> SIMD3<Float> {
            guard total > 0 else { return SIMD3<Float>(0, 0, 0) }
            
            // Simple grid layout
            let columns = Int(ceil(sqrt(Double(total))))
            let row = index / columns
            let col = index % columns
            
            let spacing: Float = 2.5
            let x = Float(col) * spacing - Float(columns - 1) * spacing / 2
            let y = -Float(row) * spacing * 0.75 + 1.0
            let z = Float(row) * -0.5  // Slight depth offset
            
            return SIMD3<Float>(x, y, z)
        }
    }
}

// MARK: - Matrix Math Helpers

struct MetalPreviewUniforms {
    var modelMatrix: float4x4 = matrix_identity_float4x4
    var viewMatrix: float4x4 = matrix_identity_float4x4
    var projectionMatrix: float4x4 = matrix_identity_float4x4
}

func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    
    let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
    
    return float4x4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(t.x, t.y, t.z, 1)
    ))
}

func perspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
    let yScale = 1 / tan(fovyRadians * 0.5)
    let xScale = yScale / aspect
    let zScale = farZ / (nearZ - farZ)
    
    return float4x4(columns: (
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zScale, -1),
        SIMD4<Float>(0, 0, nearZ * zScale, 0)
    ))
}

func translation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

func scale(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4(columns: (
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}