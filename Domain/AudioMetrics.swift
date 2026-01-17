import Foundation

// MARK: - Audio Metrics

/// Metrics about the current state of audio capture
struct AudioMetrics {
    /// The sample rate detected from the audio hardware (e.g., 44100, 48000)
    let sampleRate: Double

    /// The number of buffer underruns that have occurred (read requests when insufficient samples available)
    let bufferUnderruns: Int

    /// Whether audio capture is currently active
    let isCapturing: Bool
}
