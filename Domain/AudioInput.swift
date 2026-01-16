import Foundation

// MARK: - Audio Input

/// Protocol for audio input sources that provide a stream of audio samples
protocol AudioInput {
    /// Starts the audio capture
    /// - Throws: An error if audio capture cannot be started
    func start() throws

    /// Stops the audio capture
    func stop()

    /// The sample rate of the audio input in Hz
    var sampleRate: Double { get }

    /// An async stream of audio sample buffers
    var stream: AsyncStream<[Float]> { get }
}
