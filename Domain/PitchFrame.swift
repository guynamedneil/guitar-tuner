import Foundation

// MARK: - Pitch Frame

/// Represents a single frame of pitch detection output
struct PitchFrame {
    /// Detected fundamental frequency in Hz, or nil if no pitch detected
    let frequencyHz: Double?

    /// Confidence level of the detection (0.0 to 1.0)
    let confidence: Double

    /// Root mean square amplitude of the audio frame
    let rms: Double

    /// Timestamp of when this frame was captured
    let timestamp: TimeInterval
}
