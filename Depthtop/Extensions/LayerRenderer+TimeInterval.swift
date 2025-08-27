//
//  LayerRenderer+TimeInterval.swift
//  Depthtop
//
//  Extension to expose render duration as TimeInterval
//

import CompositorServices

extension LayerRenderer.Clock.Instant.Duration {
    /// Exposes the render duration as a `TimeInterval`.
    nonisolated var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}