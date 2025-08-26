//
//  ToggleImmersiveSpaceButton.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import SwiftUI

struct ToggleImmersiveSpaceButton: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                guard supportsRemoteScenes else {
                    print("Remote scenes are not supported on this Mac. Requires macOS 26.0+ beta.")
                    return
                }
                
                switch appModel.immersiveSpaceState {
                    case .open:
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Don't set immersiveSpaceState to .closed because there
                        // are multiple paths to ImmersiveView.onDisappear().
                        // Only set .closed in ImmersiveView.onDisappear().

                    case .closed:
                        appModel.immersiveSpaceState = .inTransition
                        // Use the literal string to ensure exact match
                        let result = await openImmersiveSpace(id: "ImmersiveSpace")
                        switch result {
                            case .opened:
                                // Don't set immersiveSpaceState to .open because there
                                // may be multiple paths to ImmersiveView.onAppear().
                                // Only set .open in ImmersiveView.onAppear().
                                break

                            case .userCancelled:
                                print("Immersive space opening cancelled by user.")
                                appModel.immersiveSpaceState = .closed
                            case .error:
                                print("Error: Unable to present ImmersiveSpace for Scene id 'ImmersiveSpace'.")
                                print("Make sure:")
                                print("1. You're running macOS 26.0+ (Tahoe) beta")
                                print("2. A Vision Pro device is connected to this Mac")
                                print("   - On Vision Pro: Settings > General > Mac Virtual Display")
                                appModel.immersiveSpaceState = .closed
                            @unknown default:
                                print("Unknown result from openImmersiveSpace: \(String(describing: result))")
                                appModel.immersiveSpaceState = .closed
                        }

                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(appModel.immersiveSpaceState == .inTransition || !supportsRemoteScenes)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
        .help(!supportsRemoteScenes 
            ? "Remote scenes not supported on this Mac (requires macOS 26.0+)"
            : "Requires Vision Pro connected via Mac Virtual Display")
    }
}

