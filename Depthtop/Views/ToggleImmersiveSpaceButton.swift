//
//  ToggleImmersiveSpaceButton.swift
//  Depthtop
//
//  Button for macOS Tahoe (26.0) with RemoteImmersiveSpace support
//

import SwiftUI

struct ToggleImmersiveSpaceButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    private var buttonLabel: String {
        switch appModel.immersiveSpaceState {
        case .open:
            return "Exit Spatial View"
        case .closed:
            return "Enter Spatial View (\(appModel.selectedImmersionStyle.rawValue))"
        case .inTransition:
            return "Loading..."
        }
    }
    
    private var buttonIcon: String {
        switch appModel.immersiveSpaceState {
        case .open:
            return "visionpro.slash"
        case .closed:
            return "visionpro"
        case .inTransition:
            return "hourglass"
        }
    }
    
    private var isDisabled: Bool {
        !supportsRemoteScenes || appModel.immersiveSpaceState == .inTransition
    }
    
    var body: some View {
        Button {
            handleToggle()
        } label: {
            Label(buttonLabel, systemImage: buttonIcon)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isDisabled)
        .help(helpText)
        .overlay(alignment: .topTrailing) {
            if appModel.immersiveSpaceState == .inTransition {
                ProgressView()
                    .controlSize(.small)
                    .offset(x: -8, y: 8)
            }
        }
    }
    
    private var helpText: String {
        if !supportsRemoteScenes {
            return "Requires macOS 26.0+ and Vision Pro connection"
        } else if appModel.immersiveSpaceState == .inTransition {
            return "Please wait..."
        } else if appModel.immersiveSpaceState == .open {
            return "Exit the spatial view and return to desktop preview"
        } else {
            let modeDesc = switch appModel.selectedImmersionStyle {
            case .mixed: "with passthrough blending"
            case .progressive: "with Digital Crown control"
            case .full: "in complete immersion"
            }
            return "Enter spatial view \(modeDesc)"
        }
    }
    
    private func handleToggle() {
        Task { @MainActor in
            guard supportsRemoteScenes else {
                showConnectionError()
                return
            }
            
            switch appModel.immersiveSpaceState {
            case .open:
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
                
            case .closed:
                appModel.immersiveSpaceState = .inTransition
                let result = await openImmersiveSpace(id: AppModel.immersiveSpaceId)
                handleOpenResult(result)
                
            case .inTransition:
                break
            }
        }
    }
    
    private func handleOpenResult(_ result: OpenImmersiveSpaceAction.Result) {
        switch result {
        case .opened:
            // State will be set by ImmersiveView.onAppear()
            break
            
        case .userCancelled:
            appModel.immersiveSpaceState = .closed
            
        case .error:
            showConnectionError()
            appModel.immersiveSpaceState = .closed
            
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
    
    private func showConnectionError() {
        // In a real app, this could show an alert
        print("❌ Cannot connect to Vision Pro")
        print("Ensure Vision Pro is connected via Mac Virtual Display")
    }
}

// Compact version for toolbars
struct CompactImmersiveSpaceToggle: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    var body: some View {
        Button {
            Task {
                await toggleImmersiveSpace()
            }
        } label: {
            Image(systemName: appModel.immersiveSpaceState == .open ? "visionpro.slash" : "visionpro")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .disabled(!supportsRemoteScenes || appModel.immersiveSpaceState == .inTransition)
        .help(appModel.immersiveSpaceState == .open ? "Exit Spatial View" : "Enter Spatial View")
    }
    
    private func toggleImmersiveSpace() async {
        guard supportsRemoteScenes else { return }
        
        if appModel.immersiveSpaceState == .open {
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        } else if appModel.immersiveSpaceState == .closed {
            appModel.immersiveSpaceState = .inTransition
            _ = await openImmersiveSpace(id: AppModel.immersiveSpaceId)
        }
    }
}

#Preview("Button") {
    VStack(spacing: 20) {
        ToggleImmersiveSpaceButton()
            .environment(AppModel())
            .frame(width: 250)
        
        CompactImmersiveSpaceToggle()
            .environment(AppModel())
    }
    .padding()
}