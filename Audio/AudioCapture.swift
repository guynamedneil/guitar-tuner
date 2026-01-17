import AVFoundation
import Accelerate
import Combine

// MARK: - Audio Capture

/// Handles microphone audio capture using AVAudioEngine
final class AudioCapture {
    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private let sessionManager: AudioSessionManager
    private let bufferSize: AVAudioFrameCount
    private var cancellables = Set<AnyCancellable>()
    private var isCapturing = false

    /// The sample rate detected from the audio hardware
    private(set) var detectedSampleRate: Double = 44100

    /// Publisher for interruption events that require UI response
    let interruptionPublisher: AnyPublisher<AudioInterruptionEvent, Never>

    /// Publisher for route change events
    let routeChangePublisher: AnyPublisher<AudioRouteChangeEvent, Never>

    // MARK: - Initialization

    /// Creates an audio capture instance with the specified session manager
    /// - Parameters:
    ///   - sessionManager: The audio session manager to use for session configuration
    ///   - bufferSize: The size of each capture buffer (default: 4096)
    init(sessionManager: AudioSessionManager = AudioSessionManager(), bufferSize: Int = 4096) {
        self.sessionManager = sessionManager
        self.bufferSize = AVAudioFrameCount(bufferSize)
        self.interruptionPublisher = sessionManager.interruptionPublisher.eraseToAnyPublisher()
        self.routeChangePublisher = sessionManager.routeChangePublisher.eraseToAnyPublisher()

        setupInternalInterruptionHandling()
    }

    // MARK: - Configuration

    /// Configures the audio session for recording with measurement mode
    func configureAudioSession() throws {
        try sessionManager.configure()
    }

    /// Activates the audio session
    func activateAudioSession() throws {
        try sessionManager.activate()
    }

    /// Deactivates the audio session
    func deactivateAudioSession() {
        sessionManager.deactivate()
    }

    // MARK: - Capture Control

    /// Starts capturing audio from the microphone
    /// - Parameter bufferHandler: Closure called with each audio buffer
    func startCapture(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isCapturing else {
            AudioLogger.audio.debug("Audio capture already running")
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        detectedSampleRate = format.sampleRate

        // Validate that we have a usable audio format
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            AudioLogger.audio.error("Invalid audio format - sampleRate: \(format.sampleRate), channels: \(format.channelCount)")
            throw AudioSessionError.inputNotAvailable
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            bufferHandler(buffer)
        }

        try audioEngine.start()
        isCapturing = true

        AudioLogger.audio.info("Audio capture started - sampleRate: \(format.sampleRate, format: .fixed(precision: 0)) Hz, channels: \(format.channelCount)")
    }

    /// Starts capturing audio from the microphone and converts to mono float samples
    /// - Parameter sampleHandler: Closure called with mono float samples for each buffer
    func startCapture(sampleHandler: @escaping ([Float]) -> Void) throws {
        try startCapture { buffer in
            let samples = Self.extractMonoSamples(from: buffer)
            sampleHandler(samples)
        }
    }

    /// Extracts mono float samples from an AVAudioPCMBuffer
    /// - Parameter buffer: The audio buffer to extract samples from
    /// - Returns: An array of mono float samples
    static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        // Convert stereo/multi-channel to mono by averaging
        var monoSamples = [Float](repeating: 0, count: frameLength)

        monoSamples.withUnsafeMutableBufferPointer { monoPtr in
            vDSP_mmov(channelData[0], monoPtr.baseAddress!, vDSP_Length(frameLength), 1, vDSP_Length(frameLength), 1)

            for channel in 1..<channelCount {
                vDSP_vadd(monoPtr.baseAddress!, 1, channelData[channel], 1, monoPtr.baseAddress!, 1, vDSP_Length(frameLength))
            }

            var divisor = Float(channelCount)
            vDSP_vsdiv(monoPtr.baseAddress!, 1, &divisor, monoPtr.baseAddress!, 1, vDSP_Length(frameLength))
        }

        return monoSamples
    }

    /// Stops audio capture and removes the tap
    func stopCapture() {
        guard isCapturing else {
            AudioLogger.audio.debug("Audio capture not running")
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false

        AudioLogger.audio.info("Audio capture stopped")
    }

    /// Pauses the audio engine without removing the tap
    func pause() {
        audioEngine.pause()
        AudioLogger.audio.info("Audio capture paused")
    }

    /// Resumes the audio engine after being paused
    func resume() throws {
        try audioEngine.start()
        AudioLogger.audio.info("Audio capture resumed")
    }

    // MARK: - Internal Interruption Handling

    private func setupInternalInterruptionHandling() {
        sessionManager.interruptionPublisher
            .sink { [weak self] event in
                self?.handleInterruption(event)
            }
            .store(in: &cancellables)

        sessionManager.routeChangePublisher
            .sink { [weak self] event in
                self?.handleRouteChange(event)
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ event: AudioInterruptionEvent) {
        switch event {
        case .began:
            guard isCapturing else { return }
            audioEngine.pause()
            AudioLogger.audio.info("Audio engine paused due to interruption")

        case .ended(let shouldResume):
            guard isCapturing, shouldResume else { return }
            do {
                try sessionManager.activate()
                try audioEngine.start()
                AudioLogger.audio.info("Audio engine resumed after interruption")
            } catch {
                AudioLogger.audio.error("Failed to resume audio engine after interruption: \(error.localizedDescription)")
            }
        }
    }

    private func handleRouteChange(_ event: AudioRouteChangeEvent) {
        guard event.requiresReconfiguration, isCapturing else { return }
        AudioLogger.audio.warning("Route change requires reconfiguration - stopping capture")
        stopCapture()
    }
}
