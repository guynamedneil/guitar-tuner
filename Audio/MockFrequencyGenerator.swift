import Foundation

// MARK: - Mock Frequency Generator

/// Generates mock frequencies for testing and UI development
enum MockFrequencyGenerator {
    /// The mode of mock frequency generation
    enum Mode {
        /// Smoothly sweeps frequency from 430 Hz to 450 Hz and back
        case glide
        /// Cycles through standard guitar tuning note frequencies
        case stepNotes
    }

    /// Returns the frequency for the given mode at the specified time
    static func frequency(for mode: Mode, at time: Double) -> Double {
        switch mode {
        case .glide:
            return glideFrequency(at: time)
        case .stepNotes:
            return stepNoteFrequency(at: time)
        }
    }

    /// Generates a smooth frequency sweep from 430 Hz to 450 Hz over a 4-second cycle
    private static func glideFrequency(at time: Double) -> Double {
        let cyclePosition = time.truncatingRemainder(dividingBy: 4.0)
        let normalizedPosition: Double
        if cyclePosition < 2.0 {
            normalizedPosition = cyclePosition / 2.0
        } else {
            normalizedPosition = 1.0 - (cyclePosition - 2.0) / 2.0
        }
        return 430.0 + normalizedPosition * 20.0
    }

    /// Cycles through standard guitar tuning frequencies, spending 2 seconds on each note
    private static func stepNoteFrequency(at time: Double) -> Double {
        let frequencies = Note.standardGuitarTuning.map { $0.frequency }
        let noteIndex = Int(time / 2.0) % frequencies.count
        return frequencies[noteIndex]
    }
}
