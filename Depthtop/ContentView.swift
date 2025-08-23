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
    @State private var selectedWindows: Set<CGWindowID> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                
                // Window list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appModel.windowCaptureManager.availableWindows, id: \.windowID) { window in
                            WindowRow(
                                window: window,
                                isCapturing: appModel.windowCaptureManager.capturedWindows.contains { 
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
                    .padding(.horizontal)
                }
                
                // Controls
                VStack(spacing: 16) {
                    // Window arrangement picker
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
                    .padding(.horizontal)
                    
                    // Status and immersive space toggle
                    HStack {
                        if appModel.windowCaptureManager.isCapturing {
                            Label("\(appModel.capturedWindows.count) windows captured", 
                                  systemImage: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.green)
                        }
                        
                        Spacer()
                        
                        ToggleImmersiveSpaceButton()
                    }
                    .padding(.horizontal)
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
        .frame(width: 600, height: 500)
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
