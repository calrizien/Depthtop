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
            // Note: remoteDeviceIdentifier will be nil when running on Mac without Vision Pro connected
            // The template originally force-unwrapped this, but we'll handle it more gracefully
            if let deviceID = remoteDeviceIdentifier {
                Renderer.startRenderLoop(layerRenderer, appModel: appModel, arSession: .init(device: deviceID))
            } else {
                // For testing without Vision Pro, we can still start the renderer
                // but ARKit features won't work
                print("Warning: No Vision Pro connected. Starting renderer without ARKit session.")
                print("To connect: On Vision Pro, go to Settings > General > Mac Virtual Display")
                Renderer.startRenderLoop(layerRenderer, appModel: appModel, arSession: nil)
            }
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

        RemoteImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveSpaceContent(appModel: appModel)
                .onAppear {
                    print("RemoteImmersiveSpace appeared")
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    print("RemoteImmersiveSpace disappeared")
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.progressive), in: .progressive)
    }
}