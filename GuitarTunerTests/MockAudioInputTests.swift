import XCTest
@testable import GuitarTuner

final class MockAudioInputTests: XCTestCase {

    // MARK: - MockAudioInput Tests

    func testMockAudioInputSampleRate() {
        let mockInput = MockAudioInput(mode: .glide)
        XCTAssertEqual(mockInput.sampleRate, 44100)
    }

    func testMockAudioInputEmitsSamples() async throws {
        let mockInput = MockAudioInput(mode: .glide)
        try mockInput.start()

        var receivedSamples = false
        let stream = mockInput.stream

        let task = Task {
            for await samples in stream {
                XCTAssertEqual(samples.count, 4096, "Buffer should contain 4096 samples")
                receivedSamples = true
                break
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        mockInput.stop()

        XCTAssertTrue(receivedSamples, "Should have received at least one sample buffer")
    }

    func testMockAudioInputStopEndsStream() async throws {
        let mockInput = MockAudioInput(mode: .glide)
        try mockInput.start()

        try await Task.sleep(nanoseconds: 100_000_000)
        mockInput.stop()

        var streamEnded = false
        for await _ in mockInput.stream {
            break
        }
        streamEnded = true

        XCTAssertTrue(streamEnded, "Stream should end after stop is called")
    }

    // MARK: - MockPitchSource Tests

    func testMockPitchSourceEmitsPitchFrames() async throws {
        let pitchSource = MockPitchSource(mode: .glide)
        pitchSource.start()

        var receivedFrame = false

        let task = Task {
            for await frame in pitchSource.pitchStream {
                XCTAssertNotNil(frame.frequencyHz, "Frequency should not be nil")
                XCTAssertGreaterThan(frame.confidence, 0, "Confidence should be positive")
                receivedFrame = true
                break
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        pitchSource.stop()

        XCTAssertTrue(receivedFrame, "Should have received at least one pitch frame")
    }

    func testMockPitchSourceGlideModeFrequencyRange() async throws {
        let pitchSource = MockPitchSource(mode: .glide)
        pitchSource.start()

        var frequencies: [Double] = []

        let task = Task {
            for await frame in pitchSource.pitchStream {
                if let freq = frame.frequencyHz {
                    frequencies.append(freq)
                }
                if frequencies.count >= 10 {
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: 600_000_000)
        task.cancel()
        pitchSource.stop()

        for freq in frequencies {
            XCTAssertGreaterThanOrEqual(freq, 430.0, "Glide frequency should be >= 430 Hz")
            XCTAssertLessThanOrEqual(freq, 450.0, "Glide frequency should be <= 450 Hz")
        }
    }

    func testMockPitchSourceStepModeEmitsGuitarNoteFrequencies() async throws {
        let pitchSource = MockPitchSource(mode: .stepNotes)
        pitchSource.start()

        var receivedFrequency: Double?

        let task = Task {
            for await frame in pitchSource.pitchStream {
                receivedFrequency = frame.frequencyHz
                break
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        pitchSource.stop()

        guard let freq = receivedFrequency else {
            XCTFail("Should have received a frequency")
            return
        }

        let guitarFrequencies = Note.standardGuitarTuning.map { $0.frequency }
        let isGuitarNote = guitarFrequencies.contains { abs($0 - freq) < 0.01 }
        XCTAssertTrue(isGuitarNote, "Step mode should emit guitar note frequencies")
    }

    func testMockPitchSourceStopEndsStream() async throws {
        let pitchSource = MockPitchSource(mode: .glide)
        pitchSource.start()

        try await Task.sleep(nanoseconds: 100_000_000)
        pitchSource.stop()

        var streamEnded = false
        for await _ in pitchSource.pitchStream {
            break
        }
        streamEnded = true

        XCTAssertTrue(streamEnded, "Stream should end after stop is called")
    }
}
