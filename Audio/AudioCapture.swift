import AVFoundation

// MARK: - Audio Capture

/// Handles microphone audio capture using AVAudioEngine
final class AudioCapture {
    private let audioEngine = AVAudioEngine()

    /// Configures the audio session for recording
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
        try session.setActive(true)
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
    }

    /// Stops audio capture and removes the tap
    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
