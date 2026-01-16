// MARK: - Tuner Reading

/// Represents a stabilized tuner reading ready for display
struct TunerReading {
    /// Name of the detected note (e.g., "A", "E", "G#")
    let noteName: String

    /// Octave number of the detected note
    let octave: Int

    /// Deviation from the target note in cents (-50 to +50)
    let cents: Double

    /// Whether the note is considered in tune (within acceptable threshold)
    let isInTune: Bool

    /// Confidence level of the reading (0.0 to 1.0)
    let confidence: Double
}
