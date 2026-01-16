import Foundation

// MARK: - Tuner ViewModel

/// ViewModel for the tuner screen that manages tuner state and coordinates with the audio pipeline
@MainActor
@Observable
final class TunerViewModel {
    // MARK: - State Properties

    /// The currently detected note name (e.g., "A", "E", "G#"), or "—" when no note is detected
    var currentNote: String = "—"

    /// The deviation from the target note in cents (-50 to +50)
    var centsOffset: Double = 0.0

    /// Whether the audio capture is currently running
    var isAudioRunning: Bool = false

    // MARK: - Actions

    /// Starts the tuning session and begins audio capture
    func startTuning() {
        print("[TunerViewModel] Start tuning requested")
    }

    /// Stops the tuning session and ends audio capture
    func stopTuning() {
        print("[TunerViewModel] Stop tuning requested")
    }
}
