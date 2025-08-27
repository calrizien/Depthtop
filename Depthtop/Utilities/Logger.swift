import Foundation

/// Centralized logging configuration for Depthtop
enum LogLevel: Int, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Categories for different logging areas
struct LogCategory: OptionSet {
    let rawValue: Int
    
    static let capture = LogCategory(rawValue: 1 << 0)
    static let rendering = LogCategory(rawValue: 1 << 1)
    static let preview = LogCategory(rawValue: 1 << 2)
    static let ioSurface = LogCategory(rawValue: 1 << 3)
    static let performance = LogCategory(rawValue: 1 << 4)
    static let arkit = LogCategory(rawValue: 1 << 5)
    static let metal = LogCategory(rawValue: 1 << 6)
    static let ui = LogCategory(rawValue: 1 << 7)
    
    static let all: LogCategory = [.capture, .rendering, .preview, .ioSurface, .performance, .arkit, .metal, .ui]
    static let none: LogCategory = []
}

/// Main logger class with configurable output
final class Logger {
    static let shared = Logger()
    
    /// Current log level - only messages at this level or higher will be printed
    var logLevel: LogLevel = .info
    
    /// Categories that are currently enabled
    var enabledCategories: LogCategory = .all
    
    /// Enable/disable all logging
    var isEnabled = true
    
    /// Enable/disable emoji prefixes
    var useEmoji = true
    
    /// Track if we've already logged certain one-time events
    private var loggedOnce = Set<String>()
    
    private init() {}
    
    /// Log a message with specified level and category
    func log(_ message: String, level: LogLevel = .debug, category: LogCategory = .none) {
        guard isEnabled else { return }
        guard level >= logLevel else { return }
        guard category.isEmpty || !enabledCategories.intersection(category).isEmpty else { return }
        
        let prefix = useEmoji ? emojiPrefix(for: level, category: category) : textPrefix(for: level)
        print("\(prefix) \(message)")
    }
    
    /// Log a message only once (useful for first frame info, etc.)
    func logOnce(_ message: String, key: String, level: LogLevel = .debug, category: LogCategory = .none) {
        guard !loggedOnce.contains(key) else { return }
        loggedOnce.insert(key)
        log(message, level: level, category: category)
    }
    
    /// Log verbose details (lowest priority)
    func verbose(_ message: String, category: LogCategory = .none) {
        log(message, level: .verbose, category: category)
    }
    
    /// Log debug information
    func debug(_ message: String, category: LogCategory = .none) {
        log(message, level: .debug, category: category)
    }
    
    /// Log general information
    func info(_ message: String, category: LogCategory = .none) {
        log(message, level: .info, category: category)
    }
    
    /// Log warnings
    func warning(_ message: String, category: LogCategory = .none) {
        log(message, level: .warning, category: category)
    }
    
    /// Log errors (highest priority)
    func error(_ message: String, category: LogCategory = .none) {
        log(message, level: .error, category: category)
    }
    
    /// Reset the once-only log tracking
    func resetOnceTracking() {
        loggedOnce.removeAll()
    }
    
    private func emojiPrefix(for level: LogLevel, category: LogCategory) -> String {
        let levelEmoji: String
        switch level {
        case .verbose: levelEmoji = "🔍"
        case .debug: levelEmoji = "🐛"
        case .info: levelEmoji = "ℹ️"
        case .warning: levelEmoji = "⚠️"
        case .error: levelEmoji = "❌"
        }
        
        // Add category emoji if specific category
        let categoryEmoji: String
        if category.contains(.capture) {
            categoryEmoji = "📹"
        } else if category.contains(.rendering) {
            categoryEmoji = "🎨"
        } else if category.contains(.preview) {
            categoryEmoji = "🖼️"
        } else if category.contains(.ioSurface) {
            categoryEmoji = "🎯"
        } else if category.contains(.performance) {
            categoryEmoji = "📊"
        } else if category.contains(.arkit) {
            categoryEmoji = "👓"
        } else if category.contains(.metal) {
            categoryEmoji = "🔧"
        } else if category.contains(.ui) {
            categoryEmoji = "🖥️"
        } else {
            categoryEmoji = ""
        }
        
        return categoryEmoji.isEmpty ? levelEmoji : "\(levelEmoji)\(categoryEmoji)"
    }
    
    private func textPrefix(for level: LogLevel) -> String {
        switch level {
        case .verbose: return "[VERBOSE]"
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARNING]"
        case .error: return "[ERROR]"
        }
    }
}

// MARK: - Convenience Functions

/// Quick configuration presets
extension Logger {
    /// Silent mode - only errors
    func setSilentMode() {
        logLevel = .error
        enabledCategories = .none
    }
    
    /// Normal mode - info and above
    func setNormalMode() {
        logLevel = .info
        enabledCategories = .all
    }
    
    /// Debug mode - all debug messages
    func setDebugMode() {
        logLevel = .debug
        enabledCategories = .all
    }
    
    /// Verbose mode - everything
    func setVerboseMode() {
        logLevel = .verbose
        enabledCategories = .all
    }
    
    /// Custom mode for specific debugging
    func setCustomMode(level: LogLevel, categories: LogCategory) {
        logLevel = level
        enabledCategories = categories
    }
}