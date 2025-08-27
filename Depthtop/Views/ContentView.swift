//
//  ContentView.swift
//  Depthtop
//
//  Main UI for macOS Tahoe (26.0) with RemoteImmersiveSpace support
//

import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
    @State private var selectedWindows: Set<CGWindowID> = []
    @State private var showSettings = false
    @State private var showPreview = true
    @State private var searchText = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("Depthtop")
        .navigationSubtitle(supportsRemoteScenes ? "Vision Pro Connected" : "Awaiting Connection")
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
        .task {
            await appModel.refreshWindows()
        }
        // Tahoe-specific: Show Vision Pro connection status in toolbar
        .toolbar {
            ToolbarItem(placement: .status) {
                if supportsRemoteScenes {
                    Label("Vision Pro Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                } else {
                    Label("Vision Pro Not Connected", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .labelStyle(.iconOnly)
                }
            }
        }
    }
    
    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedWindows) {
            Section {
                // Immersive Space Control
                VStack(spacing: 8) {
                    ToggleImmersiveSpaceButton()
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    
                    if appModel.immersiveSpaceState == .open {
                        Label("Immersive space active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }
            
            Section("Window Arrangement") {
                Picker("Layout", selection: Binding(
                    get: { appModel.windowArrangement },
                    set: { 
                        appModel.windowArrangement = $0
                        appModel.updateWindowPositions()
                    }
                )) {
                    Label("Grid", systemImage: "square.grid.3x3")
                        .tag(AppModel.WindowArrangement.grid)
                    Label("Curved", systemImage: "rectangle.curved.badge.checkmark")
                        .tag(AppModel.WindowArrangement.curved)
                    Label("Stack", systemImage: "square.stack.3d.up")
                        .tag(AppModel.WindowArrangement.stack)
                }
                .pickerStyle(.inline)
                .labelStyle(.titleAndIcon)
            }
            
            Section("Available Windows (\(filteredWindows.count))") {
                ForEach(filteredWindows, id: \.windowID) { window in
                    WindowRow(
                        window: window,
                        isCapturing: appModel.capturedWindows.contains { 
                            $0.window.windowID == window.windowID 
                        }
                    )
                    .tag(window.windowID)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search windows...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await appModel.refreshWindows()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh window list")
                
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 350)
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        if appModel.immersiveSpaceState == .open {
            // Immersive space active view
            VStack(spacing: 20) {
                Image(systemName: "visionpro")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
                
                Text("Immersive Space Active")
                    .font(.largeTitle)
                    .fontWeight(.medium)
                
                Text("\(appModel.capturedWindows.count) windows are being rendered in spatial view")
                    .foregroundStyle(.secondary)
                
                if appModel.withHover {
                    Label("Hover effects enabled", systemImage: "hand.point.up.left")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else if showPreview {
            // Preview tabs
            TabView {
                MetalPreviewView()
                    .environment(appModel)
                    .tabItem {
                        Label("Metal Preview", systemImage: "cube.transparent")
                    }
                
                RealityKitPreviewView()
                    .environment(appModel)
                    .tabItem {
                        Label("3D Preview", systemImage: "view.3d")
                    }
                
                #if DEBUG
                DebugCapturePreview()
                    .environment(appModel)
                    .tabItem {
                        Label("Debug", systemImage: "ladybug")
                    }
                #endif
            }
            .padding()
        } else {
            // Empty state
            ContentUnavailableView {
                Label("No Preview", systemImage: "eye.slash")
            } description: {
                Text("Select windows from the sidebar to begin capturing")
            } actions: {
                Button("Show Preview") {
                    showPreview = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Filtered Windows
    private var filteredWindows: [SCWindow] {
        if searchText.isEmpty {
            return appModel.windowCaptureManager.availableWindows
        } else {
            return appModel.windowCaptureManager.availableWindows.filter { window in
                let title = window.title?.localizedCaseInsensitiveContains(searchText) ?? false
                let app = window.owningApplication?.applicationName.localizedCaseInsensitiveContains(searchText) ?? false
                return title || app
            }
        }
    }
}

// MARK: - Window Row
struct WindowRow: View {
    let window: SCWindow
    let isCapturing: Bool
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon with proper styling
            Group {
                if let appName = window.owningApplication?.applicationName {
                    // Try to get the app icon
                    let appPath = "/System/Applications/\(appName).app"
                    let appIcon = NSWorkspace.shared.icon(forFile: appPath)
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 32, height: 32)
            
            // Window info with proper hierarchy
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title ?? "Untitled Window")
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let appName = window.owningApplication?.applicationName {
                        Text(appName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            
            Spacer()
            
            // Capture toggle with proper state
            Toggle("", isOn: Binding(
                get: { isCapturing },
                set: { newValue in
                    Task {
                        if newValue {
                            await appModel.startCapture(for: window)
                        } else {
                            await appModel.stopCapture(for: window)
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}