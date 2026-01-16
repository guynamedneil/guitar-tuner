import Foundation

// MARK: - Tuner ViewModel

/// ViewModel for the tuner screen that manages tuner state and coordinates with the audio pipeline
@MainActor
@Observable
final class TunerViewModel {
    // MARK: - State Properties

    /// The currently detected note name (e.g., "A", "E", "G#"), or "--" when no note is detected
    var currentNote: String = "--"

    /// The deviation from the target note in cents (-50 to +50)
    var centsOffset: Double = 0.0

    /// Whether the audio capture is currently running
    var isAudioRunning: Bool = false

    /// The current audio input mode
    let audioInputMode: AudioInputMode

    // MARK: - Private Properties

    private var pitchSource: MockPitchSource?
    private var listeningTask: Task<Void, Never>?

    // MARK: - Initialization

    init(audioInputMode: AudioInputMode = .mockGlide) {
        self.audioInputMode = audioInputMode
    }

    // MARK: - Actions

    /// Starts the tuning session and begins audio capture
    func startTuning() {
        guard !isAudioRunning else { return }

        guard let mockMode = audioInputMode.mockMode else {
            print("[TunerViewModel] Real audio mode not yet implemented")
            return
        }

        pitchSource = MockPitchSource(mode: mockMode)
        isAudioRunning = true
        pitchSource?.start()

        listeningTask = Task { [weak self] in
            guard let self, let pitchSource = self.pitchSource else { return }
            for await frame in pitchSource.pitchStream {
                await self.handlePitchFrame(frame)
            }
        }
    }

    /// Stops the tuning session and ends audio capture
    func stopTuning() {
        listeningTask?.cancel()
        listeningTask = nil
        pitchSource?.stop()
        pitchSource = nil
        isAudioRunning = false
        currentNote = "--"
        centsOffset = 0.0
    }

    /// Toggles the tuning session on or off
    func toggleTuning() {
        if isAudioRunning {
            stopTuning()
        } else {
            startTuning()
        }
    }

    // MARK: - Pitch Processing

    private func handlePitchFrame(_ frame: PitchFrame) {
        guard let frequency = frame.frequencyHz, frame.confidence > 0.5 else {
            currentNote = "--"
            centsOffset = 0.0
            return
        }

        let (note, cents) = findClosestNote(to: frequency)
        currentNote = note.name
        centsOffset = cents.clamped(to: -50...50)
    }

    /// Finds the closest note to a given frequency and returns the cents offset
    private func findClosestNote(to frequency: Double) -> (note: Note, cents: Double) {
        let allNotes = generateAllNotes()

        let closestNote = allNotes.min { noteA, noteB in
            abs(GuitarTuner.centsOffset(from: frequency, to: noteA.frequency)) <
                abs(GuitarTuner.centsOffset(from: frequency, to: noteB.frequency))
        } ?? allNotes[0]

        let cents = GuitarTuner.centsOffset(from: frequency, to: closestNote.frequency)
        return (closestNote, cents)
    }

    /// Generates all chromatic notes across relevant octaves for guitar tuning
    private func generateAllNotes() -> [Note] {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let a4Frequency = 440.0

        return (1...6).flatMap { octave in
            noteNames.enumerated().compactMap { index, name in
                let semitonesFromA4 = (octave - 4) * 12 + (index - 9)
                let frequency = a4Frequency * pow(2.0, Double(semitonesFromA4) / 12.0)

                guard frequency >= 60 && frequency <= 1200 else { return nil }
                return Note(name: name, octave: octave, frequency: frequency)
            }
        }
    }
}

// MARK: - Comparable Clamping Extension

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
