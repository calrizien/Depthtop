//
//  CompositorLayerContext.swift
//  Depthtop
//
//  Context for compositor layer, handling beta API availability
//

import Foundation
import CompositorServices
import SwiftUI
#if os(macOS)
import ARKit
#endif

/// Context for the compositor layer
struct CompositorLayerContext {
    #if os(macOS)
    var remoteDeviceIdentifier: RemoteDeviceIdentifier?
    
    init(remoteDeviceIdentifier: RemoteDeviceIdentifier? = nil) {
        self.remoteDeviceIdentifier = remoteDeviceIdentifier
    }
    #else
    init() {}
    #endif
}