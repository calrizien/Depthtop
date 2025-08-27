//
//  SettingsView.swift
//  Depthtop
//
//  Settings and developer options for macOS Tahoe (26.0)
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showDeveloperSection = false
    
    var body: some View {
        Form {
            // MARK: - Display Settings
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Display", systemImage: "display")
                        .font(.headline)
                    
                    Toggle("Enable Hover Effects", isOn: Binding(
                        get: { appModel.withHover },
                        set: { appModel.withHover = $0 }
                    ))
                    .toggleStyle(.switch)
                    
                    Toggle("Use MSAA for Better Quality", isOn: Binding(
                        get: { appModel.useMSAA },
                        set: { appModel.useMSAA = $0 }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!appModel.withHover)
                    
                    Toggle("Enable Foveation", isOn: Binding(
                        get: { appModel.foveation },
                        set: { appModel.foveation = $0 }
                    ))
                    .toggleStyle(.switch)
                    .help("Optimizes rendering quality based on eye tracking")
                }
                .padding(.vertical, 8)
            }
            
            // MARK: - Performance Settings
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Performance", systemImage: "speedometer")
                        .font(.headline)
                    
                    HStack {
                        Text("Preview Quality")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appModel.previewQuality },
                            set: { appModel.previewQuality = $0 }
                        )) {
                            ForEach(AppModel.PreviewQuality.allCases, id: \.self) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Override Resolution", isOn: Binding(
                            get: { appModel.overrideResolution },
                            set: { appModel.overrideResolution = $0 }
                        ))
                        .toggleStyle(.switch)
                        
                        if appModel.overrideResolution {
                            HStack {
                                Text("Resolution Scale")
                                    .foregroundStyle(.secondary)
                                Slider(value: Binding(
                                    get: { appModel.resolution },
                                    set: { appModel.resolution = $0 }
                                ), in: 0.5...2.0, step: 0.1)
                                Text(String(format: "%.1fx", appModel.resolution))
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .trailing)
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // MARK: - Developer Options
            #if DEBUG
            DisclosureGroup("Developer Options", isExpanded: $showDeveloperSection) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Debug Colors", isOn: Binding(
                        get: { appModel.debugColors },
                        set: { appModel.debugColors = $0 }
                    ))
                    .toggleStyle(.switch)
                    .help("Shows hover areas with debug colors")
                    
                    if appModel.hoveredWindowID != nil {
                        HStack {
                            Text("Hovered Window ID:")
                                .foregroundStyle(.secondary)
                            Text("\(appModel.hoveredWindowID!)")
                                .monospacedDigit()
                        }
                        
                        HStack {
                            Text("Hover Progress:")
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(appModel.hoverProgress), total: 1.0)
                                .progressViewStyle(.linear)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Captured Windows: \(appModel.capturedWindows.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Immersive Space: \(String(describing: appModel.immersiveSpaceState))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            .foregroundStyle(.secondary)
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}