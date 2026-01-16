import Accelerate
import AVFoundation

// MARK: - Pitch Detection

/// Performs pitch detection on audio sample data
struct PitchDetector {
    /// Minimum frequency to detect (Hz)
    let minimumFrequency: Double

    /// Maximum frequency to detect (Hz)
    let maximumFrequency: Double

    /// Sample rate of the audio input
    let sampleRate: Double

    /// Minimum RMS amplitude required for pitch detection
    private let rmsThreshold: Float = 0.01

    init(sampleRate: Double = 44100, minimumFrequency: Double = 60, maximumFrequency: Double = 500) {
        self.sampleRate = sampleRate
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
    }

    /// Detects the fundamental frequency in the given audio samples
    /// - Parameter samples: Array of audio sample values
    /// - Returns: Detected frequency in Hz, or nil if no pitch detected
    func detectPitch(in samples: [Float]) -> Double? {
        guard !samples.isEmpty else { return nil }

        let minLag = Int(sampleRate / maximumFrequency)
        let maxLag = Int(sampleRate / minimumFrequency)

        guard maxLag < samples.count else { return nil }

        var bestLag = minLag
        var bestCorrelation: Float = -1

        for lag in minLag..<maxLag {
            var correlation: Float = 0
            vDSP_dotpr(samples, 1, Array(samples[lag...]), 1, &correlation, vDSP_Length(samples.count - lag))

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        return sampleRate / Double(bestLag)
    }

    /// Processes an audio buffer and returns a pitch frame
    /// - Parameter buffer: The audio buffer to process
    /// - Returns: A PitchFrame with the detected pitch, or nil if the buffer is invalid
    func process(buffer: AVAudioPCMBuffer) -> PitchFrame? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))

        let timestamp = Date().timeIntervalSince1970

        guard rms > rmsThreshold else {
            return PitchFrame(frequencyHz: nil, confidence: 0, rms: Double(rms), timestamp: timestamp)
        }

        let frequency = detectPitch(in: samples)
        let confidence = min(Double(rms) / 0.1, 1.0)

        return PitchFrame(frequencyHz: frequency, confidence: confidence, rms: Double(rms), timestamp: timestamp)
    }
}

// MARK: - Frequency Smoothing

/// Applies exponential smoothing to frequency readings
struct FrequencySmoother {
    private var smoothedValue: Double?

    /// Smoothing factor (0-1). Higher values = more smoothing
    let alpha: Double

    init(alpha: Double = 0.3) {
        self.alpha = max(0, min(1, alpha))
    }

    /// Applies smoothing to a new frequency reading
    /// - Parameter frequency: The new frequency measurement
    /// - Returns: The smoothed frequency value
    mutating func smooth(_ frequency: Double) -> Double {
        guard let previous = smoothedValue else {
            smoothedValue = frequency
            return frequency
        }

        let smoothed = alpha * previous + (1 - alpha) * frequency
        smoothedValue = smoothed
        return smoothed
    }

    /// Resets the smoother state
    mutating func reset() {
        smoothedValue = nil
    }
}
