import Foundation

// MARK: - Note Model

/// Represents a musical note with its properties
struct Note: Equatable, Hashable {
    let name: String
    let octave: Int
    let frequency: Double

    /// Standard tuning frequencies for guitar strings (E2, A2, D3, G3, B3, E4)
    static let standardGuitarTuning: [Note] = [
        Note(name: "E", octave: 2, frequency: 82.41),
        Note(name: "A", octave: 2, frequency: 110.00),
        Note(name: "D", octave: 3, frequency: 146.83),
        Note(name: "G", octave: 3, frequency: 196.00),
        Note(name: "B", octave: 3, frequency: 246.94),
        Note(name: "E", octave: 4, frequency: 329.63)
    ]
}

// MARK: - Frequency Calculations

/// Calculates the difference in cents between two frequencies
/// - Parameters:
///   - frequency: The measured frequency
///   - referenceFrequency: The target reference frequency
/// - Returns: The difference in cents (positive = sharp, negative = flat)
func centsOffset(from frequency: Double, to referenceFrequency: Double) -> Double {
    guard frequency > 0, referenceFrequency > 0 else { return 0 }
    return 1200 * log2(frequency / referenceFrequency)
}
