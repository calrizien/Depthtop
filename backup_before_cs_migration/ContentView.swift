//
//  ContentView.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
    @State private var selectedWindows: Set<CGWindowID> = []
    @State private var showRealityKitPreview = true
    @State private var showMetalPreview = false
    @State private var showDebugCapture = false
    
    var body: some View {
        HSplitView {
            // Left side: Window list and controls
            NavigationStack {
                VStack(spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Depthtop")
                            .font(.largeTitle)
                            .bold()
                        
                        Text("Select windows to display in spatial view")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Window list - use more of the available space
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.windowCaptureManager.availableWindows, id: \.windowID) { window in
                                WindowRow(
                                    window: window,
                                    isCapturing: appModel.capturedWindows.contains { 
                                        $0.window.windowID == window.windowID 
                                    },
                                    onToggle: { isOn in
                                        Task {
                                            if isOn {
                                                await appModel.startCapture(for: window)
                                            } else {
                                                await appModel.stopCapture(for: window)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    
                    // Controls
                    VStack(spacing: 12) {
                        // Window arrangement picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3D Arrangement")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Picker("Arrangement", selection: Binding(
                                get: { appModel.windowArrangement },
                                set: { 
                                    appModel.windowArrangement = $0
                                    appModel.updateWindowPositions()
                                }
                            )) {
                                Text("Grid").tag(AppModel.WindowArrangement.grid)
                                Text("Curved").tag(AppModel.WindowArrangement.curved)
                                Text("Stack").tag(AppModel.WindowArrangement.stack)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(.horizontal, 12)
                        
                        // Status and controls
                        VStack(spacing: 8) {
                            // Status
                            if appModel.windowCaptureManager.isCapturing {
                                HStack {
                                    Label("\(appModel.capturedWindows.count) windows captured", 
                                          systemImage: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                            
                            // Action buttons - arranged vertically for more space
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Button(action: { showRealityKitPreview.toggle() }) {
                                        Label(showRealityKitPreview ? "Hide 3D Preview" : "Show 3D Preview", 
                                              systemImage: showRealityKitPreview ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    
                                    Button(action: { showMetalPreview.toggle() }) {
                                        Label(showMetalPreview ? "Hide Metal" : "Show Metal", 
                                              systemImage: showMetalPreview ? "square.stack.3d.slash" : "square.stack.3d")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundStyle(.purple)
                                }
                                
                                #if DEBUG
                                Button(action: { showDebugCapture.toggle() }) {
                                    Label(showDebugCapture ? "Hide Debug" : "Show Debug", 
                                          systemImage: showDebugCapture ? "ladybug.slash" : "ladybug")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundStyle(.orange)
                                #endif
                                
                                ToggleImmersiveSpaceButton()
                            }
                        }
                        .padding(.horizontal, 12)
                        
                        // Vision Pro connection status
                        if !supportsRemoteScenes {
                            Label("Remote scenes not supported on this Mac", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal)
                        } else if appModel.immersiveSpaceState == .closed {
                            Text("Note: Vision Pro must be connected to use spatial view")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
                .task {
                    await appModel.refreshWindows()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Refresh") {
                            Task {
                                await appModel.refreshWindows()
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 400)
            
            // Right side: Preview panels
            if showRealityKitPreview || showMetalPreview || showDebugCapture {
                HStack(spacing: 0) {
                    if showRealityKitPreview {
                        RealityKitPreviewView()
                            .environment(appModel)
                            .frame(minWidth: 400, minHeight: 500)
                    }
                    
                    if showMetalPreview {
                        MetalPreviewView()
                            .environment(appModel)
                            .frame(minWidth: 400, minHeight: 500)
                    }
                    
                    if showDebugCapture {
                        DebugCapturePreview()
                            .environment(appModel)
                            .frame(minWidth: 300)
                    }
                }
            }
        }
        .frame(width: totalWidth, height: 600)
    }
    
    private var totalWidth: CGFloat {
        var rightPanelWidth: CGFloat = 0
        
        if showRealityKitPreview {
            rightPanelWidth += 400
        }
        if showMetalPreview {
            rightPanelWidth += 400
        }
        if showDebugCapture {
            rightPanelWidth += 300
        }
        
        return 400 + rightPanelWidth  // Left panel (400) + right panels
    }
}

struct WindowRow: View {
    let window: SCWindow
    let isCapturing: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "macwindow")
                        .foregroundStyle(.tint)
                }
            
            // Window info
            VStack(alignment: .leading, spacing: 4) {
                Text(window.title ?? "Unknown Window")
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(window.owningApplication?.applicationName ?? "Unknown App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Capture toggle
            Toggle("Capture", isOn: Binding(
                get: { isCapturing },
                set: { onToggle($0) }
            ))
            .toggleStyle(SwitchToggleStyle())
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
