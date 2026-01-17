// MARK: - Pitch Detecting Protocol

/// Protocol for pitch detection algorithms
protocol PitchDetecting {
    /// Detects the pitch in a frame of audio samples
    /// - Parameters:
    ///   - frame: Array of audio samples (PCM Float values)
    ///   - sampleRate: The sample rate of the audio in Hz
    /// - Returns: A PitchFrame containing the detection results
    mutating func detect(_ frame: [Float], sampleRate: Double) -> PitchFrame
}
