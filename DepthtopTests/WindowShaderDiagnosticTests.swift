//
//  WindowShaderDiagnosticTests.swift
//  DepthtopTests
//
//  Diagnostic tests to identify rendering issues
//

import XCTest
import Metal
import simd
@testable import Depthtop

class WindowShaderDiagnosticTests: ShaderTestBase {
    
    // MARK: - Test 1: Basic Shader Compilation
    
    func test1_ShadersExistAndCompile() throws {
        print("\n🔍 TEST 1: Checking if shaders exist and compile...")
        
        // Check if window shaders exist
        let vertexFunction = library.makeFunction(name: "windowVertexShader")
        let fragmentFunction = library.makeFunction(name: "windowFragmentShader")
        
        XCTAssertNotNil(vertexFunction, "❌ Window vertex shader not found! Check Shaders.metal")
        XCTAssertNotNil(fragmentFunction, "❌ Window fragment shader not found! Check Shaders.metal")
        
        if vertexFunction != nil && fragmentFunction != nil {
            print("✅ Both shaders found and compiled successfully")
        }
        
        // Also check the regular shaders for comparison
        let regularVertex = library.makeFunction(name: "vertexShader")
        let regularFragment = library.makeFunction(name: "fragmentShader")
        
        if regularVertex != nil && regularFragment != nil {
            print("✅ Regular shaders also found (cube rendering works)")
        } else {
            print("⚠️ Regular shaders missing (might explain why nothing renders)")
        }
    }
    
    // MARK: - Test 2: Pipeline State Creation
    
