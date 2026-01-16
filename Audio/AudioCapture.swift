import AVFoundation
import Combine

// MARK: - Audio Capture

/// Handles microphone audio capture using AVAudioEngine
final class AudioCapture {
    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private let sessionManager: AudioSessionManager
    private var cancellables = Set<AnyCancellable>()
    private var isCapturing = false

    /// Publisher for interruption events that require UI response
    let interruptionPublisher: AnyPublisher<AudioInterruptionEvent, Never>

    /// Publisher for route change events
    let routeChangePublisher: AnyPublisher<AudioRouteChangeEvent, Never>

    // MARK: - Initialization

    init(sessionManager: AudioSessionManager = AudioSessionManager()) {
        self.sessionManager = sessionManager
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

        // Validate that we have a usable audio format
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            AudioLogger.audio.error("Invalid audio format - sampleRate: \(format.sampleRate), channels: \(format.channelCount)")
            throw AudioSessionError.inputNotAvailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            bufferHandler(buffer)
        }

        try audioEngine.start()
        isCapturing = true

        AudioLogger.audio.info("Audio capture started - sampleRate: \(format.sampleRate, format: .fixed(precision: 0)) Hz, channels: \(format.channelCount)")
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
