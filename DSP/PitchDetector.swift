import Accelerate
import Foundation

// MARK: - Pitch Detection

/// Performs pitch detection on audio sample data using autocorrelation
struct PitchDetector: PitchDetecting {
    /// Minimum frequency to detect (Hz)
    let minimumFrequency: Double

    /// Maximum frequency to detect (Hz)
    let maximumFrequency: Double

    /// Sample rate of the audio input (used as default when not provided)
    let sampleRate: Double

    /// RMS threshold below which audio is considered silence
    let silenceThreshold: Float

    /// Minimum confidence required to report a valid pitch
    let confidenceThreshold: Double

    init(
        sampleRate: Double = 44100,
        minimumFrequency: Double = 60,
        maximumFrequency: Double = 500,
        silenceThreshold: Float = 0.01,
        confidenceThreshold: Double = 0.2
    ) {
        self.sampleRate = sampleRate
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
        self.silenceThreshold = silenceThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    // MARK: - PitchDetecting Protocol

    /// Detects pitch in a frame of audio samples
    /// - Parameters:
    ///   - frame: Array of audio samples (PCM Float values)
    ///   - sampleRate: The sample rate of the audio in Hz
    /// - Returns: A PitchFrame containing the detection results
    func detect(_ frame: [Float], sampleRate: Double) -> PitchFrame {
        let timestamp = Date().timeIntervalSince1970
        let rms = calculateRMS(frame)

        guard !frame.isEmpty else {
            return PitchFrame(frequencyHz: nil, confidence: 0.0, rms: rms, timestamp: timestamp)
        }

        // Check for silence
        if rms < Double(silenceThreshold) {
            return PitchFrame(frequencyHz: nil, confidence: 0.0, rms: rms, timestamp: timestamp)
        }

        let minLag = Int(sampleRate / maximumFrequency)
        let maxLag = Int(sampleRate / minimumFrequency)

        guard maxLag < frame.count, minLag < maxLag else {
            return PitchFrame(frequencyHz: nil, confidence: 0.0, rms: rms, timestamp: timestamp)
        }

        // Calculate autocorrelation at lag 0 for normalization
        var zeroLagCorrelation: Float = 0
        vDSP_dotpr(frame, 1, frame, 1, &zeroLagCorrelation, vDSP_Length(frame.count))

        guard zeroLagCorrelation > 0 else {
            return PitchFrame(frequencyHz: nil, confidence: 0.0, rms: rms, timestamp: timestamp)
        }

        // Find the best lag using autocorrelation
        var bestLag = minLag
        var bestCorrelation: Float = -.greatestFiniteMagnitude
        var correlations = [Float](repeating: 0, count: maxLag - minLag)

        for i in 0..<(maxLag - minLag) {
            let lag = minLag + i
            var correlation: Float = 0
            let overlapLength = frame.count - lag

            frame.withUnsafeBufferPointer { framePtr in
                let delayed = UnsafeBufferPointer(start: framePtr.baseAddress! + lag, count: overlapLength)
                vDSP_dotpr(framePtr.baseAddress!, 1, delayed.baseAddress!, 1, &correlation, vDSP_Length(overlapLength))
            }

            correlations[i] = correlation

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        // Calculate normalized confidence (0.0 to 1.0)
        let normalizedConfidence = Double(bestCorrelation / zeroLagCorrelation)
        let confidence = max(0.0, min(1.0, normalizedConfidence))

        // Apply parabolic interpolation for sub-sample accuracy
        let interpolatedLag = parabolicInterpolation(
            lag: bestLag,
            minLag: minLag,
            correlations: correlations
        )

        let frequency = sampleRate / interpolatedLag

        // Only return frequency if confidence meets threshold
        let detectedFrequency = confidence >= confidenceThreshold ? frequency : nil
        return PitchFrame(frequencyHz: detectedFrequency, confidence: confidence, rms: rms, timestamp: timestamp)
    }

    // MARK: - Legacy Method (for backward compatibility)

    /// Detects the fundamental frequency in the given audio samples
    /// - Parameter samples: Array of audio sample values
    /// - Returns: Detected frequency in Hz, or nil if no pitch detected
    func detectPitch(in samples: [Float]) -> Double? {
        let frame = detect(samples, sampleRate: sampleRate)
        return frame.frequencyHz
    }

    // MARK: - Private Helpers

    /// Calculates the root mean square amplitude of the samples
    private func calculateRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0.0 }

        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))

        return Double(sqrt(sumSquares / Float(samples.count)))
    }

    /// Applies parabolic interpolation around the peak for sub-sample accuracy
    private func parabolicInterpolation(lag: Int, minLag: Int, correlations: [Float]) -> Double {
        let index = lag - minLag

        // Need at least one sample on each side for interpolation
        guard index > 0, index < correlations.count - 1 else {
            return Double(lag)
        }

        let y1 = Double(correlations[index - 1])
        let y2 = Double(correlations[index])
        let y3 = Double(correlations[index + 1])

        // Parabolic interpolation formula
        let denominator = y1 - 2 * y2 + y3

        // Avoid division by zero or near-zero
        guard abs(denominator) > 1e-10 else {
            return Double(lag)
        }

        let delta = 0.5 * (y1 - y3) / denominator

        return Double(lag) + delta
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
