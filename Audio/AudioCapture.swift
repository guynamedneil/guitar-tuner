import AVFoundation

// MARK: - Audio Capture

/// Handles microphone audio capture using AVAudioEngine
final class AudioCapture {
    private let audioEngine = AVAudioEngine()
    private let sessionManager: AudioSessionManager

    /// Creates an audio capture instance with the specified session manager
    /// - Parameter sessionManager: The audio session manager to use for session configuration
    init(sessionManager: AudioSessionManager) {
        self.sessionManager = sessionManager
    }

    /// Configures and activates the audio session for recording
    func configureAudioSession() throws {
        try sessionManager.configureSession()
        try sessionManager.activateSession()
    }

    /// Starts capturing audio from the microphone
    /// - Parameter bufferHandler: Closure called with each audio buffer
    func startCapture(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            bufferHandler(buffer)
        }

        try audioEngine.start()

        AudioLogger.audio.info("Audio capture started - sampleRate: \(format.sampleRate, format: .fixed(precision: 0)) Hz, channels: \(format.channelCount)")
    }

    /// Stops audio capture and removes the tap
    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

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
}
