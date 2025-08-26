//
//  DebugCapturePreview.swift
//  Depthtop
//
//  Debug preview for captured window content using native macOS views
//

import SwiftUI
import AppKit
import IOSurface
import CoreImage
import ScreenCaptureKit
import Combine

struct DebugCapturePreview: View {
    @Environment(AppModel.self) private var appModel
    @State private var updateTrigger = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Debug: Captured Content")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(appModel.capturedWindows.count) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            if appModel.capturedWindows.isEmpty {
                // No windows captured
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    Text("No windows captured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Toggle window capture switches to see content here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show captured windows
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appModel.capturedWindows, id: \.window.windowID) { capturedWindow in
                            DebugWindowPreview(capturedWindow: capturedWindow)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Trigger view updates to show new frames
            updateTrigger.toggle()
        }
    }
}

struct DebugWindowPreview: View {
    let capturedWindow: CapturedWindow
    @State private var displayImage: NSImage?
    @State private var lastSurfaceUpdate: Date = .distantPast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Window info header
            HStack {
                Image(systemName: "macwindow")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(capturedWindow.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("ID: \(capturedWindow.window.windowID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let texture = capturedWindow.texture {
                            Text("Texture: \(texture.width)×\(texture.height)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("Updated: \(capturedWindow.lastUpdate, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(capturedWindow.texture != nil ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding()
            .background(Color(NSColor.separatorColor).opacity(0.3))
            .cornerRadius(8)
            
            // Image preview
            Group {
                if let displayImage = displayImage {
                    Image(nsImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                } else if capturedWindow.texture != nil {
                    // Has texture but no image yet
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.3))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Converting texture to image...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                } else {
                    // No texture available
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.3))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                    .foregroundStyle(.red)
                                Text("No surface data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }
            }
        }
        .onAppear {
            updateImageFromSurface()
        }
        .onChange(of: capturedWindow.lastUpdate) {
            updateImageFromSurface()
        }
    }
    
    private func updateImageFromSurface() {
        guard let texture = capturedWindow.texture,
              capturedWindow.lastUpdate > lastSurfaceUpdate else {
            return
        }
        
        lastSurfaceUpdate = capturedWindow.lastUpdate
        
        Task { @MainActor in
            if let nsImage = await createNSImageFromTexture(texture) {
                self.displayImage = nsImage
                print("✅ DEBUG: Updated preview image for \(capturedWindow.title): \(nsImage.size)")
            } else {
                print("❌ DEBUG: Failed to create NSImage from texture for \(capturedWindow.title)")
            }
        }
    }
    
    @MainActor
    private func createNSImageFromTexture(_ texture: MTLTexture) async -> NSImage? {
        print("🖼️ DEBUG: Creating NSImage from Metal texture: \(texture.width)×\(texture.height)")
        
        // Create CIImage from Metal texture
        guard let ciImage = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ]) else {
            print("❌ DEBUG: Failed to create CIImage from Metal texture")
            return nil
        }
        
        // Create CIContext for rendering
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("❌ DEBUG: Failed to create color space")
            return nil
        }
        
        let ciContext = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .useSoftwareRenderer: false
        ])
        
        // Render to CGImage
        let renderRect = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        guard let cgImage = ciContext.createCGImage(ciImage, from: renderRect) else {
            print("❌ DEBUG: Failed to create CGImage from CIImage")
            return nil
        }
        
        // Create NSImage
        let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        print("✅ DEBUG: Created NSImage: \(nsImage.size) from CGImage: \(cgImage.width)×\(cgImage.height)")
        
        return nsImage
    }
}

#Preview {
    DebugCapturePreview()
        .environment(AppModel())
        .frame(width: 400, height: 600)
}