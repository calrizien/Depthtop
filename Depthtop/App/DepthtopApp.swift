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

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }.defaultSize(CGSize(width: 800, height: 600))

        #if os(macOS)
        RemoteImmersiveSpace(id: AppModel.immersiveSpaceId) {
            MacOSLayer { remoteDeviceIdentifier in
                makeCompositorLayer(CompositorLayerContext(
                    remoteDevice: remoteDeviceIdentifier
                ))
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        #else
        ImmersiveSpace(id: AppModel.immersiveSpaceId) {
            makeCompositorLayer(.init())
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        #endif
    }
}

#if os(macOS)
struct MacOSLayer: CompositorContent {
    // Access the actual RemoteDeviceIdentifier type
    @Environment(\.remoteDeviceIdentifier)
    private var remoteDeviceIdentifier: RemoteDeviceIdentifier?

    // But pass it as Any? to avoid type issues
    let closure: (Any?) -> CompositorLayer

    var body: some CompositorContent {
        closure(remoteDeviceIdentifier as Any?)
    }
}
#endif