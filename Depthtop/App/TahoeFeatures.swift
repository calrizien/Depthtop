//
//  TahoeFeatures.swift
//  Depthtop
//
//  macOS Tahoe (26.0) specific features and capabilities
//

import SwiftUI
import CompositorServices

/// Tahoe-specific features for RemoteImmersiveSpace and Vision Pro integration
@available(macOS 26.0, *)
struct TahoeFeatures {
    
    /// Check if we're running on macOS Tahoe or later
    static var isTahoeOrLater: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    /// Check if RemoteImmersiveSpace is available
    static var hasRemoteImmersiveSpace: Bool {
        #if os(macOS)
        return true  // RemoteImmersiveSpace is macOS Tahoe exclusive
        #else
        return false
        #endif
    }
    
    /// Check if CompositorServices with RemoteDeviceIdentifier is available
    static var hasRemoteDeviceSupport: Bool {
        // This is a Tahoe-specific feature
        return isTahoeOrLater && hasRemoteImmersiveSpace
    }
    
    /// Get system information for debugging
    static var systemInfo: String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    }
}

/// Environment key for Tahoe features
@available(macOS 26.0, *)
struct TahoeFeaturesKey: EnvironmentKey {
    static let defaultValue = TahoeFeatures()
}

@available(macOS 26.0, *)
extension EnvironmentValues {
    var tahoeFeatures: TahoeFeatures {
        get { self[TahoeFeaturesKey.self] }
        set { self[TahoeFeaturesKey.self] = newValue }
    }
}

/// View modifier to add Tahoe-specific UI enhancements
@available(macOS 26.0, *)
struct TahoeUIEnhancements: ViewModifier {
    @Environment(\.supportsRemoteScenes) var supportsRemoteScenes
    
    func body(content: Content) -> some View {
        content
            // Add visual feedback for Vision Pro connection status
            .overlay(alignment: .topTrailing) {
                if supportsRemoteScenes {
                    Image(systemName: "visionpro")
                        .symbolEffect(.pulse.wholeSymbol, isActive: true)
                        .foregroundStyle(.tint)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding()
                        .opacity(0.8)
                }
            }
            // Add Tahoe-specific toolbar items
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if supportsRemoteScenes {
                        Label("Vision Pro Connected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                    }
                }
            }
    }
}

@available(macOS 26.0, *)
extension View {
    func tahoeEnhancements() -> some View {
        self.modifier(TahoeUIEnhancements())
    }
}