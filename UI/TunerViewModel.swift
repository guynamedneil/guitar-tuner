import AVFoundation
import Combine
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

    /// Whether the audio session is interrupted (phone call, Siri, etc.)
    var isInterrupted: Bool = false

    /// The current audio input mode
    let audioInputMode: AudioInputMode

    /// The current microphone permission status (only relevant for real audio mode)
    var microphonePermissionStatus: MicrophonePermissionStatus = .notDetermined

    // MARK: - Private Properties

    private var pitchSource: MockPitchSource?
    private var audioCapture: AudioCapture?
    private var pitchDetector: PitchDetector?
    private var listeningTask: Task<Void, Never>?
    private let permissionManager = MicrophonePermissionManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(audioInputMode: AudioInputMode = .mockGlide) {
        self.audioInputMode = audioInputMode
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

        guard let mockMode = audioInputMode.mockMode else {
            // Real audio mode
            startRealAudioCapture()
            return
        }

        // Mock audio mode
        AudioLogger.audio.info("Tuning session started - mode: \(self.audioInputMode.description)")

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

    /// Starts real audio capture from the microphone
    private func startRealAudioCapture() {
        guard microphonePermissionStatus == .granted else {
            AudioLogger.audio.warning("Cannot start tuning - microphone permission not granted")
            return
        }

        AudioLogger.audio.info("Tuning session started - mode: real audio")

        do {
            let capture = AudioCapture()
            self.audioCapture = capture

            setupInterruptionHandling(for: capture)

            try capture.configureAudioSession()
            try capture.activateAudioSession()

            let detector = PitchDetector()
            self.pitchDetector = detector

            try capture.startCapture { [weak self] buffer in
                guard let self else { return }
                if let frame = self.pitchDetector?.process(buffer: buffer) {
                    Task { @MainActor [weak self] in
                        self?.handlePitchFrame(frame)
                    }
                }
            }

            isAudioRunning = true
        } catch {
            AudioLogger.audio.error("Failed to start real audio capture: \(error.localizedDescription)")
            cleanupRealAudioCapture()
        }
    }

    /// Sets up interruption handling for the audio capture
    private func setupInterruptionHandling(for capture: AudioCapture) {
        capture.interruptionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleInterruption(event)
            }
            .store(in: &cancellables)

        capture.routeChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleRouteChange(event)
            }
            .store(in: &cancellables)
    }

    /// Handles audio session interruption events
    private func handleInterruption(_ event: AudioInterruptionEvent) {
        switch event {
        case .began:
            isInterrupted = true
            currentNote = "--"
            centsOffset = 0.0
            AudioLogger.audio.info("UI updated for interruption began")

        case .ended(let shouldResume):
            isInterrupted = false
            AudioLogger.audio.info("UI updated for interruption ended - shouldResume: \(shouldResume)")
        }
    }

    /// Handles audio route change events
    private func handleRouteChange(_ event: AudioRouteChangeEvent) {
        guard event.requiresReconfiguration else { return }
        stopTuning()
        AudioLogger.audio.warning("Tuning stopped due to route change requiring reconfiguration")
    }

    /// Cleans up real audio capture resources
    private func cleanupRealAudioCapture() {
        cancellables.removeAll()
        audioCapture?.stopCapture()
        audioCapture?.deactivateAudioSession()
        audioCapture = nil
        pitchDetector = nil
    }

    /// Stops the tuning session and ends audio capture
    func stopTuning() {
        guard isAudioRunning else { return }

        listeningTask?.cancel()
        listeningTask = nil
        pitchSource?.stop()
        pitchSource = nil

        cleanupRealAudioCapture()

        isAudioRunning = false
        isInterrupted = false
        currentNote = "--"
        centsOffset = 0.0

        AudioLogger.audio.info("Tuning session stopped")
    }

    /// Called when the app enters the background
    func handleAppDidEnterBackground() {
        guard isAudioRunning, audioInputMode == .real else { return }
        AudioLogger.audio.info("App entering background - stopping real audio")
        stopTuning()
    }

    /// Called when the app becomes active
    func handleAppDidBecomeActive() {
        guard audioInputMode == .real else { return }
        checkMicrophonePermission()
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