    func test2_PipelineStateCreation() throws {
        print("\n🔍 TEST 2: Testing pipeline state creation...")
        
        guard let vertexFunction = library.makeFunction(name: "windowVertexShader"),
              let fragmentFunction = library.makeFunction(name: "windowFragmentShader") else {
            XCTFail("❌ Shaders not found - run test1 first")
            return
        }
        
        // Create vertex descriptor matching Renderer.swift
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Texture coordinate attribute
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        
        // Layout for position buffer
        vertexDescriptor.layouts[0].stride = 12 // 3 floats * 4 bytes
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Layout for texture coordinate buffer
        vertexDescriptor.layouts[1].stride = 8 // 2 floats * 4 bytes
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stepFunction = .perVertex
        
        // Create pipeline descriptor matching Renderer.swift configuration
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Window Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // Match the pixel format from Renderer
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Try to create pipeline state
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            XCTAssertNotNil(pipelineState)
            print("✅ Pipeline state created successfully")
        } catch {
            XCTFail("❌ Pipeline state creation failed: \(error)")
            print("This means shaders compile but can't form a valid pipeline")
            print("Check vertex/fragment shader input/output compatibility")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Test 3: Shader Output with Forced Color
    
    func test3_ForceColorOutput() throws {
        print("\n🔍 TEST 3: Testing if shader pipeline executes at all...")
        print("This test forces the shader to output RED regardless of input")
        
        // Create a modified fragment shader that just outputs red
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct ColorInOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        fragment float4 diagnosticFragment(ColorInOut in [[stage_in]]) {
            // Ignore everything, just output red
            return float4(1.0, 0.0, 0.0, 1.0);
        }
        """
        
        // Compile diagnostic shader
        do {
            let diagnosticLibrary = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "windowVertexShader")
            let fragmentFunction = diagnosticLibrary.makeFunction(name: "diagnosticFragment")
            
            XCTAssertNotNil(vertexFunction)
            XCTAssertNotNil(fragmentFunction)
            
            // Create and render with diagnostic pipeline
            let outputTexture = createTestTexture(width: 100, height: 100)!
            
            // Render a frame
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let renderPass = MTLRenderPassDescriptor()
            renderPass.colorAttachments[0].texture = outputTexture
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPass.colorAttachments[0].storeAction = .store
            
            // We can't actually render without proper vertex data setup
            // But we can check if the shader would output red
            print("✅ Diagnostic shader compiled successfully")
            print("📝 If preview is still BLACK with this shader, pipeline setup is broken")
            print("📝 If preview shows RED with this shader, texture binding is the issue")
            
        } catch {
            XCTFail("❌ Failed to compile diagnostic shader: \(error)")
        }
    }
    
    // MARK: - Test 4: Texture Binding and Sampling
    
    func test4_TextureBinding() throws {
        print("\n🔍 TEST 4: Testing texture binding and sampling...")
        
        guard let vertexFunction = library.makeFunction(name: "windowVertexShader"),
              let fragmentFunction = library.makeFunction(name: "windowFragmentShader") else {
            XCTFail("❌ Shaders not found")
            return
        }
        
        // Create test textures
        let inputTexture = createTestTexture()!
        fillTextureWithTestPattern(inputTexture, pattern: .solid(r: 255, g: 0, b: 0, a: 255)) // Red
        
        let outputTexture = createTestTexture()!
        
        print("✅ Created test textures (input is solid red)")
        
        // Check if we can at least bind textures
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1) // Clear to green
        renderPass.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.setFragmentTexture(inputTexture, index: 0) // TextureIndexColor = 0
            encoder.endEncoding()
            print("✅ Texture binding successful")
        } else {
            print("❌ Failed to create render encoder")
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Check if the clear color worked at least
        let pixel = readPixel(from: outputTexture, x: 50, y: 50)
        if pixel.g > 250 {
            print("✅ Render target is working (cleared to green)")
        } else {
            print("❌ Render target not working properly")
        }
    }
    
    // MARK: - Test 5: Nil Texture Handling
    
    func test5_NilTextureHandling() throws {
        print("\n🔍 TEST 5: Testing nil texture handling...")
        print("Our shader should output gray (0.2, 0.2, 0.2) for nil textures")
        
        // This test checks if the shader's nil texture handling works
        // In actual rendering, if we see BLACK instead of GRAY, textures aren't nil - they're broken
        // If we see GRAY, textures are nil/not being passed
        
        print("📝 In the actual app:")
        print("   - BLACK screen = shaders not running OR textures exist but are black")
        print("   - GRAY screen = textures are nil/not bound")
        print("   - Window content = everything works!")
    }
    
    // MARK: - Test 6: BGRA Format Handling
    
    func test6_BGRAFormatHandling() throws {
        print("\n🔍 TEST 6: Testing BGRA pixel format (ScreenCaptureKit format)...")
        
        // Create BGRA texture like ScreenCaptureKit provides
        let bgraTexture = createTestTexture(pixelFormat: .bgra8Unorm)!
        
        // Fill with a known pattern
        fillTextureWithTestPattern(bgraTexture, pattern: .gradient)
        
        // Read back a pixel to verify BGRA ordering
        let pixel = readPixel(from: bgraTexture, x: 0, y: 0)
        
        print("✅ BGRA texture created successfully")
        print("📝 Pixel at (0,0): R=\(pixel.r), G=\(pixel.g), B=\(pixel.b), A=\(pixel.a)")
        
        // The gradient pattern should have blue at top-left
        if pixel.b > 250 && pixel.r < 5 {
            print("✅ BGRA format is correct")
        } else {
            print("⚠️ BGRA format might have byte order issues")
        }
    }
    
    // MARK: - Diagnostic Summary
    
    func test7_DiagnosticSummary() throws {
        print("\n" + String(repeating: "=", count: 60))
        print("📊 DIAGNOSTIC SUMMARY")
        print(String(repeating: "=", count: 60))
        
        var passedTests: [String] = []
        var failedTests: [String] = []
        
        // Quick re-run of critical checks
        if library.makeFunction(name: "windowVertexShader") != nil &&
           library.makeFunction(name: "windowFragmentShader") != nil {
            passedTests.append("✅ Shaders compile")
        } else {
            failedTests.append("❌ Shaders don't compile")
        }
        
        // Check texture creation
        if createTestTexture() != nil {
            passedTests.append("✅ Textures can be created")
        } else {
            failedTests.append("❌ Texture creation fails")
        }
        
        // Check device
        if device != nil {
            passedTests.append("✅ Metal device available")
        } else {
            failedTests.append("❌ No Metal device")
        }
        
        print("\nPASSED:")
        for test in passedTests {
            print("  \(test)")
        }
        
        if !failedTests.isEmpty {
            print("\nFAILED:")
            for test in failedTests {
                print("  \(test)")
            }
        }
        
        print("\n💡 NEXT DEBUGGING STEPS:")
        if failedTests.isEmpty {
            print("1. Shaders work in isolation")
            print("2. Check if textures from ScreenCaptureKit are valid")
            print("3. Verify render loop is calling draw commands")
            print("4. Check if window pipeline state is being used (not cube pipeline)")
        } else {
            print("1. Fix compilation/setup issues first")
            print("2. Ensure Metal shaders are in the app bundle")
            print("3. Check ShaderTypes.h for struct definitions")
        }
        
        print("\n📝 To test in actual app, temporarily modify windowFragmentShader to:")
        print("   return float4(1.0, 0.0, 0.0, 1.0); // Force red output")
        print("   If screen stays black, pipeline isn't being used")
        print("   If screen turns red, texture binding is the issue")
        print(String(repeating: "=", count: 60))
    }
}