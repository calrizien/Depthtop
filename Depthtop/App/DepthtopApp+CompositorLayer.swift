//
//  DepthtopApp+CompositorLayer.swift
//  Depthtop
//
//  Extension that creates and configures the CompositorLayer
//

import SwiftUI
import RealityKit
import CompositorServices
import ModelIO
import ARKit
@preconcurrency import MetalKit
import os.log

extension DepthtopApp {
    
    func makeCompositorLayer(
        _ context: CompositorLayerContext
    ) -> CompositorLayer {
        CompositorLayer(configuration: { capabilities, configuration in
            
            // Set the buffer formats for the depth and color buffer
            configuration.depthFormat = .depth32Float
            configuration.colorFormat = .bgra8Unorm_srgb

            // Enable foveation if supported
            if capabilities.supportsFoveation {
                configuration.isFoveationEnabled = true
            }
            
            // Set up features requiring visionOS 26 or later
            if #available(visionOS 26.0, *), appModel.withHover {
                // Enable the tracking area buffer for hover effects
                configuration.trackingAreasFormat = .r8Uint
                
                // Specify how to use tracking data
                if appModel.withHover && appModel.useMSAA {
                    configuration.trackingAreasUsage = [.shaderWrite, .shaderRead]
                } else {
                    configuration.trackingAreasUsage = [.renderTarget, .shaderRead]
                }
                
                // Override the render-quality resolution, if requested
                if appModel.overrideResolution {
                    configuration.maxRenderQuality = .init(Float(appModel.resolution))
                }
            }
            
        }) { renderer in
            render(renderer, context: context)
        }
    }
}