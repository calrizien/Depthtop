//
//  DepthtopApp.swift
//  Depthtop
//
//  Main app class integrating CS_HoverEffect's CompositorServices architecture
//  with Depthtop's window capture functionality
//

import SwiftUI
import RealityKit
import CompositorServices
import ModelIO
import ARKit
@preconcurrency import MetalKit
import os.log

var globalAppModel = AppModel()

@main
struct DepthtopApp: App {
    @State var appModel = globalAppModel
    
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    private var immersionStyleForApp: ImmersionStyle {
        switch appModel.selectedImmersionStyle {
        case .mixed:
            // Mixed might not be available on macOS, fallback to progressive
            #if os(macOS)
            return .progressive
            #else
            return .mixed
            #endif
        case .progressive:
            return .progressive
        case .full:
            return .full
        }
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(CGSize(width: 1000, height: 700))
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appModel)
        }
        #endif

        #if os(macOS)
        RemoteImmersiveSpace(id: AppModel.immersiveSpaceId) {
            MacOSLayer { remoteDeviceIdentifier in
                makeCompositorLayer(CompositorLayerContext(
                    remoteDeviceIdentifier: remoteDeviceIdentifier
                ))
            }
            .onAppear {
                print("RemoteImmersiveSpace appeared")
                appModel.immersiveSpaceState = .open
            }
            .onDisappear {
                print("RemoteImmersiveSpace disappeared") 
                appModel.immersiveSpaceState = .closed
            }
        }
        .immersionStyle(selection: .constant(immersionStyleForApp), in: .progressive, .full)
        .immersiveEnvironmentBehavior(.coexist)
        #else
        ImmersiveSpace(id: AppModel.immersiveSpaceId) {
            makeCompositorLayer(.init())
                .onAppear {
                    print("ImmersiveSpace appeared")
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    print("ImmersiveSpace disappeared")
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(immersionStyleForApp), in: .progressive, .full)
        .immersiveEnvironmentBehavior(.coexist)
        #endif
    }
}

#if os(macOS)
struct MacOSLayer: CompositorContent {
    @Environment(\.remoteDeviceIdentifier)
    private var remoteDeviceIdentifier: RemoteDeviceIdentifier?

    let closure: (RemoteDeviceIdentifier?) -> CompositorLayer

    var body: some CompositorContent {
        closure(remoteDeviceIdentifier)
    }
}
#endif
