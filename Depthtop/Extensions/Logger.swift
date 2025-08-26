//
//  Logger.swift
//  Depthtop
//
//  Centralized logging with easy on/off control
//

import Foundation
import os

/// Global flag to control verbose logging
/// Set to false to disable most logging output
fileprivate let VERBOSE_LOGGING = false

/// Subsystem identifier for unified logging
fileprivate let subsystem = "com.depthtop"

/// Custom loggers for different components
struct DepthtopLogger {
    static let renderer = Logger(subsystem: subsystem, category: "Renderer")
    static let window = Logger(subsystem: subsystem, category: "WindowCapture")
    static let immersive = Logger(subsystem: subsystem, category: "ImmersiveSpace")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let general = Logger(subsystem: subsystem, category: "General")
}

/// Debug-only print that compiles out in Release builds
@inline(__always)
func debugLog(_ message: @autoclosure () -> String, 
              file: String = #file, 
              line: Int = #line) {
    #if DEBUG
    if VERBOSE_LOGGING {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("[\(filename):\(line)] \(message())")
    }
    #endif
}

/// Verbose logging that can be toggled without recompiling
@inline(__always)
func verboseLog(_ message: @autoclosure () -> String,
                category: Logger = DepthtopLogger.general) {
    #if DEBUG
    if VERBOSE_LOGGING {
        let msg = message()
        category.debug("\(msg)")
    }
    #endif
}

/// Always log important events (errors, milestones)
@inline(__always)
func importantLog(_ message: String,
                  category: Logger = DepthtopLogger.general) {
    category.info("\(message)")
}

/// Error logging - always enabled
@inline(__always)
func errorLog(_ message: String,
              category: Logger = DepthtopLogger.general) {
    category.error("\(message)")
}

// MARK: - Renderer Logging

extension DepthtopLogger {
    /// Log renderer events with frame throttling
    static func rendererFrame(_ frameIndex: UInt64, _ message: @autoclosure () -> String) {
        #if DEBUG
        if VERBOSE_LOGGING && frameIndex % 60 == 0 {  // Only log every 60th frame
            let msg = message()
            renderer.debug("Frame \(frameIndex): \(msg)")
        }
        #endif
    }
    
    /// Log renderer milestones (always visible)
    static func rendererMilestone(_ message: String) {
        renderer.info("🎯 \(message)")
    }
    
    /// Log renderer errors (always visible)
    static func rendererError(_ message: String) {
        renderer.error("❌ \(message)")
    }
}