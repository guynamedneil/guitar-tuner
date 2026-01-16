import Foundation

// MARK: - Mock Audio Input

/// A mock audio input source that generates synthetic audio samples for testing and UI development
/// without requiring microphone access
final class MockAudioInput: AudioInput {
    // MARK: - Properties

    let sampleRate: Double = 44100
    let mode: MockFrequencyGenerator.Mode

    private var isRunning = false
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var generatorTask: Task<Void, Never>?

    private let bufferSize = 4096
    private let emissionInterval: TimeInterval

    // MARK: - Stream

    private(set) lazy var stream: AsyncStream<[Float]> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }()

    // MARK: - Initialization

    init(mode: MockFrequencyGenerator.Mode = .glide) {
        self.mode = mode
        self.emissionInterval = Double(bufferSize) / sampleRate
    }

    // MARK: - AudioInput Protocol

    func start() throws {
        guard !isRunning else { return }
        isRunning = true

        generatorTask = Task { [weak self] in
            await self?.generateSamples()
        }
    }

    func stop() {
        isRunning = false
        generatorTask?.cancel()
        generatorTask = nil
        continuation?.finish()
    }

    // MARK: - Sample Generation

    private func generateSamples() async {
        var phase: Double = 0
        var time: Double = 0
        let intervalNanoseconds = UInt64(emissionInterval * 1_000_000_000)

        while isRunning && !Task.isCancelled {
            let frequency = MockFrequencyGenerator.frequency(for: mode, at: time)
            let samples = generateSineWave(frequency: frequency, phase: &phase)
            continuation?.yield(samples)

            time += emissionInterval

            do {
                try await Task.sleep(nanoseconds: intervalNanoseconds)
            } catch {
                break
            }
        }
    }

    /// Generates a buffer of sine wave samples at the specified frequency
    private func generateSineWave(frequency: Double, phase: inout Double) -> [Float] {
        var samples = [Float](repeating: 0, count: bufferSize)
        let phaseIncrement = 2.0 * .pi * frequency / sampleRate

        for i in 0..<bufferSize {
            samples[i] = Float(sin(phase)) * 0.5
            phase += phaseIncrement
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
        }

        return samples
    }
}
