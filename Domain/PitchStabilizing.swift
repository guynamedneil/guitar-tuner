// MARK: - Pitch Stabilizing Protocol

/// Protocol for stabilizing pitch readings over time
protocol PitchStabilizing {
    /// Pushes a new pitch frame and returns a stabilized tuner reading if available
    /// - Parameter frame: The latest pitch detection result
    /// - Returns: A stabilized TunerReading, or nil if not enough data to produce a stable reading
    mutating func push(_ frame: PitchFrame) -> TunerReading?
}
