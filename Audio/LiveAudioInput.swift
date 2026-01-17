import AVFoundation

// MARK: - Live Audio Input

/// Real microphone audio input source that implements the AudioInput protocol.
/// Uses AVAudioEngine to capture audio and provides samples through an async stream.
final class LiveAudioInput: AudioInput {
    // MARK: - Properties

    /// The sample rate detected from the audio hardware
    private(set) var sampleRate: Double = 44100

    /// The ring buffer for storing audio samples
    private let sampleBuffer: SampleBuffer

    /// The number of buffer underruns that have occurred
    var underrunCount: Int {
        sampleBuffer.underrunCount
    }

    // MARK: - Private Properties

    private let audioEngine = AVAudioEngine()
    private let sessionManager: AudioSessionManager
    private let bufferSize: Int
    private let frameSize: Int
    private var isRunning = false
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var frameEmissionTask: Task<Void, Never>?

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

    /// Creates a new live audio input with the specified configuration
    /// - Parameters:
    ///   - sessionManager: The audio session manager for session configuration
    ///   - bufferCapacity: The capacity of the ring buffer in samples (default: 16384)
    ///   - bufferSize: The size of each capture buffer from AVAudioEngine (default: 1024)
    ///   - frameSize: The number of samples to emit per frame (default: 4096)
    init(
        sessionManager: AudioSessionManager,
        bufferCapacity: Int = 16384,
        bufferSize: Int = 1024,
        frameSize: Int = 4096
    ) {
        self.sessionManager = sessionManager
        self.sampleBuffer = SampleBuffer(capacity: bufferCapacity)
        self.bufferSize = bufferSize
        self.frameSize = frameSize
    }

    // MARK: - AudioInput Protocol

    func start() throws {
        guard !isRunning else { return }

        try sessionManager.configureSession()
        try sessionManager.activateSession()

        sampleRate = sessionManager.currentSampleRate

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(bufferSize),
            format: hardwareFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        try audioEngine.start()
        isRunning = true

        startFrameEmission()

        AudioLogger.audio.info("Live audio input started - sampleRate: \(self.sampleRate, format: .fixed(precision: 0)) Hz, bufferSize: \(self.bufferSize), frameSize: \(self.frameSize)")
    }

    func stop() {
        guard isRunning else { return }

        frameEmissionTask?.cancel()
        frameEmissionTask = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        sampleBuffer.reset()
        continuation?.finish()
        isRunning = false

        AudioLogger.audio.info("Live audio input stopped")
    }

    /// Pauses the audio engine without removing the tap
    func pause() {
        audioEngine.pause()
        frameEmissionTask?.cancel()
        frameEmissionTask = nil
        AudioLogger.audio.info("Live audio input paused")
    }

    /// Resumes the audio engine after being paused
    func resume() throws {
        try audioEngine.start()
        startFrameEmission()
        AudioLogger.audio.info("Live audio input resumed")
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let monoSamples = AudioCapture.extractMonoSamples(from: buffer)
        guard !monoSamples.isEmpty else { return }
        sampleBuffer.write(monoSamples)
    }

    private func startFrameEmission() {
        let emissionInterval = Double(frameSize) / sampleRate
        let intervalNanoseconds = UInt64(emissionInterval * 1_000_000_000)

        frameEmissionTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && self.isRunning {
                if let samples = self.sampleBuffer.read(self.frameSize) {
                    self.continuation?.yield(samples)
                }

                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }
}
