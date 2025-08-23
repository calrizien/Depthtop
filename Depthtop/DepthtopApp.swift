//
//  DepthtopApp.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import ARKit
import CompositorServices
import SwiftUI

struct ImmersiveSpaceContent: CompositorContent {

    @Environment(\.remoteDeviceIdentifier) private var remoteDeviceIdentifier

    var appModel: AppModel

    var body: some CompositorContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            guard let deviceID = remoteDeviceIdentifier else {
                print("Error: No remote device identifier available. Ensure Vision Pro is connected.")
                Task { @MainActor in
                    appModel.immersiveSpaceState = .closed
                }
                return
            }
            Renderer.startRenderLoop(layerRenderer, appModel: appModel, arSession: .init(device: deviceID))
        }
    }
}

extension ImmersiveSpaceContent: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
        let device = MTLCreateSystemDefaultDevice()!

        configuration.drawableRenderContextRasterSampleCount = device.rasterSampleCount

        if capabilities.drawableRenderContextSupportedStencilFormats.contains(.stencil8) {
            configuration.drawableRenderContextStencilFormat = .stencil8
        } else {
            configuration.drawableRenderContextStencilFormat = .depth32Float_stencil8
            configuration.depthFormat = .depth32Float_stencil8
        }

        let foveationEnabled = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)

        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated

        configuration.supportsMTL4 = true
    }
}

@main
struct DepthtopApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        RemoteImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveSpaceContent(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.progressive), in: .progressive)
    }
}