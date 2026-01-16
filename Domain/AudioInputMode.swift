import Foundation

// MARK: - Audio Input Mode

/// Configuration for selecting the audio input source
enum AudioInputMode {
    /// Uses the real microphone for audio capture (requires microphone permission)
    case real
    /// Uses mock audio that sweeps smoothly between frequencies for animation testing
    case mockGlide
    /// Uses mock audio that cycles through guitar tuning note frequencies
    case mockStepNotes

    /// Human-readable description of the mode
    var description: String {
        switch self {
        case .real:
            return "real"
        case .mockGlide:
            return "mock (glide)"
        case .mockStepNotes:
            return "mock (notes)"
        }
    }

    /// Converts to the corresponding MockFrequencyGenerator.Mode, if applicable
    var mockMode: MockFrequencyGenerator.Mode? {
        switch self {
        case .real:
            return nil
        case .mockGlide:
            return .glide
        case .mockStepNotes:
            return .stepNotes
        }
    }
}
