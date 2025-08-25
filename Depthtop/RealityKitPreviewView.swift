//
//  RealityKitPreviewView.swift
//  Depthtop
//
//  RealityKit-based 3D preview of captured windows for macOS
//

import SwiftUI
import RealityKit
import Metal
import MetalKit
import ScreenCaptureKit
import CoreImage
import IOSurface
import Combine
import simd

// MARK: - Timeout Utilities

struct TimeoutError: Error {}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the operation
        group.addTask {
            return try await operation()
        }
        
        // Add the timeout
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        
        group.cancelAll()
        return result
    }
}

// Store entities outside the view to persist across updates
// No ObservableObject or @Published to avoid "Publishing changes" error
final class EntityStorage {
    var windowEntities: [CGWindowID: Entity] = [:]
    var cameraEntity: Entity?
    var sceneRoot: Entity?  // Root entity to hold all windows
    var lastLoggedWindowCount: Int = -1
    var lastTextureUpdate: [CGWindowID: Date] = [:]  // Track last texture update per window
}

struct RealityKitPreviewView: View {
    @Environment(AppModel.self) private var appModel
    // Use a simple State variable to hold the storage reference
    @State private var entityStorage = EntityStorage()
    @State private var targetCameraPosition: SIMD3<Float> = [0, 0, 5]
    @State private var currentCameraPosition: SIMD3<Float> = [0, 0, 5]
    @State private var cameraRotation: SIMD3<Float> = [0, 0, 0] // pitch, yaw, roll
    @State private var isDragging = false
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var textureUpdateTrigger = false  // Trigger RealityView updates for texture changes
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview controls toolbar
            VStack(spacing: 8) {
                // Title and quality
                HStack {
                    Text("3D Preview")
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("Quality", selection: Binding(
                        get: { appModel.previewQuality },
                        set: { appModel.previewQuality = $0 }
                    )) {
                        Text("Low").tag(AppModel.PreviewQuality.low)
                        Text("Medium").tag(AppModel.PreviewQuality.medium)
                        Text("High").tag(AppModel.PreviewQuality.high)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 180)
                }
                
                // Camera controls - spread out nicely
                HStack(spacing: 16) {
                    Button(action: resetCamera) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    // Movement controls in cross pattern
                    VStack(spacing: 4) {
                        // Forward
                        Button(action: { moveCamera(direction: [0, 0, -2]) }) {
                            Image(systemName: "arrow.up")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        
                        // Left/Right
                        HStack(spacing: 12) {
                            Button(action: { moveCamera(direction: [-2, 0, 0]) }) {
                                Image(systemName: "arrow.left")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderless)
                            
                            Button(action: { moveCamera(direction: [2, 0, 0]) }) {
                                Image(systemName: "arrow.right")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        // Back
                        Button(action: { moveCamera(direction: [0, 0, 2]) }) {
                            Image(systemName: "arrow.down")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Spacer()
                    
                    // Instructions
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Drag to look around")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Arrows to move")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            
            // RealityKit view
            RealityView { content in
                // MAKE closure - called once when view is created
                // Setup the scene with camera, lights, and ground
                setupScene(content: content, appModel: appModel)
                
                // Create a root entity for all windows
                let rootEntity = Entity()
                rootEntity.name = "WindowsRoot"
                content.add(rootEntity)
                entityStorage.sceneRoot = rootEntity
                
            } update: { content in
                // UPDATE closure - called when SwiftUI state changes or timer triggers
                // The textureUpdateTrigger causes this to be called periodically
                let _ = textureUpdateTrigger  // Reference the trigger to make SwiftUI call this
                
                print("🔵 RealityView UPDATE CLOSURE CALLED at \(Date())")
                print("   Captured windows count: \(appModel.capturedWindows.count)")
                
                // Don't use Task with escaping closure - run synchronously
                updateWindowEntitiesDeferred(content: content)
                updateCameraPosition(content: content)
            }
            .background(Color.black)
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                // Trigger RealityView updates every 100ms to check for texture changes
                textureUpdateTrigger.toggle()
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            lastMouseLocation = value.location
                        }
                        
                        let delta = CGPoint(
                            x: value.location.x - lastMouseLocation.x,
                            y: value.location.y - lastMouseLocation.y
                        )
                        
                        // Convert mouse movement to camera rotation
                        let sensitivity: Float = 0.01
                        cameraRotation.y += Float(delta.x) * sensitivity  // Yaw
                        cameraRotation.x -= Float(delta.y) * sensitivity  // Pitch (inverted)
                        
                        // Clamp pitch to prevent over-rotation
                        cameraRotation.x = max(-Float.pi/2, min(Float.pi/2, cameraRotation.x))
                        
                        lastMouseLocation = value.location
                        
                        print("🎮 Camera rotation: pitch=\(cameraRotation.x), yaw=\(cameraRotation.y)")
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .overlay(alignment: .bottomLeading) {
                // Stats overlay
                VStack(alignment: .leading, spacing: 4) {
                    if !appModel.capturedWindows.isEmpty {
                        Text("\(appModel.capturedWindows.count) windows, \(entityStorage.windowEntities.count) entities")
                            .font(.caption)
                        Text("Arrangement: \(arrangementName)")
                            .font(.caption)
                    } else {
                        Text("No windows captured")
                            .font(.caption)
                    }
                    
                    // Camera info
                    Text("Camera: (\(String(format: "%.1f", currentCameraPosition.x)), \(String(format: "%.1f", currentCameraPosition.y)), \(String(format: "%.1f", currentCameraPosition.z)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("Rotation: (\(String(format: "%.2f", cameraRotation.x)), \(String(format: "%.2f", cameraRotation.y)), \(String(format: "%.2f", cameraRotation.z)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        // Reset camera to default position and rotation
        targetCameraPosition = [0, 0, 5]
        cameraRotation = [0, 0, 0]
        print("📷 Reset camera to default position and rotation")
    }
    
    private func moveCamera(direction: SIMD3<Float>) {
        // Move camera relative to current rotation
        let yaw = cameraRotation.y
        let pitch = cameraRotation.x
        
        // Create rotation matrix for yaw (Y-axis rotation)
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        
        // Transform direction by current yaw rotation
        let rotatedDirection = SIMD3<Float>(
            direction.x * cosYaw - direction.z * sinYaw,
            direction.y, // Y movement unaffected by yaw
            direction.x * sinYaw + direction.z * cosYaw
        )
        
        targetCameraPosition += rotatedDirection
        print("🎮 Moving camera by \(rotatedDirection) to \(targetCameraPosition)")
    }
    
    private func setupScene(content: RealityViewCameraContent, appModel: AppModel) {
        print("🎬 RealityKit: Setting up scene...")
        
        // Add lighting
        setupLighting(content: content)
        
        // Add ground plane for reference
        setupGroundPlane(content: content)  // ENABLED: Helps with spatial orientation
        
        // Debug spheres to verify scene is working
        addDebugSpheres(content: content)  // ENABLED: Helps verify camera view
        
        // Setup camera EXPLICITLY for macOS non-AR mode
        setupCamera(content: content)
        
        // Test code removed - planes are working correctly now
        
        print("✅ RealityKit: Scene setup complete")
    }
    
    private func setupLighting(content: RealityViewCameraContent) {
        // Create directional light (sun-like)
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.light.color = .white
        // Updated API for macOS 15
        directionalLight.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 10,
            depthBias: 1.0
        )
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
    
    private func addDebugSpheres(content: RealityViewCameraContent) {
        print("🔵 Adding debug spheres to verify camera view...")
        
        // Create bright red sphere at origin
        let originSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.3),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        originSphere.position = [0, 0, 0]
        originSphere.name = "OriginSphere"
        content.add(originSphere)
        print("  Added RED sphere at origin (0, 0, 0)")
        
        // Create green sphere in front (negative Z)
        let frontSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.3),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        frontSphere.position = [0, 0, -2]
        frontSphere.name = "FrontSphere"
        content.add(frontSphere)
        print("  Added GREEN sphere at (0, 0, -2)")
        
        // Create blue sphere to the right
        let rightSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.3),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        rightSphere.position = [2, 0, 0]
        rightSphere.name = "RightSphere"
        content.add(rightSphere)
        print("  Added BLUE sphere at (2, 0, 0)")
        
        // Create yellow sphere above
        let topSphere = ModelEntity(
            mesh: .generateSphere(radius: 0.3),
            materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
        )
        topSphere.position = [0, 2, 0]
        topSphere.name = "TopSphere"
        content.add(topSphere)
        print("  Added YELLOW sphere at (0, 2, 0)")
        
        // Create large purple sphere behind camera to test if we're looking backwards
        let behindSphere = ModelEntity(
            mesh: .generateSphere(radius: 1.0),
            materials: [SimpleMaterial(color: .purple, isMetallic: false)]
        )
        behindSphere.position = [0, 0, 10]
        behindSphere.name = "BehindSphere"
        content.add(behindSphere)
        print("  Added PURPLE sphere behind camera at (0, 0, 10)")
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
        // CRITICAL: macOS RealityKit requires explicit camera setup in non-AR mode
        print("📷 Setting up PerspectiveCamera for macOS...")
        
        let cameraEntity = Entity()
        cameraEntity.name = "MainCamera"
        
        // Create perspective camera component
        var cameraComponent = PerspectiveCameraComponent()
        cameraComponent.fieldOfViewInDegrees = 60
        
        // Add the camera component to the entity
        cameraEntity.components.set(cameraComponent)
        
        // Position camera to look at the scene
        // Move camera back on Z axis and up on Y axis to see the windows
        cameraEntity.position = [0, 0, 5]  // 5 units back on Z axis
        
        // Look at the center of the scene where windows will be
        cameraEntity.look(at: [0, 0, 0], from: cameraEntity.position, relativeTo: nil)
        
        // Add camera to the scene
        content.add(cameraEntity)
        
        // Store camera reference in persistent storage
        entityStorage.cameraEntity = cameraEntity
        
        print("✅ Camera positioned at: \(cameraEntity.position), looking at origin")
    }
    
    private func updateWindowEntitiesDeferred(content: RealityViewCameraContent) {
        // ALWAYS log to debug the issue
        print("\n🔄 === UPDATE WINDOW ENTITIES CALLED ===")
        print("🕐 Time: \(Date())")
        let windowCount = appModel.capturedWindows.count
        print("📊 AppModel captured windows count: \(windowCount)")
        print("📊 Existing entity count: \(entityStorage.windowEntities.count)")
        
        if entityStorage.lastLoggedWindowCount != windowCount {
            print("📊 Window count changed from \(entityStorage.lastLoggedWindowCount) to \(windowCount)")
            entityStorage.lastLoggedWindowCount = windowCount
        }
        
        // Debug: Print detailed info about each captured window (only when count changes)
        if entityStorage.lastLoggedWindowCount != windowCount {
            for (index, window) in appModel.capturedWindows.enumerated() {
                print("  Window \(index): \(window.title)")
                print("    ID: \(window.window.windowID)")
                print("    Has texture: \(window.texture != nil)")
                if let texture = window.texture {
                    print("    Texture size: \(texture.width)x\(texture.height)")
                    print("    Texture format: \(texture.pixelFormat)")
                }
                print("    Last update: \(window.lastUpdate)")
            }
        }
        
        guard let rootEntity = entityStorage.sceneRoot else {
            print("⚠️ No scene root found!")
            return
        }
        
        let capturedWindows = appModel.capturedWindows
        let currentWindowIDs = Set(capturedWindows.map { $0.window.windowID })
        
        // Remove entities for windows that are no longer captured
        var toRemove: [CGWindowID] = []
        for (windowID, entity) in entityStorage.windowEntities {
            if !currentWindowIDs.contains(windowID) {
                toRemove.append(windowID)
                entity.removeFromParent()
            }
        }
        for windowID in toRemove {
            entityStorage.windowEntities.removeValue(forKey: windowID)
            entityStorage.lastTextureUpdate.removeValue(forKey: windowID)  // Clean up throttling data
            print("🗑️ Removed entity for window ID: \(windowID)")
        }
        
        // Add or update entities for captured windows
        for (index, capturedWindow) in capturedWindows.enumerated() {
            let windowID = capturedWindow.window.windowID
            
            if let existingEntity = entityStorage.windowEntities[windowID] {
                // Update texture if available and changed
                if capturedWindow.texture != nil {
                    updateWindowTexture(existingEntity, with: capturedWindow)
                }
            } else {
                // Create new entity SYNCHRONOUSLY
                print("✨ Creating entity for window: \(capturedWindow.title)")
                
                let newEntity = createBasicWindowEntity(for: capturedWindow, at: index)
                
                // Add to scene immediately
                rootEntity.addChild(newEntity)
                entityStorage.windowEntities[windowID] = newEntity
                
                print("📦 Added entity to scene for: \(capturedWindow.title)")
                print("  Position: \(newEntity.position)")
                print("  Children in root: \(rootEntity.children.count)")
                
                // Update texture immediately if available
                if let texture = capturedWindow.texture {
                    print("🎨 Texture available, updating material immediately...")
                    // Apply texture in a more direct way
                    Task { @MainActor in
                        print("🔥 Starting texture application task...")
                        if let modelEntity = newEntity as? ModelEntity {
                            // Try the simplest possible approach first
                            if let material = await createSimpleTexturedMaterial(from: texture) {
                                print("🎨 Got material, applying to entity...")
                                if let mesh = modelEntity.model?.mesh {
                                    modelEntity.model = ModelComponent(mesh: mesh, materials: [material])
                                    print("✅ Applied texture material successfully!")
                                } else {
                                    print("❌ No mesh found on model entity")
                                }
                            } else {
                                print("❌ Failed to create material from texture")
                            }
                        } else {
                            print("❌ Entity is not a ModelEntity")
                        }
                    }
                } else {
                    print("⚠️ No texture available for window, skipping texture update")
                }
            }
        }
        
        // Update camera position if needed
        if !entityStorage.windowEntities.isEmpty {
            calculateOptimalCameraPosition()
        }
    }
    
    @MainActor
    private func updateWindowTexture(_ entity: Entity, with window: CapturedWindow) {
        let windowID = window.window.windowID
        
        // Throttle texture updates to prevent memory overflow - max 10 FPS for texture updates
        let minUpdateInterval: TimeInterval = 0.1  // 100ms = 10 FPS
        let now = Date()
        
        if let lastUpdate = entityStorage.lastTextureUpdate[windowID],
           now.timeIntervalSince(lastUpdate) < minUpdateInterval {
            // Skip this update - too frequent
            return
        }
        
        // Record this update time
        entityStorage.lastTextureUpdate[windowID] = now
        
        // Only update texture, not position
        Task { @MainActor in
            if let modelEntity = entity as? ModelEntity,
               let texture = window.texture,
               let material = await createMaterial(from: texture) {
                
                print("🎯 Throttled texture update for window: \(window.title)")
                
                // Instead of just updating materials array, recreate the ModelComponent
                // This ensures RealityKit properly refreshes the rendering
                if let existingMesh = modelEntity.model?.mesh {
                    print("🔄 Recreating ModelComponent with new texture material")
                    modelEntity.model = ModelComponent(mesh: existingMesh, materials: [material])
                    print("✅ Updated ModelComponent with new texture for entity: \(entity.name ?? "unnamed")")
                } else {
                    // Fallback to materials array update if no mesh found
                    print("⚠️ No existing mesh found, falling back to materials array update")
                    modelEntity.model?.materials = [material]
                    print("✅ Updated materials array for entity: \(entity.name ?? "unnamed")")
                }
            }
        }
    }
    
    private func calculateOptimalCameraPosition() {
        // Find bounds of all window entities
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minY: Float = .infinity
        var maxY: Float = -.infinity
        
        for (_, entity) in entityStorage.windowEntities {
            let pos = entity.position
            minX = min(minX, pos.x - 1.0)  // Account for window width
            maxX = max(maxX, pos.x + 1.0)
            minY = min(minY, pos.y - 1.0)  // Account for window height
            maxY = max(maxY, pos.y + 1.0)
        }
        
        // Calculate center point of all windows
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        
        // Calculate required distance to fit all windows with some padding
        let width = maxX - minX
        let height = maxY - minY
        let maxDimension = max(width, height)
        
        // Use field of view to calculate distance (60 degrees FOV)
        // Distance = (maxDimension / 2) / tan(FOV/2)
        let fovRadians = Float(60.0 * .pi / 180.0)
        let distance = (maxDimension * 1.2) / tan(fovRadians / 2)  // 1.2 for padding
        
        // Set target camera position
        targetCameraPosition = [centerX, centerY, max(distance, 3.0)]  // Minimum 3 units back
    }
    
    private func updateCameraPosition(content: RealityViewCameraContent) {
        guard let camera = entityStorage.cameraEntity else { return }
        
        // Smooth interpolation towards target position
        let lerpFactor: Float = 0.1  // Adjust for smoothness (0.1 = smooth, 1.0 = instant)
        currentCameraPosition = mix(currentCameraPosition, targetCameraPosition, t: lerpFactor)
        
        // Update camera position
        camera.position = currentCameraPosition
        
        // Apply rotation using quaternion
        let pitchQuat = simd_quatf(angle: cameraRotation.x, axis: [1, 0, 0])  // Pitch around X
        let yawQuat = simd_quatf(angle: cameraRotation.y, axis: [0, 1, 0])    // Yaw around Y
        let rollQuat = simd_quatf(angle: cameraRotation.z, axis: [0, 0, 1])   // Roll around Z
        
        // Combine rotations: yaw * pitch * roll
        camera.orientation = yawQuat * pitchQuat * rollQuat
    }
    
    @MainActor
    private func createWindowEntity(for window: CapturedWindow, at index: Int) async -> Entity {
        // Create plane mesh sized to window aspect ratio
        let aspectRatio = window.aspectRatio
        let width: Float = 2.0 * aspectRatio
        let height: Float = 2.0
        
        // Use generatePlane with depth for vertical orientation
        // Note: generatePlane creates a horizontal plane by default, we need to rotate it
        let mesh = MeshResource.generatePlane(width: width, depth: height, cornerRadius: 0.05)
        
        // Create material
        let material: SimpleMaterial
        if let metalTexture = window.texture {
            // Convert Metal texture to material
            material = await createMaterial(from: metalTexture) ?? {
                // Fallback bright material if conversion fails
                let m = SimpleMaterial(color: .init(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0), roughness: 0.3, isMetallic: false)
                print("⚠️ Using fallback red material for window: \(window.title)")
                return m
            }()
        } else {
            // No texture yet - use bright blue to make it visible
            material = SimpleMaterial(color: .init(red: 0.2, green: 0.2, blue: 1.0, alpha: 1.0), roughness: 0.3, isMetallic: false)
            print("ℹ️ No texture available yet, using blue placeholder for window: \(window.title)")
        }
        
        // Create model entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Window_\(window.window.windowID)"
        
        // Position windows in a more spread out arrangement
        let columns = 3  // Max columns before wrapping
        let row = index / columns
        let col = index % columns
        
        let horizontalSpacing: Float = 4.0  // More spacing
        let verticalSpacing: Float = 3.0    // More spacing
        
        // Center the grid but spread it out more
        let totalCols = min(appModel.capturedWindows.count, columns)
        let xOffset = Float(col) * horizontalSpacing - (Float(totalCols - 1) * horizontalSpacing / 2)
        let yOffset = -Float(row) * verticalSpacing + 2.0  // Start higher up
        
        entity.position = [xOffset, yOffset, -2]  // Move windows forward (negative Z) so camera can see them easily
        
        // Rotate plane to stand upright (default plane lies flat on XZ plane)
        // We need to rotate 90 degrees around X axis to make it vertical
        entity.orientation = simd_quatf(angle: -.pi/2, axis: [1, 0, 0])
        
        print("📍 Positioned window '\(window.title)' at: \(entity.position)")
        
        // Add hover effect component
        entity.components.set(HoverEffectComponent())
        
        // Add input target component for interaction
        entity.components.set(InputTargetComponent())
        
        // Add collision component for interaction
        let collisionShape = ShapeResource.generateBox(width: width, height: 0.1, depth: height)
        entity.components.set(CollisionComponent(shapes: [collisionShape]))
        
        return entity
    }
    
    @MainActor
    private func createBasicWindowEntity(for window: CapturedWindow, at index: Int) -> Entity {
        print("\n📦 === CREATING BASIC WINDOW ENTITY ===")
        print("🎯 Window: \(window.title)")
        print("   Window ID: \(window.window.windowID)")
        print("   Index: \(index)")
        
        // Create plane mesh sized to window aspect ratio
        let aspectRatio = window.aspectRatio
        let width: Float = 2.0 * aspectRatio
        let height: Float = 2.0
        
        print("   Aspect ratio: \(aspectRatio)")
        print("   Entity dimensions: \(width) x \(height)")
        
        // Create plane mesh with window's aspect ratio
        let mesh = MeshResource.generatePlane(width: width, depth: height, cornerRadius: 0.05)
        
        // Check if we have a texture and try to use it immediately
        var material: SimpleMaterial
        if let texture = window.texture {
            print("🎨 Window has texture! Size: \(texture.width)x\(texture.height)")
            // Try to create a simple colored material for now
            material = SimpleMaterial(color: .init(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0), roughness: 0.0, isMetallic: false)
            print("🟢 Created GREEN material (texture available but not converted yet)")
        } else {
            print("⚠️ Window has NO texture")
            material = SimpleMaterial(color: .init(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), roughness: 0.0, isMetallic: false)
            print("🔷 Created bright MAGENTA debug material (no texture available)")
        }
        
        // Create model entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Window_\(window.window.windowID)"
        
        print("🔷 Created ModelEntity:")
        print("   Mesh type: \(type(of: mesh))")
        print("   Material count: \(entity.model?.materials.count ?? 0)")
        print("   Entity name: \(entity.name ?? "unnamed")")
        print("   Model exists: \(entity.model != nil)")
        
        // Position windows in a more spread out arrangement
        let columns = 3  // Max columns before wrapping
        let row = index / columns
        let col = index % columns
        
        let horizontalSpacing: Float = 4.0  // More spacing
        let verticalSpacing: Float = 3.0    // More spacing
        
        // Center the grid but spread it out more
        let totalCols = min(appModel.capturedWindows.count, columns)
        let xOffset = Float(col) * horizontalSpacing - (Float(totalCols - 1) * horizontalSpacing / 2)
        let yOffset = -Float(row) * verticalSpacing + 2.0  // Start higher up
        
        // Position windows in a grid arrangement
        entity.position = [xOffset, yOffset, 0]  // Use calculated grid position
        print("🔍 DEBUG: Positioned window at (\(xOffset), \(yOffset), 0)")
        
        // Rotate plane to stand upright (default plane lies flat on XZ plane)
        // We need to rotate 90 degrees around X axis to make it vertical
        entity.orientation = simd_quatf(angle: -.pi/2, axis: [1, 0, 0])
        print("🔍 DEBUG: Rotated plane to stand upright (90° around X axis)")
        
        print("📍 Positioned window '\(window.title)' at: \(entity.position)")
        
        // Add interaction components
        entity.components.set(HoverEffectComponent())
        entity.components.set(InputTargetComponent())
        
        // Add collision component for interaction
        let collisionShape = ShapeResource.generateBox(width: width, height: 0.1, depth: height)
        entity.components.set(CollisionComponent(shapes: [collisionShape]))
        
        return entity
    }
    
    @MainActor
    private func updateEntityTextureFromCapture(_ entity: Entity, with window: CapturedWindow) async {
        print("\n🔄 === UPDATING ENTITY TEXTURE ===")
        print("🎯 Entity: \(entity.name ?? "unnamed")")
        print("🎯 Window: \(window.title)")
        
        guard let modelEntity = entity as? ModelEntity else {
            print("❌ Entity is not a ModelEntity: \(type(of: entity))")
            return
        }
        
        guard let metalTexture = window.texture else {
            print("❌ Window has no Metal texture")
            print("   Window ID: \(window.window.windowID)")
            print("   Last update: \(window.lastUpdate)")
            return
        }
        
        print("✅ Prerequisites met - proceeding with material creation")
        print("   Texture: \(metalTexture.width)x\(metalTexture.height)")
        
        // Create material from Metal texture
        if let material = await createMaterial(from: metalTexture) {
            print("🎯 Applying material to ModelEntity...")
            
            // Recreate ModelComponent instead of just updating materials array
            if let existingMesh = modelEntity.model?.mesh {
                print("🔄 Recreating ModelComponent with new texture material")
                modelEntity.model = ModelComponent(mesh: existingMesh, materials: [material])
                print("✅ Successfully updated entity texture with new ModelComponent: \(entity.name ?? "unnamed")")
            } else {
                // Fallback to materials array update if no mesh found
                print("⚠️ No existing mesh found, using materials array update as fallback")
                modelEntity.model?.materials = [material]
                print("✅ Successfully updated entity texture via materials array: \(entity.name ?? "unnamed")")
            }
        } else {
            print("❌ Failed to create material from IOSurface for entity: \(entity.name ?? "unnamed")")
            print("🔷 Entity will keep bright BLUE debug material (indicates texture conversion failure)")
        }
        print("=== UPDATE ENTITY TEXTURE COMPLETE ===\n")
    }
    
    @MainActor
    private func createSimpleTexturedMaterial(from metalTexture: MTLTexture) async -> SimpleMaterial? {
        print("🚀 SIMPLE: Creating textured material...")
        
        // The file approach works reliably on macOS RealityKit
        // Direct CGImage to TextureResource has compatibility issues
        return await createMaterialViaTemporaryFile(from: metalTexture)
    }
    
    @MainActor
    private func createMaterial(from metalTexture: MTLTexture) async -> SimpleMaterial? {
        print("\n🎨 === CREATING MATERIAL FROM METAL TEXTURE ===")
        print("🎯 Texture: \(metalTexture.width)x\(metalTexture.height), format: \(metalTexture.pixelFormat)")
        
        // Validate texture properties
        guard metalTexture.width > 0 && metalTexture.height > 0 else {
            print("❌ Invalid texture dimensions")
            return SimpleMaterial(color: .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), roughness: 0.3, isMetallic: false)
        }
        
        // Convert Metal texture to CGImage then to TextureResource
        // This is the recommended approach per Perplexity research
        return await createTextureResourceFromMetal(metalTexture: metalTexture)
    }
    
    @MainActor
    private func createTextureResourceFromMetal(metalTexture: MTLTexture) async -> SimpleMaterial? {
        print("🔧 Converting Metal texture to TextureResource...")
        
        // APPROACH 1: Standardize the CGImage to fix color space/format issues
        guard let standardizedCGImage = createStandardizedCGImage(from: metalTexture) else {
            print("❌ Failed to create standardized CGImage")
            
            // APPROACH 2: Fallback to temporary file if direct conversion fails
            return await createMaterialViaTemporaryFile(from: metalTexture)
        }
        
        print("✅ Created standardized CGImage: \(standardizedCGImage.width)x\(standardizedCGImage.height)")
        
        // Create TextureResource from CGImage with proper options
        do {
            // Use init instead of generate (generate doesn't exist in macOS RealityKit)
            let textureResource = try await TextureResource(
                image: standardizedCGImage,
                options: TextureResource.CreateOptions(semantic: .color)
            )
            
            print("✅ Created TextureResource successfully")
            
            var material = SimpleMaterial()
            material.color = SimpleMaterial.BaseColor(texture: MaterialParameters.Texture(textureResource))
            material.roughness = 0.3
            material.metallic = 0.0
            
            print("✅ Created SimpleMaterial with texture")
            return material
            
        } catch {
            print("❌ TextureResource.generate failed: \(error)")
            
            // Try fallback approach
            return await createMaterialViaTemporaryFile(from: metalTexture)
        }
    }
    
    @MainActor
    private func createStandardizedCGImage(from metalTexture: MTLTexture) -> CGImage? {
        print("📐 Standardizing CGImage from Metal texture...")
        
        // First convert Metal texture to CIImage
        guard let ciImage = CIImage(mtlTexture: metalTexture, options: [
            .colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ]) else {
            print("❌ Failed to create CIImage from Metal texture")
            return nil
        }
        
        // Create CIContext with specific options for macOS
        let ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
        
        let renderRect = CGRect(x: 0, y: 0, width: metalTexture.width, height: metalTexture.height)
        
        // First get CGImage from CIContext
        guard let initialCGImage = ciContext.createCGImage(ciImage, from: renderRect) else {
            print("❌ Failed to create initial CGImage from CIImage")
            return nil
        }
        
        // Now standardize it to ensure proper format for RealityKit
        let width = initialCGImage.width
        let height = initialCGImage.height
        
        // Create a new context with exact specifications RealityKit expects
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("❌ Failed to create sRGB color space")
            return nil
        }
        
        // Use premultiplied first alpha (ARGB) format as per Perplexity recommendations
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("❌ Failed to create standardized CGContext")
            return nil
        }
        
        // Draw the image into the standardized context
        context.draw(initialCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get the standardized CGImage
        guard let standardizedImage = context.makeImage() else {
            print("❌ Failed to create standardized CGImage from context")
            return nil
        }
        
        print("✅ Standardized CGImage created with proper format")
        return standardizedImage
    }
    
    @MainActor
    private func createMaterialViaTemporaryFile(from metalTexture: MTLTexture) async -> SimpleMaterial? {
        print("💾 Fallback: Creating material via temporary file...")
        
        // First get a CGImage (even if not perfectly standardized)
        guard let ciImage = CIImage(mtlTexture: metalTexture, options: [:]) else {
            print("❌ Failed to create CIImage for fallback")
            return SimpleMaterial(color: .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), roughness: 0.3, isMetallic: false)
        }
        
        let ciContext = CIContext()
        let renderRect = CGRect(x: 0, y: 0, width: metalTexture.width, height: metalTexture.height)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: renderRect) else {
            print("❌ Failed to create CGImage for fallback")
            return SimpleMaterial(color: .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), roughness: 0.3, isMetallic: false)
        }
        
        // Convert to PNG data
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("❌ Failed to create PNG data")
            return SimpleMaterial(color: .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), roughness: 0.3, isMetallic: false)
        }
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("texture_\(UUID().uuidString).png")
        
        do {
            try pngData.write(to: tempURL)
            print("✅ Saved texture to temporary file: \(tempURL.lastPathComponent)")
            
            // Load TextureResource from file
            let textureResource = try await TextureResource.load(contentsOf: tempURL)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            var material = SimpleMaterial()
            material.color = SimpleMaterial.BaseColor(texture: MaterialParameters.Texture(textureResource))
            material.roughness = 0.3
            material.metallic = 0.0
            
            print("✅ Created SimpleMaterial via temporary file approach")
            return material
            
        } catch {
            print("❌ Failed to create texture via temporary file: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return SimpleMaterial(color: .init(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0), roughness: 0.3, isMetallic: false)
        }
    }
}

// MARK: - Preview

#Preview {
    RealityKitPreviewView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}