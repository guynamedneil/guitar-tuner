import AVFoundation
import Accelerate

// MARK: - Audio Capture

/// Handles microphone audio capture using AVAudioEngine
final class AudioCapture {
    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private let sessionManager: AudioSessionManager
    private let bufferSize: AVAudioFrameCount

    /// The sample rate detected from the audio hardware
    private(set) var detectedSampleRate: Double = 44100

    // MARK: - Initialization

    /// Creates an audio capture instance with the specified session manager
    /// - Parameters:
    ///   - sessionManager: The audio session manager to use for session configuration
    ///   - bufferSize: The size of each capture buffer (default: 4096)
    init(sessionManager: AudioSessionManager, bufferSize: Int = 4096) {
        self.sessionManager = sessionManager
        self.bufferSize = AVAudioFrameCount(bufferSize)
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
        detectedSampleRate = format.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            bufferHandler(buffer)
        }

        try audioEngine.start()

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
