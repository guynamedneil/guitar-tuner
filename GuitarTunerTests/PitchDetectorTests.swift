import XCTest
@testable import GuitarTuner

final class PitchDetectorTests: XCTestCase {

    // MARK: - Test Configuration

    private let defaultSampleRate: Double = 44100
    private let defaultFrameSize = 4096
    private let frequencyAccuracy: Double = 2.0 // Hz tolerance for frequency detection

    // MARK: - Sine Wave Detection Tests

    func testDetectA4_440Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 440.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 440.0, noteName: "A4")
    }

    func testDetectE2_82Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate, minimumFrequency: 60)
        let samples = generateSineWave(frequency: 82.41, sampleRate: defaultSampleRate, sampleCount: 8192)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 82.41, noteName: "E2", minimumConfidence: 0.7)
    }

    func testDetectA2_110Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 110.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 110.0, noteName: "A2")
    }

    func testDetectD3_147Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 146.83, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 146.83, noteName: "D3")
    }

    func testDetectG3_196Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 196.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 196.0, noteName: "G3")
    }

    func testDetectB3_247Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 246.94, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 246.94, noteName: "B3")
    }

    func testDetectE4_330Hz() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 329.63, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let result = detector.detect(samples, sampleRate: defaultSampleRate)
        assertDetectedFrequency(result, expected: 329.63, noteName: "E4")
    }

    // MARK: - Silence Detection Tests

    func testSilenceReturnsNilFrequency() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let silence = generateSilence(sampleCount: defaultFrameSize)

        let result = detector.detect(silence, sampleRate: defaultSampleRate)

        XCTAssertNil(result.frequencyHz, "Should return nil frequency for silence")
        XCTAssertEqual(result.confidence, 0.0, "Confidence should be 0 for silence")
        XCTAssertLessThan(result.rms, 0.001, "RMS should be near zero for silence")
    }

    func testVeryLowAmplitudeReturnsNilFrequency() {
        let detector = PitchDetector(sampleRate: defaultSampleRate, silenceThreshold: 0.01)
        // Generate a sine wave with very low amplitude (below silence threshold)
        let samples = generateSineWave(frequency: 440.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize, amplitude: 0.005)

        let result = detector.detect(samples, sampleRate: defaultSampleRate)

        XCTAssertNil(result.frequencyHz, "Should return nil frequency for very quiet signal")
        XCTAssertEqual(result.confidence, 0.0, "Confidence should be 0 for quiet signal below threshold")
    }

    // MARK: - RMS Calculation Tests

    func testRMSCalculationForSineWave() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let amplitude: Float = 0.5
        let samples = generateSineWave(frequency: 440.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize, amplitude: amplitude)

        let result = detector.detect(samples, sampleRate: defaultSampleRate)

        // RMS of a sine wave = amplitude / sqrt(2) ≈ amplitude * 0.707
        let expectedRMS = Double(amplitude) / sqrt(2.0)
        XCTAssertEqual(result.rms, expectedRMS, accuracy: 0.01, "RMS should match expected value for sine wave")
    }

    // MARK: - Edge Cases

    func testEmptyBufferReturnsNilFrequency() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let empty: [Float] = []

        let result = detector.detect(empty, sampleRate: defaultSampleRate)

        XCTAssertNil(result.frequencyHz, "Should return nil frequency for empty buffer")
        XCTAssertEqual(result.confidence, 0.0, "Confidence should be 0 for empty buffer")
        XCTAssertEqual(result.rms, 0.0, "RMS should be 0 for empty buffer")
    }

    func testBufferTooShortForMinimumFrequency() {
        let detector = PitchDetector(sampleRate: defaultSampleRate, minimumFrequency: 60)
        // For 60 Hz at 44100 sample rate, maxLag = 735 samples
        // Buffer needs to be larger than maxLag
        let tooShort = generateSineWave(frequency: 100.0, sampleRate: defaultSampleRate, sampleCount: 500)

        let result = detector.detect(tooShort, sampleRate: defaultSampleRate)

        XCTAssertNil(result.frequencyHz, "Should return nil frequency for buffer too short")
        XCTAssertEqual(result.confidence, 0.0, "Confidence should be 0 for insufficient buffer")
    }

    // MARK: - Sample Rate Independence Tests

    func testDetectionAt48000Hz() {
        let sampleRate: Double = 48000
        let detector = PitchDetector(sampleRate: sampleRate)
        let samples = generateSineWave(frequency: 440.0, sampleRate: sampleRate, sampleCount: 4096)
        let result = detector.detect(samples, sampleRate: sampleRate)
        assertDetectedFrequency(result, expected: 440.0, noteName: "A4 at 48000 Hz")
    }

    func testDetectionAt44100Hz() {
        let sampleRate: Double = 44100
        let detector = PitchDetector(sampleRate: sampleRate)
        let samples = generateSineWave(frequency: 440.0, sampleRate: sampleRate, sampleCount: 4096)
        let result = detector.detect(samples, sampleRate: sampleRate)
        assertDetectedFrequency(result, expected: 440.0, noteName: "A4 at 44100 Hz")
    }

    // MARK: - Confidence Threshold Tests

    func testLowConfidenceReturnsNilFrequency() {
        // Create a detector with a high confidence threshold
        let detector = PitchDetector(sampleRate: defaultSampleRate, confidenceThreshold: 0.95)
        // Generate noisy signal that won't achieve 95% confidence
        var samples = generateSineWave(frequency: 440.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize, amplitude: 0.3)
        // Add noise
        for i in 0..<samples.count {
            samples[i] += Float.random(in: -0.2...0.2)
        }

        let result = detector.detect(samples, sampleRate: defaultSampleRate)

        // The signal may or may not meet the threshold depending on noise
        // But the result should be consistent - either nil with low confidence, or frequency with high confidence
        if result.frequencyHz != nil {
            XCTAssertGreaterThanOrEqual(result.confidence, 0.95, "If frequency is returned, confidence should meet threshold")
        }
    }

    // MARK: - Legacy API Tests

    func testLegacyDetectPitchMethod() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let samples = generateSineWave(frequency: 440.0, sampleRate: defaultSampleRate, sampleCount: defaultFrameSize)
        let frequency = detector.detectPitch(in: samples)

        XCTAssertNotNil(frequency, "Legacy method should detect frequency")
        XCTAssertEqual(frequency ?? 0, 440.0, accuracy: frequencyAccuracy, "Legacy method should detect A4 at 440 Hz")
    }

    func testLegacyDetectPitchSilence() {
        let detector = PitchDetector(sampleRate: defaultSampleRate)
        let silence = generateSilence(sampleCount: defaultFrameSize)

        let frequency = detector.detectPitch(in: silence)

        XCTAssertNil(frequency, "Legacy method should return nil for silence")
    }

    // MARK: - All Guitar String Frequencies Test

    func testAllStandardGuitarTuningFrequencies() {
        let detector = PitchDetector(sampleRate: defaultSampleRate, minimumFrequency: 60)
        let guitarFrequencies: [(name: String, frequency: Double)] = [
            ("E2", 82.41),
            ("A2", 110.0),
            ("D3", 146.83),
            ("G3", 196.0),
            ("B3", 246.94),
            ("E4", 329.63)
        ]

        for (name, expectedFrequency) in guitarFrequencies {
            // Use larger frame for low frequencies
            let frameSize = expectedFrequency < 100 ? 8192 : 4096
            let samples = generateSineWave(frequency: expectedFrequency, sampleRate: defaultSampleRate, sampleCount: frameSize)

            let result = detector.detect(samples, sampleRate: defaultSampleRate)

            XCTAssertNotNil(result.frequencyHz, "Should detect frequency for \(name)")
            if let detectedFrequency = result.frequencyHz {
                XCTAssertEqual(detectedFrequency, expectedFrequency, accuracy: frequencyAccuracy, "Should detect \(name) at \(expectedFrequency) Hz")
            }
            XCTAssertGreaterThan(result.confidence, 0.7, "Confidence should be high for \(name)")
        }
    }

    // MARK: - Test Helpers

    /// Generates a sine wave at the specified frequency
    private func generateSineWave(
        frequency: Double,
        sampleRate: Double,
        sampleCount: Int,
        amplitude: Float = 1.0
    ) -> [Float] {
        var samples = [Float](repeating: 0, count: sampleCount)
        let angularFrequency = 2.0 * Double.pi * frequency / sampleRate

        for i in 0..<sampleCount {
            samples[i] = amplitude * Float(sin(angularFrequency * Double(i)))
        }

        return samples
    }

    /// Generates a silent buffer (all zeros)
    private func generateSilence(sampleCount: Int) -> [Float] {
        [Float](repeating: 0, count: sampleCount)
    }

    /// Asserts that a pitch detection result matches the expected frequency with high confidence
    private func assertDetectedFrequency(
        _ result: PitchFrame,
        expected: Double,
        noteName: String,
        minimumConfidence: Double = 0.8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(result.frequencyHz, "Should detect a frequency for \(noteName)", file: file, line: line)
        if let frequency = result.frequencyHz {
            XCTAssertEqual(frequency, expected, accuracy: frequencyAccuracy, "Should detect \(noteName) at \(expected) Hz", file: file, line: line)
        }
        XCTAssertGreaterThan(result.confidence, minimumConfidence, "Confidence should be high for \(noteName)", file: file, line: line)
    }
}
