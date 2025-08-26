//
//  CompositorLayerContext.swift
//  Depthtop
//
//  Context for compositor layer, handling beta API availability
//

import Foundation
import CompositorServices
#if os(macOS)
import ARKit
#endif

/// Context for the compositor layer
struct CompositorLayerContext {
    #if os(macOS)
    // Store as Any? to avoid direct type dependency
    var remoteDevice: Any?
    
    init(remoteDevice: Any? = nil) {
        self.remoteDevice = remoteDevice
    }
    
    // Computed property to safely access the device if available
    var remoteDeviceIdentifier: Any? {
        return remoteDevice
    }
    #else
    init() {}
    #endif
}