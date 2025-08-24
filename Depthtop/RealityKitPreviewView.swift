//
//  RealityKitPreviewView.swift
//  Depthtop
//
//  RealityKit-based 3D preview of captured windows for macOS
//

import SwiftUI
import RealityKit
import Metal
import ScreenCaptureKit
import CoreImage

struct RealityKitPreviewView: View {
    @Environment(AppModel.self) private var appModel
    @State private var windowEntities: [CGWindowID: Entity] = [:]
    @State private var lastUpdateTime = Date()
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview controls toolbar
            HStack {
                Text("3D Preview")
                    .font(.headline)
                
                Spacer()
                
                // Camera controls
                Button(action: resetCamera) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                
                // Preview quality selector
                Picker("Quality", selection: Binding(
                    get: { appModel.previewQuality },
                    set: { appModel.previewQuality = $0 }
                )) {
                    Text("Low").tag(AppModel.PreviewQuality.low)
                    Text("Medium").tag(AppModel.PreviewQuality.medium)
                    Text("High").tag(AppModel.PreviewQuality.high)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            
            // RealityKit view
            RealityView { content in
                // Set camera mode to virtual (non-AR) for desktop preview
                content.camera = .virtual
                
                // Setup the scene
                setupScene(content: content)
                
            } update: { content in
                // Update window entities dynamically
                updateWindowEntities(content: content)
            }
            .background(Color.black)
            .overlay(alignment: .bottomLeading) {
                // Stats overlay
                VStack(alignment: .leading, spacing: 4) {
                    if !appModel.capturedWindows.isEmpty {
                        Text("\(appModel.capturedWindows.count) windows")
                            .font(.caption)
                        Text("Arrangement: \(arrangementName)")
                            .font(.caption)
                    } else {
                        Text("No windows captured")
                            .font(.caption)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .foregroundColor(.white)
                .padding()
            }
        }
    }
    
    private var arrangementName: String {
        switch appModel.windowArrangement {
        case .grid: return "Grid"
        case .curved: return "Curved"
        case .stack: return "Stack"
        }
    }
    
    private func resetCamera() {
        // Camera reset will be handled by updating the view
        // RealityKit handles camera controls automatically with .virtual mode
    }
    
    private func setupScene(content: RealityViewCameraContent) {
        // Add lighting
        setupLighting(content: content)
        
        // Add ground plane for reference
        setupGroundPlane(content: content)
        
        // Setup initial camera position
        setupCamera(content: content)
    }
    
    private func setupLighting(content: RealityViewCameraContent) {
        // Create directional light (sun-like)
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.light.color = .white
        directionalLight.shadow?.maximumDistance = 10
        directionalLight.shadow?.depthBias = 1.0
        directionalLight.look(at: [0, 0, 0], from: [5, 10, 5], relativeTo: nil)
        content.add(directionalLight)
        
        // Add ambient light using PointLight entity
        let ambientLight = PointLight()
        ambientLight.light.intensity = 500
        ambientLight.light.color = .white
        ambientLight.position = [0, 5, 0]
        content.add(ambientLight)
    }
    
    private func setupGroundPlane(content: RealityViewCameraContent) {
        // Create ground plane
        let groundMesh = MeshResource.generatePlane(width: 20, depth: 20)
        var groundMaterial = SimpleMaterial()
        groundMaterial.color = .init(tint: .init(white: 0.1, alpha: 1.0))
        groundMaterial.roughness = 0.8
        groundMaterial.metallic = 0.0
        
        let groundEntity = ModelEntity(mesh: groundMesh, materials: [groundMaterial])
        groundEntity.position = [0, -2, 0]
        groundEntity.name = "GroundPlane"
        content.add(groundEntity)
        
        // Add grid lines
        addGridLines(to: content)
    }
    
    private func addGridLines(to content: RealityViewCameraContent) {
        let gridSize: Float = 20.0
        let gridDivisions = 10
        let lineThickness: Float = 0.02
        
        for i in -gridDivisions...gridDivisions {
            let position = Float(i) * (gridSize / Float(gridDivisions))
            
            // X-axis lines
            let xLineMesh = MeshResource.generateBox(width: lineThickness, height: 0.001, depth: gridSize)
            var lineMaterial = SimpleMaterial()
            lineMaterial.color = .init(tint: .init(white: 0.3, alpha: 0.5))
            
            let xLine = ModelEntity(mesh: xLineMesh, materials: [lineMaterial])
            xLine.position = [position, -1.99, 0]
            xLine.name = "GridLineX_\(i)"
            content.add(xLine)
            
            // Z-axis lines
            let zLineMesh = MeshResource.generateBox(width: gridSize, height: 0.001, depth: lineThickness)
            let zLine = ModelEntity(mesh: zLineMesh, materials: [lineMaterial])
            zLine.position = [0, -1.99, position]
            zLine.name = "GridLineZ_\(i)"
            content.add(zLine)
        }
    }
    
    private func setupCamera(content: RealityViewCameraContent) {
        // RealityKit handles camera automatically in .virtual mode
        // Camera controls are enabled by default on macOS
    }
    
    private func updateWindowEntities(content: RealityViewCameraContent) {
        let capturedWindows = appModel.capturedWindows
        
        // Remove entities for windows that are no longer captured
        let currentWindowIDs = Set(capturedWindows.map { $0.window.windowID })
        
        for (windowID, entity) in windowEntities {
            if !currentWindowIDs.contains(windowID) {
                entity.removeFromParent()
                windowEntities.removeValue(forKey: windowID)
            }
        }
        
        // Add or update entities for captured windows
        for (index, capturedWindow) in capturedWindows.enumerated() {
            let windowID = capturedWindow.window.windowID
            
            if let existingEntity = windowEntities[windowID] {
                // Update existing entity
                updateWindowEntity(existingEntity, with: capturedWindow)
            } else {
                // Create new entity
                let newEntity = createWindowEntity(for: capturedWindow, at: index)
                content.add(newEntity)
                windowEntities[windowID] = newEntity
            }
        }
    }
    
    private func createWindowEntity(for window: CapturedWindow, at index: Int) -> Entity {
        // Create plane mesh sized to window aspect ratio
        let aspectRatio = window.aspectRatio
        let width: Float = 2.0 * aspectRatio
        let height: Float = 2.0
        
        let mesh = MeshResource.generatePlane(width: width, depth: height, cornerRadius: 0.05)
        
        // Create material
        var material = SimpleMaterial()
        if let texture = window.texture {
            // Convert Metal texture to material
            material = createMaterial(from: texture) ?? material
        } else {
            material.color = .init(tint: .darkGray)
        }
        material.roughness = 0.5
        material.metallic = 0.0
        
        // Create model entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Window_\(window.window.windowID)"
        
        // Set position based on window arrangement
        entity.position = window.position
        
        // Rotate to face forward (planes generate facing up by default)
        entity.orientation = simd_quatf(angle: -.pi/2, axis: [1, 0, 0])
        
        // Add hover effect component
        entity.components.set(HoverEffectComponent())
        
        // Add input target component for interaction
        entity.components.set(InputTargetComponent())
        
        // Add collision component for interaction
        let collisionShape = ShapeResource.generateBox(width: width, height: 0.1, depth: height)
        entity.components.set(CollisionComponent(shapes: [collisionShape]))
        
        return entity
    }
    
    private func updateWindowEntity(_ entity: Entity, with window: CapturedWindow) {
        // Update position
        entity.position = window.position
        
        // Update texture if available and changed
        if let modelEntity = entity as? ModelEntity,
           let texture = window.texture {
            print("Updating texture for window: \(window.title)")
            if let material = createMaterial(from: texture) {
                modelEntity.model?.materials = [material]
            } else {
                print("Failed to create material from texture for window: \(window.title)")
            }
        } else {
            print("No texture available for window: \(window.title)")
        }
    }
    
    private func createMaterial(from metalTexture: MTLTexture) -> SimpleMaterial? {
        // Create a simple colored material for now as a test
        // This bypasses texture conversion issues temporarily
        var material = SimpleMaterial()
        material.color = .init(tint: .init(
            red: Double.random(in: 0.3...0.8),
            green: Double.random(in: 0.3...0.8),
            blue: Double.random(in: 0.3...0.8),
            alpha: 1.0
        ))
        material.roughness = 0.5
        material.metallic = 0.0
        
        print("Created placeholder material for testing (texture conversion temporarily disabled)")
        return material
        
        // TODO: Fix texture conversion after verifying window capture works
        /*
        // Convert Metal texture to CGImage for RealityKit
        let ciContext = CIContext()
        
        // Create CIImage from Metal texture
        guard let ciImage = CIImage(mtlTexture: metalTexture, options: nil) else {
            print("Failed to create CIImage from Metal texture")
            return nil
        }
        
        // Flip vertically (Metal coordinate system is different)
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: ciImage.extent.height))
        
        // Convert to CGImage
        guard let cgImage = ciContext.createCGImage(flipped, from: flipped.extent) else {
            print("Failed to create CGImage from CIImage")
            return nil
        }
        
        // Create texture resource from CGImage
        do {
            let textureResource = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
            
            var material = SimpleMaterial()
            material.color = .init(texture: .init(textureResource))
            material.roughness = 0.5
            material.metallic = 0.0
            
            return material
        } catch {
            print("Failed to create texture resource: \(error)")
            return nil
        }
        */
    }
}

// MARK: - Preview

#Preview {
    RealityKitPreviewView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}