//
//  MetalLibraryLoadTest.swift
//  DepthtopTests
//
//  Test Metal library loading issues
//

import XCTest
import Metal

final class MetalLibraryLoadTest: XCTestCase {
    
    func testDefaultLibraryLoading() throws {
        // Create a Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Failed to create Metal device")
            return
        }
        
        print("[TEST] Device created: \(device.name)")
        
        // Try to load the default library
        let defaultLibrary = device.makeDefaultLibrary()
        
        if let library = defaultLibrary {
            print("[TEST] Successfully loaded default library")
            
            // Check for our functions
            let vertexFunction = library.makeFunction(name: "windowVertex")
            let fragmentFunction = library.makeFunction(name: "windowFragment")
            
            XCTAssertNotNil(vertexFunction, "windowVertex function not found")
            XCTAssertNotNil(fragmentFunction, "windowFragment function not found")
            
            print("[TEST] Found windowVertex: \(vertexFunction != nil)")
            print("[TEST] Found windowFragment: \(fragmentFunction != nil)")
        } else {
            print("[TEST] Failed to load default library")
            
            // Try loading from bundle
            if let bundleURL = Bundle.main.url(forResource: "default-binaryarchive", withExtension: "metallib") {
                print("[TEST] Found metallib at: \(bundleURL)")
                
                do {
                    let library = try device.makeLibrary(URL: bundleURL)
                    print("[TEST] Successfully loaded library from bundle")
                    
                    let vertexFunction = library.makeFunction(name: "windowVertex")
                    let fragmentFunction = library.makeFunction(name: "windowFragment")
                    
                    XCTAssertNotNil(vertexFunction, "windowVertex function not found in bundle library")
                    XCTAssertNotNil(fragmentFunction, "windowFragment function not found in bundle library")
                } catch {
                    XCTFail("Failed to load library from bundle: \(error)")
                }
            } else {
                print("[TEST] No metallib found in bundle")
                
                // Check test bundle
                let testBundle = Bundle(for: type(of: self))
                if let testBundleURL = testBundle.url(forResource: "default-binaryarchive", withExtension: "metallib") {
                    print("[TEST] Found metallib in test bundle at: \(testBundleURL)")
                } else {
                    print("[TEST] No metallib in test bundle either")
                }
            }
        }
    }
    
    func testPipelineStateCreationWithFunctionConstants() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Failed to create Metal device")
            return
        }
        
        // Get library (from default or bundle)
        var library: MTLLibrary?
        
        library = device.makeDefaultLibrary()
        if library == nil {
            if let bundleURL = Bundle.main.url(forResource: "default-binaryarchive", withExtension: "metallib") {
                library = try? device.makeLibrary(URL: bundleURL)
            }
        }
        
        guard let lib = library else {
            XCTFail("No library available")
            return
        }
        
        // Create function constants (required for these shaders)
        let functionConstants = MTLFunctionConstantValues()
        var useHoverEffect = false
        var useTextureArray = false  
        var useDebugColors = false
        functionConstants.setConstantValue(&useHoverEffect, type: .bool, index: 0)
        functionConstants.setConstantValue(&useTextureArray, type: .bool, index: 1)
        functionConstants.setConstantValue(&useDebugColors, type: .bool, index: 2)
        
        guard let vertexFunction = try? lib.makeFunction(name: "windowVertex", constantValues: functionConstants),
              let fragmentFunction = try? lib.makeFunction(name: "windowFragment", constantValues: functionConstants) else {
            XCTFail("Failed to create specialized functions")
            return
        }
        
        print("[TEST] Successfully created specialized functions")
        
        // Try to create a pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            XCTAssertNotNil(pipelineState)
            print("[TEST] Successfully created pipeline state")
        } catch {
            XCTFail("Failed to create pipeline state: \(error)")
        }
    }
}