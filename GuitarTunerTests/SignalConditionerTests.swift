import XCTest
@testable import GuitarTuner

final class SignalConditionerTests: XCTestCase {

    // MARK: - DC Offset Removal Tests

    func testDCOffsetRemoval_RemovesDCOffset() {
        let conditioner = SignalConditioner(config: .none)
        let dcOffset: Float = 0.5
        let samples: [Float] = [0.1 + dcOffset, 0.2 + dcOffset, -0.1 + dcOffset, -0.2 + dcOffset]

        let result = conditioner.removeDCOffset(samples)

        // Mean should be approximately zero after DC removal
        let mean = result.reduce(0, +) / Float(result.count)
        XCTAssertEqual(mean, 0.0, accuracy: 0.0001, "Mean should be approximately zero after DC removal")
    }

    func testDCOffsetRemoval_PreservesSignalShape() {
        let conditioner = SignalConditioner(config: .none)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]

        let result = conditioner.removeDCOffset(samples)

        // The differences between consecutive samples should be preserved
        for i in 1..<samples.count {
            let originalDiff = samples[i] - samples[i - 1]
            let resultDiff = result[i] - result[i - 1]
            XCTAssertEqual(originalDiff, resultDiff, accuracy: 0.0001, "Signal shape should be preserved")
        }
    }

    func testDCOffsetRemoval_ZeroMeanSignalUnchanged() {
        let conditioner = SignalConditioner(config: .none)
        let samples: [Float] = [-1.0, 1.0, -1.0, 1.0]

        let result = conditioner.removeDCOffset(samples)

        for i in 0..<samples.count {
            XCTAssertEqual(result[i], samples[i], accuracy: 0.0001, "Zero-mean signal should remain unchanged")
        }
    }

    func testDCOffsetRemoval_EmptyArrayReturnsEmpty() {
        let conditioner = SignalConditioner(config: .none)
        let samples: [Float] = []

        let result = conditioner.removeDCOffset(samples)

        XCTAssertTrue(result.isEmpty, "Empty array should return empty array")
    }

    // MARK: - Pre-emphasis Filter Tests

    func testPreEmphasis_AppliesFilter() {
        let conditioner = SignalConditioner(config: .none)
        let coefficient: Float = 0.97
        let samples: [Float] = [1.0, 1.0, 1.0, 1.0]

        let result = conditioner.applyPreEmphasis(samples, coefficient: coefficient)

        // First sample should be unchanged
        XCTAssertEqual(result[0], samples[0], accuracy: 0.0001, "First sample should be unchanged")

        // Subsequent samples should be: x[n] - 0.97 * x[n-1]
        for i in 1..<samples.count {
            let expected = samples[i] - coefficient * samples[i - 1]
            XCTAssertEqual(result[i], expected, accuracy: 0.0001, "Pre-emphasis formula should be applied correctly")
        }
    }

    func testPreEmphasis_EnhancesHighFrequencies() {
        let conditioner = SignalConditioner(config: .none)
        let coefficient: Float = 0.97

        // Low frequency signal (slow changes)
        let lowFreq: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4]
        // High frequency signal (fast changes)
        let highFreq: [Float] = [0.0, 0.5, 0.0, 0.5, 0.0]

        let lowResult = conditioner.applyPreEmphasis(lowFreq, coefficient: coefficient)
        let highResult = conditioner.applyPreEmphasis(highFreq, coefficient: coefficient)

        // Calculate energy (sum of squares) for each
        let lowEnergy = lowResult.map { $0 * $0 }.reduce(0, +)
        let highEnergy = highResult.map { $0 * $0 }.reduce(0, +)

        // High frequency should have relatively more energy after pre-emphasis
        let originalLowEnergy = lowFreq.map { $0 * $0 }.reduce(0, +)
        let originalHighEnergy = highFreq.map { $0 * $0 }.reduce(0, +)

        let lowRatio = lowEnergy / originalLowEnergy
        let highRatio = highEnergy / originalHighEnergy

        XCTAssertGreaterThan(highRatio, lowRatio, "Pre-emphasis should enhance high frequencies more than low frequencies")
    }

    func testPreEmphasis_SingleSampleReturnsUnchanged() {
        let conditioner = SignalConditioner(config: .none)
        let samples: [Float] = [0.5]

        let result = conditioner.applyPreEmphasis(samples, coefficient: 0.97)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], samples[0], accuracy: 0.0001)
    }

    func testPreEmphasis_EmptyArrayReturnsEmpty() {
        let conditioner = SignalConditioner(config: .none)
        let samples: [Float] = []

        let result = conditioner.applyPreEmphasis(samples, coefficient: 0.97)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Window Function Tests

    func testHannWindow_CorrectShape() {
        let window = SignalConditioner.createHannWindow(size: 100)

        XCTAssertEqual(window.count, 100)

        // Hann window should taper to near-zero at edges
        XCTAssertLessThan(window[0], 0.01, "Hann window should start near zero")
        XCTAssertLessThan(window[99], 0.01, "Hann window should end near zero")

        // Hann window should peak in the middle
        let middleValue = window[50]
        XCTAssertGreaterThan(middleValue, 0.9, "Hann window should peak near 1.0 in the middle")
    }

    func testHammingWindow_CorrectShape() {
        let window = SignalConditioner.createHammingWindow(size: 100)

        XCTAssertEqual(window.count, 100)

        // Hamming window has non-zero edges (approximately 0.08)
        XCTAssertGreaterThan(window[0], 0.05, "Hamming window should have non-zero start")
        XCTAssertLessThan(window[0], 0.15, "Hamming window start should be small")

        // Hamming window should peak in the middle
        let middleValue = window[50]
        XCTAssertGreaterThan(middleValue, 0.9, "Hamming window should peak near 1.0 in the middle")
    }

    func testApplyWindow_TapersEdges() {
        var conditioner = SignalConditioner(config: .none)
        let samples = [Float](repeating: 1.0, count: 100)

        let result = conditioner.applyWindow(samples, type: .hann)

        // Edges should be near zero
        XCTAssertLessThan(result[0], 0.01, "Windowed signal should taper to near zero at start")
        XCTAssertLessThan(result[99], 0.01, "Windowed signal should taper to near zero at end")

        // Middle should be near original
        XCTAssertGreaterThan(result[50], 0.9, "Windowed signal should preserve middle values")
    }

    func testApplyWindow_EmptyArrayReturnsEmpty() {
        var conditioner = SignalConditioner(config: .none)
        let samples: [Float] = []

        let result = conditioner.applyWindow(samples, type: .hann)

        XCTAssertTrue(result.isEmpty)
    }

    func testCreateWindow_ZeroSizeReturnsEmpty() {
        let window = SignalConditioner.createHannWindow(size: 0)
        XCTAssertTrue(window.isEmpty)
    }

    // MARK: - Full Conditioning Pipeline Tests

    func testCondition_AppliesAllSteps() {
        let config = SignalConditionerConfig(
            removeDCOffset: true,
            applyPreEmphasis: true,
            preEmphasisCoefficient: 0.97,
            applyWindow: true,
            windowType: .hann
        )
        var conditioner = SignalConditioner(config: config)

        // Signal with DC offset
        let dcOffset: Float = 0.5
        var samples = [Float](repeating: 0, count: 100)
        for i in 0..<100 {
            samples[i] = dcOffset + Float(sin(Double(i) * 0.1))
        }

        let result = conditioner.condition(samples)

        // Result should be windowed (tapered at edges)
        XCTAssertLessThan(abs(result[0]), 0.1, "Conditioned signal should be tapered at start")
        XCTAssertLessThan(abs(result[99]), 0.1, "Conditioned signal should be tapered at end")
    }

    func testCondition_NoneConfigReturnsOriginal() {
        var conditioner = SignalConditioner(config: .none)
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

        let result = conditioner.condition(samples)

        for i in 0..<samples.count {
            XCTAssertEqual(result[i], samples[i], accuracy: 0.0001, "No conditioning should return original samples")
        }
    }

    func testCondition_EmptyArrayReturnsEmpty() {
        var conditioner = SignalConditioner(config: .default)
        let samples: [Float] = []

        let result = conditioner.condition(samples)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Configuration Tests

    func testDefaultConfig_HasExpectedValues() {
        let config = SignalConditionerConfig.default

        XCTAssertTrue(config.removeDCOffset)
        XCTAssertTrue(config.applyPreEmphasis)
        XCTAssertEqual(config.preEmphasisCoefficient, 0.97, accuracy: 0.001)
        XCTAssertTrue(config.applyWindow)
    }

    func testNoneConfig_HasExpectedValues() {
        let config = SignalConditionerConfig.none

        XCTAssertFalse(config.removeDCOffset)
        XCTAssertFalse(config.applyPreEmphasis)
        XCTAssertFalse(config.applyWindow)
    }

    // MARK: - Window Caching Tests

    func testWindowCaching_ReusesCachedWindow() {
        var conditioner = SignalConditioner(config: .default)
        let samples1 = [Float](repeating: 1.0, count: 100)
        let samples2 = [Float](repeating: 0.5, count: 100)

        // Apply window twice with same size
        let result1 = conditioner.applyWindow(samples1, type: .hann)
        let result2 = conditioner.applyWindow(samples2, type: .hann)

        // Results should use the same window coefficients
        // result2 should be half of result1 since samples2 is half of samples1
        for i in 0..<100 {
            XCTAssertEqual(result2[i], result1[i] * 0.5, accuracy: 0.0001, "Cached window should produce consistent results")
        }
    }
}
