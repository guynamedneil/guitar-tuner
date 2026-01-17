import Foundation
import Combine

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

    /// Whether audio was interrupted and is waiting to resume
    var isInterrupted: Bool = false

    /// The current audio input mode
    let audioInputMode: AudioInputMode

    /// The current microphone permission status (only relevant for real audio mode)
    var microphonePermissionStatus: MicrophonePermissionStatus = .notDetermined

    // MARK: - Private Properties

    private var pitchSource: MockPitchSource?
    private var listeningTask: Task<Void, Never>?
    private let permissionManager = MicrophonePermissionManager()
    private let audioSessionManager = AudioSessionManager()
    private var audioCapture: AudioCapture?
    private var interruptionCancellable: AnyCancellable?
    private var wasRunningBeforeInterruption: Bool = false

    // MARK: - Initialization

    init(audioInputMode: AudioInputMode = .mockGlide) {
        self.audioInputMode = audioInputMode
        setupInterruptionHandling()
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        interruptionCancellable = audioSessionManager.interruptionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.handleInterruption(state)
                }
            }
    }

    private func handleInterruption(_ state: AudioInterruptionState) {
        switch state {
        case .began:
            wasRunningBeforeInterruption = isAudioRunning
            if isAudioRunning {
                isInterrupted = true
                audioCapture?.pause()
                AudioLogger.audio.info("Tuning paused due to audio interruption")
            }

        case .ended(let shouldResume):
            isInterrupted = false
            if wasRunningBeforeInterruption && shouldResume {
                do {
                    try audioCapture?.resume()
                    AudioLogger.audio.info("Tuning resumed after audio interruption")
                } catch {
                    AudioLogger.audio.error("Failed to resume audio capture: \(error.localizedDescription)")
                    stopTuning()
                }
            }
            wasRunningBeforeInterruption = false
        }
    }

    // MARK: - Actions

    /// Checks the current microphone permission status and updates the state
    func checkMicrophonePermission() {
        guard audioInputMode == .real else { return }
        microphonePermissionStatus = permissionManager.currentStatus
        AudioLogger.audio.info("Microphone permission status: \(String(describing: self.microphonePermissionStatus))")
    }

    /// Requests microphone permission and updates the state
    func requestMicrophonePermission() async {
        microphonePermissionStatus = await permissionManager.requestPermission()
    }

    /// Opens the system Settings app to grant microphone permission
    func openMicrophoneSettings() {
        permissionManager.openSettings()
    }

    /// Starts the tuning session and begins audio capture
    func startTuning() {
        guard !isAudioRunning else { return }

        switch audioInputMode {
        case .real:
            guard microphonePermissionStatus == .granted else {
                AudioLogger.audio.warning("Cannot start tuning - microphone permission not granted")
                return
            }
            startRealAudioTuning()

        case .mockGlide, .mockStepNotes:
            guard let mockMode = audioInputMode.mockMode else { return }
            startMockAudioTuning(mode: mockMode)
        }
    }

    private func startMockAudioTuning(mode: MockFrequencyGenerator.Mode) {
        AudioLogger.audio.info("Tuning session started - mode: \(self.audioInputMode.description)")

        pitchSource = MockPitchSource(mode: mode)
        isAudioRunning = true
        pitchSource?.start()

        listeningTask = Task { [weak self] in
            guard let self, let pitchSource = self.pitchSource else { return }
            for await frame in pitchSource.pitchStream {
                await self.handlePitchFrame(frame)
            }
        }
    }

    private func startRealAudioTuning() {
        AudioLogger.audio.info("Tuning session started - mode: \(self.audioInputMode.description)")

        let capture = AudioCapture(sessionManager: audioSessionManager)
        audioCapture = capture

        do {
            try capture.configureAudioSession()
            try capture.startCapture { [weak self] buffer in
                // TODO: Process audio buffer through pitch detection pipeline
                // For now, this sets up the infrastructure for real audio capture
                _ = buffer
            }
            isAudioRunning = true
        } catch {
            AudioLogger.audio.error("Failed to start real audio tuning: \(error.localizedDescription)")
            audioCapture = nil
        }
    }

    /// Stops the tuning session and ends audio capture
    func stopTuning() {
        guard isAudioRunning || isInterrupted else { return }

        // Stop mock audio if active
        listeningTask?.cancel()
        listeningTask = nil
        pitchSource?.stop()
        pitchSource = nil

        // Stop real audio capture if active
        audioCapture?.stopCapture()
        audioCapture = nil

        isAudioRunning = false
        isInterrupted = false
        wasRunningBeforeInterruption = false
        currentNote = "--"
        centsOffset = 0.0

        AudioLogger.audio.info("Tuning session stopped")
    }

    /// Toggles the tuning session on or off
    func toggleTuning() {
        if isAudioRunning {
            stopTuning()
        } else {
            startTuning()
        }
    }

    /// Handles app lifecycle changes
    /// - Parameter isActive: Whether the app is in the active state
    func handleAppActiveStateChange(isActive: Bool) {
        guard audioInputMode == .real else { return }

        if isActive {
            resumeIfInterrupted()
        } else {
            pauseIfRunning()
        }
    }

    private func resumeIfInterrupted() {
        guard isInterrupted, wasRunningBeforeInterruption else { return }

        do {
            try audioCapture?.resume()
            isInterrupted = false
            AudioLogger.audio.info("Tuning resumed after app became active")
        } catch {
            AudioLogger.audio.error("Failed to resume audio capture on app activation: \(error.localizedDescription)")
            stopTuning()
        }
    }

    private func pauseIfRunning() {
        guard isAudioRunning, !isInterrupted else { return }

        wasRunningBeforeInterruption = true
        isInterrupted = true
        audioCapture?.pause()
        AudioLogger.audio.info("Tuning paused - app became inactive")
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
