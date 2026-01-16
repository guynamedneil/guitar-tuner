import Foundation

// MARK: - Mock Pitch Source

/// A mock pitch source that directly emits PitchFrame data for testing and UI development
/// without requiring microphone access or pitch detection processing
final class MockPitchSource {
    // MARK: - Properties

    let mode: MockFrequencyGenerator.Mode

    private var isRunning = false
    private var continuation: AsyncStream<PitchFrame>.Continuation?
    private var generatorTask: Task<Void, Never>?

    private let emissionInterval: TimeInterval = 0.05

    // MARK: - Stream

    private(set) lazy var pitchStream: AsyncStream<PitchFrame> = {
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
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        isRunning = true

        AudioLogger.audio.info("Mock pitch source started - mode: \(String(describing: self.mode))")

        generatorTask = Task { [weak self] in
            await self?.generatePitchFrames()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generatorTask?.cancel()
        generatorTask = nil
        continuation?.finish()

        AudioLogger.audio.info("Mock pitch source stopped")
    }

    // MARK: - Pitch Frame Generation

    private func generatePitchFrames() async {
        var time: Double = 0
        let startDate = Date()
        let intervalNanoseconds = UInt64(emissionInterval * 1_000_000_000)

        while isRunning && !Task.isCancelled {
            let frequency = MockFrequencyGenerator.frequency(for: mode, at: time)
            let frame = PitchFrame(
                frequencyHz: frequency,
                confidence: 0.95,
                rms: 0.3,
                timestamp: Date().timeIntervalSince(startDate)
            )
            continuation?.yield(frame)

            time += emissionInterval

            do {
                try await Task.sleep(nanoseconds: intervalNanoseconds)
            } catch {
                break
            }
        }
    }
}
