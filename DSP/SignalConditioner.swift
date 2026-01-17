import Accelerate
import Foundation

// MARK: - Window Type

/// Available window functions for signal conditioning
enum WindowType {
    case hann
    case hamming
}

// MARK: - Signal Conditioner Configuration

/// Configuration options for signal conditioning
struct SignalConditionerConfig {
    /// Whether to remove DC offset from the signal
    var removeDCOffset: Bool

    /// Whether to apply pre-emphasis filtering
    var applyPreEmphasis: Bool

    /// Pre-emphasis filter coefficient (typically 0.95-0.97)
    var preEmphasisCoefficient: Float

    /// Whether to apply a window function
    var applyWindow: Bool

    /// Type of window function to apply
    var windowType: WindowType

    /// Default configuration with all conditioning enabled
    static let `default` = SignalConditionerConfig(
        removeDCOffset: true,
        applyPreEmphasis: true,
        preEmphasisCoefficient: 0.97,
        applyWindow: true,
        windowType: .hann
    )

    /// Configuration with no conditioning applied
    static let none = SignalConditionerConfig(
        removeDCOffset: false,
        applyPreEmphasis: false,
        preEmphasisCoefficient: 0.97,
        applyWindow: false,
        windowType: .hann
    )

    init(
        removeDCOffset: Bool = true,
        applyPreEmphasis: Bool = true,
        preEmphasisCoefficient: Float = 0.97,
        applyWindow: Bool = true,
        windowType: WindowType = .hann
    ) {
        self.removeDCOffset = removeDCOffset
        self.applyPreEmphasis = applyPreEmphasis
        self.preEmphasisCoefficient = preEmphasisCoefficient
        self.applyWindow = applyWindow
        self.windowType = windowType
    }
}

// MARK: - Signal Conditioner

/// Applies signal conditioning to audio samples before pitch detection
struct SignalConditioner {
    let config: SignalConditionerConfig

    /// Cache for window arrays to avoid regeneration
    private var windowCache: [Int: [Float]] = [:]

    init(config: SignalConditionerConfig = .default) {
        self.config = config
    }

    /// Applies all configured conditioning steps to the input samples
    /// - Parameter samples: Input audio samples
    /// - Returns: Conditioned audio samples
    mutating func condition(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var output = samples

        if config.removeDCOffset {
            output = removeDCOffset(output)
        }

        if config.applyPreEmphasis {
            output = applyPreEmphasis(output, coefficient: config.preEmphasisCoefficient)
        }

        if config.applyWindow {
            output = applyWindow(output, type: config.windowType)
        }

        return output
    }

    // MARK: - DC Offset Removal

    /// Removes DC offset from the signal by subtracting the mean
    /// - Parameter samples: Input audio samples
    /// - Returns: Samples with DC offset removed
    func removeDCOffset(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))

        var output = [Float](repeating: 0, count: samples.count)
        var negativeMean = -mean
        vDSP_vsadd(samples, 1, &negativeMean, &output, 1, vDSP_Length(samples.count))

        return output
    }

    // MARK: - Pre-emphasis Filter

    /// Applies pre-emphasis filter to enhance high frequencies
    /// Formula: y[n] = x[n] - α * x[n-1]
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - coefficient: Pre-emphasis coefficient (typically 0.95-0.97)
    /// - Returns: Pre-emphasized samples
    func applyPreEmphasis(_ samples: [Float], coefficient: Float) -> [Float] {
        guard samples.count > 1 else { return samples }

        var output = [Float](repeating: 0, count: samples.count)
        output[0] = samples[0]

        // y[n] = x[n] - α * x[n-1]
        // Vectorized: create delayed version and subtract
        var delayed = [Float](repeating: 0, count: samples.count)
        delayed[0] = 0
        for i in 1..<samples.count {
            delayed[i] = samples[i - 1]
        }

        // Scale delayed by coefficient
        var scaledDelayed = [Float](repeating: 0, count: samples.count)
        var coeff = coefficient
        vDSP_vsmul(delayed, 1, &coeff, &scaledDelayed, 1, vDSP_Length(samples.count))

        // Subtract: output = samples - scaledDelayed
        vDSP_vsub(scaledDelayed, 1, samples, 1, &output, 1, vDSP_Length(samples.count))

        return output
    }

    // MARK: - Window Functions

    /// Applies a window function to the samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - type: Type of window function to apply
    /// - Returns: Windowed samples
    mutating func applyWindow(_ samples: [Float], type: WindowType) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let window = getOrCreateWindow(size: samples.count, type: type)

        var output = [Float](repeating: 0, count: samples.count)
        vDSP_vmul(samples, 1, window, 1, &output, 1, vDSP_Length(samples.count))

        return output
    }

    /// Creates a Hann window of the specified size
    /// - Parameter size: Number of samples in the window
    /// - Returns: Hann window coefficients
    static func createHannWindow(size: Int) -> [Float] {
        guard size > 0 else { return [] }

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        return window
    }

    /// Creates a Hamming window of the specified size
    /// - Parameter size: Number of samples in the window
    /// - Returns: Hamming window coefficients
    static func createHammingWindow(size: Int) -> [Float] {
        guard size > 0 else { return [] }

        var window = [Float](repeating: 0, count: size)
        vDSP_hamm_window(&window, vDSP_Length(size), 0)

        return window
    }

    // MARK: - Private Helpers

    /// Gets a cached window or creates a new one
    private mutating func getOrCreateWindow(size: Int, type: WindowType) -> [Float] {
        let cacheKey = size

        if let cached = windowCache[cacheKey] {
            return cached
        }

        let window: [Float]
        switch type {
        case .hann:
            window = SignalConditioner.createHannWindow(size: size)
        case .hamming:
            window = SignalConditioner.createHammingWindow(size: size)
        }

        windowCache[cacheKey] = window
        return window
    }
}
