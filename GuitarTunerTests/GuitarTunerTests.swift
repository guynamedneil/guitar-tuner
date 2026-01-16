import XCTest
@testable import GuitarTuner

final class GuitarTunerTests: XCTestCase {
    func testCentsOffsetCalculation() {
        // Test that identical frequencies produce 0 cents offset
        let offset = centsOffset(from: 440.0, to: 440.0)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testCentsOffsetOctaveAbove() {
        // An octave above should be +1200 cents
        let offset = centsOffset(from: 880.0, to: 440.0)
        XCTAssertEqual(offset, 1200, accuracy: 0.001)
    }

    func testCentsOffsetOctaveBelow() {
        // An octave below should be -1200 cents
        let offset = centsOffset(from: 220.0, to: 440.0)
        XCTAssertEqual(offset, -1200, accuracy: 0.001)
    }

    func testStandardGuitarTuningCount() {
        // Standard guitar tuning should have 6 strings
        XCTAssertEqual(Note.standardGuitarTuning.count, 6)
    }

    func testStandardGuitarTuningFirstString() {
        // First string (low E) should be E2 at ~82.41 Hz
        let lowE = Note.standardGuitarTuning[0]
        XCTAssertEqual(lowE.name, "E")
        XCTAssertEqual(lowE.octave, 2)
        XCTAssertEqual(lowE.frequency, 82.41, accuracy: 0.01)
    }
}
