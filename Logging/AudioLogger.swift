import Foundation
import os

// MARK: - Audio Logger

/// Centralized logging for audio-related operations using Unified Logging
enum AudioLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.GuitarTuner"

    /// Logger for audio capture, processing, and routing events
    static let audio = Logger(subsystem: subsystem, category: "audio")
}
