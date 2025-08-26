//
//  PipelineConfigurationTests.swift
//  DepthtopTests
//
//  Tests for Metal pipeline configuration issues
//

import XCTest
import Metal
import CompositorServices
@testable import Depthtop

class PipelineConfigurationTests: XCTestCase {
    
    var device: MTLDevice!
    var library: MTLLibrary!
    
    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
        library = device.makeDefaultLibrary()
        XCTAssertNotNil(device, "Failed to create Metal device")
        XCTAssertNotNil(library, "Failed to load Metal library")
    }
    
    func testWindowPipelineConfiguration() throws {
        print("\n🔍 Testing Window Pipeline Configuration for LayerRenderer...")
        
        // Get the shader functions
        guard let vertexFunction = library.makeFunction(name: "windowVertex") else {
            XCTFail("❌ windowVertex function not found in Metal library")
            return
        }
        
        guard let fragmentFunction = library.makeFunction(name: "windowFragment") else {
            XCTFail("❌ windowFragment function not found in Metal library")
            return
        }
        
        print("✅ Found shader functions: windowVertex and windowFragment")
        
        // Create vertex descriptor matching RenderData.swift
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
        
        // Test different pixel formats that LayerRenderer might use
        let pixelFormats: [(color: MTLPixelFormat, depth: MTLPixelFormat, name: String)] = [
            (.bgra8Unorm_srgb, .depth32Float, "Standard sRGB"),
            (.rgba16Float, .depth32Float, "HDR Float16"),
            (.bgr10a2Unorm, .depth32Float, "10-bit HDR"),
            (.rgba8Unorm_srgb, .depth32Float, "RGBA sRGB")
        ]
        
        for format in pixelFormats {
            print("\n📝 Testing with \(format.name) - Color: \(format.color), Depth: \(format.depth)")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "Window Pipeline Test - \(format.name)"
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.colorAttachments[0].pixelFormat = format.color
            pipelineDescriptor.depthAttachmentPixelFormat = format.depth
            
            // Test without vertex amplification first
            do {
                _ = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("  ✅ Pipeline created successfully WITHOUT vertex amplification")
            } catch {
                print("  ❌ Pipeline failed WITHOUT vertex amplification: \(error)")
            }
            
            // Test with vertex amplification (stereoscopic rendering)
            pipelineDescriptor.maxVertexAmplificationCount = 2
            do {
                _ = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("  ✅ Pipeline created successfully WITH vertex amplification (stereo)")
            } catch {
                print("  ❌ Pipeline failed WITH vertex amplification: \(error)")
                print("     This might be the issue when layout == .layered")
            }
        }
    }
    
    func testSecondColorAttachment() throws {
        print("\n🔍 Testing Pipeline with Tracking Area Attachment...")
        
        guard let vertexFunction = library.makeFunction(name: "windowVertex"),
              let fragmentFunction = library.makeFunction(name: "windowFragment") else {
            XCTFail("Shader functions not found")
            return
        }
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Window Pipeline with Tracking"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // Main color attachment
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        
        // Tracking area attachment (for hover effects) - this might be causing issues
        pipelineDescriptor.colorAttachments[1].pixelFormat = .r16Uint
        
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.maxVertexAmplificationCount = 2
        
        do {
            _ = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("✅ Pipeline with tracking attachment created successfully")
        } catch {
            print("❌ Pipeline with tracking attachment FAILED: \(error)")
            print("   This could be the crash cause - fragment shader may not output to color[1]")
        }
    }
    
    func testShaderOutputCompatibility() throws {
        print("\n🔍 Analyzing Shader Output Compatibility...")
        
        // Check if FragmentOut struct matches pipeline expectations
        print("\n📝 Fragment shader outputs (from FragmentOut struct):")
        print("   - color [[color(0)]] -> float4")
        print("   - hoverIndex [[color(1)]] -> uint16_t")
        print("\n⚠️ If pipeline expects color attachment 1 but shader doesn't write to it,")
        print("   this will cause the crash you're seeing!")
    }
    
    func testLayerRendererSpecificConfig() throws {
        print("\n🔍 Testing LayerRenderer-specific Configuration...")
        
        // LayerRenderer.Configuration typically uses these formats
        let compositorFormats: [(color: MTLPixelFormat, depth: MTLPixelFormat)] = [
            (.rgba16Float, .depth32Float),  // Most common for compositor
            (.bgr10a2Unorm, .depth32Float), // HDR format
        ]
        
        guard let vertexFunction = library.makeFunction(name: "windowVertex"),
              let fragmentFunction = library.makeFunction(name: "windowFragment") else {
            XCTFail("Shader functions not found")
            return
        }
        
        for format in compositorFormats {
            print("\n📝 Testing compositor format - Color: \(format.color)")
            
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            
            vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.colorAttachments[0].pixelFormat = format.color
            
            // This is likely the problem - tracking area format
            if format.color == .rgba16Float {
                // CompositorServices might expect a tracking format
                pipelineDescriptor.colorAttachments[1].pixelFormat = .r16Uint
            }
            
            pipelineDescriptor.depthAttachmentPixelFormat = format.depth
            pipelineDescriptor.maxVertexAmplificationCount = 2  // Stereo
            
            do {
                _ = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("  ✅ Compositor pipeline created successfully")
            } catch {
                print("  ❌ Compositor pipeline FAILED: \(error)")
                print("     Error details: \(error.localizedDescription)")
            }
        }
    }
    
    func testDiagnoseSolution() {
        print("\n" + String(repeating: "=", count: 60))
        print("💡 DIAGNOSIS AND SOLUTION")
        print(String(repeating: "=", count: 60))
        
        print("\n🔍 Based on the crash and tests, the likely issue is:")
        print("\n1. The fragment shader outputs to TWO color attachments:")
        print("   - color [[color(0)]] for the main output")
        print("   - hoverIndex [[color(1)]] for hover tracking")
        
        print("\n2. But the pipeline descriptor might not configure color[1]")
        print("   when renderer.configuration doesn't have trackingAreasFormat")
        
        print("\n🛠 SOLUTION:")
        print("In RenderData.swift setUpShaderPipeline(), add:")
        print("""
        
        // Only add second color attachment if tracking is available
        if #available(visionOS 26.0, *) {
            if let trackingFormat = renderer.configuration.trackingAreasFormat {
                pipelineDescriptor.colorAttachments[1].pixelFormat = trackingFormat
            }
        }
        """)
        
        print("\nOR modify the fragment shader to conditionally output hoverIndex")
        print("only when hover tracking is enabled.")
        print(String(repeating: "=", count: 60))
    }
}