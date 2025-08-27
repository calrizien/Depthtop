//
//  DepthtopApp+Render.swift
//  Depthtop
//
//  Extension containing the main render loop entry
//

import SwiftUI
import RealityKit
import CompositorServices
import ModelIO
import ARKit
@preconcurrency import MetalKit
import os

let logger = os.Logger(subsystem: "com.depthtop.render", category: "Rendering")

extension DepthtopApp {
    func render(_ renderer: LayerRenderer, context: CompositorLayerContext) {
        logger.info("[RENDER START] Beginning render setup for immersive space")
        
        #if os(macOS)
        // Check if we have a valid remote device identifier
        if context.remoteDeviceIdentifier == nil {
            logger.warning("[RENDER] No RemoteDeviceIdentifier available - Vision Pro may not be connected")
        } else {
            logger.info("[RENDER] RemoteDeviceIdentifier available - Vision Pro connection established")
        }
        #endif
        
        Task.detached(priority: .high) {
            logger.info("[RENDER] Creating RenderData instance")
            
            let renderData = RenderData(
                layerRenderer: renderer,
                context: context,
                theAppModel: appModel
            )
            
            logger.info("[RENDER] RenderData created successfully")
            
            #if os(visionOS)
            logger.info("[RENDER] Setting up world tracking")
            await renderData.setUpWorldTracking()
            #endif
            
            logger.info("[RENDER] Setting up tile resolve pipeline")
            await renderData.setUpTileResolvePipeline()  // Set up hover tracking pipeline
            
            logger.info("[RENDER] Setting up shader pipeline")
            await renderData.setUpShaderPipeline()
            
            logger.info("[RENDER] Shader pipeline setup completed - checking status")
            
            // Verify pipeline was created
            let pipelineReady = await renderData.isPipelineReady()
            if !pipelineReady {
                logger.error("[RENDER CRITICAL] Pipeline setup failed - cannot proceed with rendering")
                return
            }
            
            logger.info("[RENDER] Pipeline verified, proceeding with spatial events setup")
            
            // Handle spatial events for hover effects and window interaction
            #if os(visionOS)
            if #available(visionOS 26.0, *) {
                renderer.onSpatialEvent = { events in
                    for event in events {
                        logger.log(level: .info, "Received spatial event:\(String(describing: event), privacy: .public)")
                        let id = event.trackingAreaIdentifier.rawValue
                        let phase = event.phase
                        
                        // Handle hover events
                        if phase == .began {
                            // Window hover started
                            Task(priority: .userInitiated) {
                                await renderData.setHoveredWindow(windowID: CGWindowID(id))
                            }
                        } else if phase == .ended {
                            // Window hover ended or clicked
                            if id != 0 {
                                Task(priority: .userInitiated) {
                                    await renderData.handleWindowTap(windowID: CGWindowID(id))
                                }
                            }
                            Task(priority: .userInitiated) {
                                await renderData.clearHoveredWindow()
                            }
                        }
                    }
                }
            }
            #endif
            
            await renderData.renderLoop()
        }
    }
}
