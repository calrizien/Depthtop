//
//  ShaderTestBase.swift
//  DepthtopTests
//
//  Base class for Metal shader testing
//

import XCTest
import Metal
import simd

class ShaderTestBase: XCTestCase {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var library: MTLLibrary!
    
    override func setUp() {
        super.setUp()
        
        device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device, "Metal device should be available")
        
        commandQueue = device.makeCommandQueue()
        XCTAssertNotNil(commandQueue, "Command queue should be created")
        
        // Load the default library (contains our shaders)
        do {
            library = device.makeDefaultLibrary()
            XCTAssertNotNil(library, "Default library should be available")
        }
    }
    
    override func tearDown() {
        library = nil
        commandQueue = nil
        device = nil
        super.tearDown()
    }
    
    // MARK: - Utility Functions
    
    func createTestTexture(width: Int = 1920, height: Int = 1080, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: descriptor)
    }
    
    func fillTextureWithTestPattern(_ texture: MTLTexture, pattern: TestPattern = .gradient) {
        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                
                switch pattern {
                case .solid(let r, let g, let b, let a):
                    pixels[index] = b      // B
                    pixels[index + 1] = g  // G
                    pixels[index + 2] = r  // R
                    pixels[index + 3] = a  // A
                    
                case .gradient:
                    // Blue to red gradient
                    pixels[index] = UInt8(255 * (height - y) / height)  // B
                    pixels[index + 1] = 0                                // G
                    pixels[index + 2] = UInt8(255 * x / width)          // R
                    pixels[index + 3] = 255                             // A
                    
                case .checkerboard:
                    let checker = ((x / 50) + (y / 50)) % 2 == 0
                    let value: UInt8 = checker ? 255 : 0
                    pixels[index] = value      // B
                    pixels[index + 1] = value  // G
                    pixels[index + 2] = value  // R
                    pixels[index + 3] = 255    // A
                    
                case .windowSimulation:
                    // Simulate a typical window with header and content
                    if y < 30 {
                        // Title bar
                        pixels[index] = 200      // B
                        pixels[index + 1] = 200  // G
                        pixels[index + 2] = 200  // R
                        pixels[index + 3] = 255  // A
                    } else {
                        // Content area
                        pixels[index] = 255      // B
                        pixels[index + 1] = 255  // G
                        pixels[index + 2] = 255  // R
                        pixels[index + 3] = 255  // A
                    }
                }
            }
        }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
    }
    
    func readPixel(from texture: MTLTexture, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        // BGRA format
        return (r: pixel[2], g: pixel[1], b: pixel[0], a: pixel[3])
    }
    
    func averageColor(of texture: MTLTexture) -> (r: Float, g: Float, b: Float, a: Float) {
        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        
        var totalR: Int = 0
        var totalG: Int = 0
        var totalB: Int = 0
        var totalA: Int = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                totalB += Int(pixels[index])
                totalG += Int(pixels[index + 1])
                totalR += Int(pixels[index + 2])
                totalA += Int(pixels[index + 3])
            }
        }
        
        let pixelCount = Float(width * height)
        return (
            r: Float(totalR) / pixelCount / 255.0,
            g: Float(totalG) / pixelCount / 255.0,
            b: Float(totalB) / pixelCount / 255.0,
            a: Float(totalA) / pixelCount / 255.0
        )
    }
    
    // Create a simple quad for rendering
    func createQuadVertices() -> [Float] {
        return [
            // Position (x, y, z) + TexCoord (u, v)
            -1.0, -1.0, 0.0,  0.0, 1.0,  // Bottom-left
             1.0, -1.0, 0.0,  1.0, 1.0,  // Bottom-right
            -1.0,  1.0, 0.0,  0.0, 0.0,  // Top-left
             1.0,  1.0, 0.0,  1.0, 0.0,  // Top-right
        ]
    }
    
    enum TestPattern {
        case solid(r: UInt8, g: UInt8, b: UInt8, a: UInt8)
        case gradient
        case checkerboard
        case windowSimulation
    }
}