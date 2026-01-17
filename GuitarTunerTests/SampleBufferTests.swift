import XCTest
@testable import GuitarTuner

final class SampleBufferTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithCapacity() {
        let buffer = SampleBuffer(capacity: 1024)
        XCTAssertEqual(buffer.capacity, 1024)
        XCTAssertEqual(buffer.availableSamples, 0)
        XCTAssertEqual(buffer.underrunCount, 0)
    }

    // MARK: - Write Tests

    func testWriteIncreasesAvailableSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]

        buffer.write(samples)

        XCTAssertEqual(buffer.availableSamples, 5)
    }

    func testWriteMultipleTimes() {
        let buffer = SampleBuffer(capacity: 1024)

        buffer.write([1.0, 2.0, 3.0])
        buffer.write([4.0, 5.0])

        XCTAssertEqual(buffer.availableSamples, 5)
    }

    func testWriteFromPointer() {
        let buffer = SampleBuffer(capacity: 1024)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]

        samples.withUnsafeBufferPointer { ptr in
            buffer.write(from: ptr.baseAddress!, count: ptr.count)
        }

        XCTAssertEqual(buffer.availableSamples, 5)
    }

    func testWriteEmptyArrayDoesNothing() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([])

        XCTAssertEqual(buffer.availableSamples, 0)
    }

    // MARK: - Read Tests

    func testReadReturnsWrittenSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]

        buffer.write(samples)
        let result = buffer.read(5)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, samples)
    }

    func testReadDecreasesAvailableSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0])

        _ = buffer.read(3)

        XCTAssertEqual(buffer.availableSamples, 2)
    }

    func testReadReturnsNilWhenInsufficientSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0, 3.0])

        let result = buffer.read(5)

        XCTAssertNil(result)
    }

    func testReadIncrementsUnderrunCountWhenInsufficientSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0])

        _ = buffer.read(5)
        _ = buffer.read(5)

        XCTAssertEqual(buffer.underrunCount, 2)
    }

    func testReadMultipleTimes() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0])

        let first = buffer.read(2)
        let second = buffer.read(3)

        XCTAssertEqual(first, [1.0, 2.0])
        XCTAssertEqual(second, [3.0, 4.0, 5.0])
    }

    // MARK: - Peek Tests

    func testPeekReturnsDataWithoutConsuming() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0, 3.0])

        let peeked = buffer.peek(3)
        let read = buffer.read(3)

        XCTAssertEqual(peeked, [1.0, 2.0, 3.0])
        XCTAssertEqual(read, [1.0, 2.0, 3.0])
    }

    func testPeekReturnsNilWhenInsufficientSamples() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0])

        let result = buffer.peek(5)

        XCTAssertNil(result)
    }

    func testPeekDoesNotIncrementUnderrunCount() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0])

        _ = buffer.peek(5)

        XCTAssertEqual(buffer.underrunCount, 0)
    }

    // MARK: - Wrap-around Tests

    func testWriteWrapsAroundBuffer() {
        let buffer = SampleBuffer(capacity: 8)

        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
        _ = buffer.read(4)
        buffer.write([7.0, 8.0, 9.0, 10.0])

        let result = buffer.read(6)
        XCTAssertEqual(result, [5.0, 6.0, 7.0, 8.0, 9.0, 10.0])
    }

    func testReadWrapsAroundBuffer() {
        let buffer = SampleBuffer(capacity: 8)

        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0])
        _ = buffer.read(3)
        buffer.write([6.0, 7.0, 8.0, 9.0, 10.0])

        let result = buffer.read(7)
        XCTAssertEqual(result, [4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])
    }

    // MARK: - Overflow Tests

    func testOverflowOverwritesOldData() {
        let buffer = SampleBuffer(capacity: 4)

        buffer.write([1.0, 2.0, 3.0, 4.0])
        buffer.write([5.0, 6.0])

        XCTAssertEqual(buffer.availableSamples, 4)

        let result = buffer.read(4)
        XCTAssertEqual(result, [3.0, 4.0, 5.0, 6.0])
    }

    // MARK: - Reset Tests

    func testResetClearsBuffer() {
        let buffer = SampleBuffer(capacity: 1024)
        buffer.write([1.0, 2.0, 3.0])

        buffer.reset()

        XCTAssertEqual(buffer.availableSamples, 0)
        XCTAssertNil(buffer.read(1))
    }

    func testResetUnderrunCount() {
        let buffer = SampleBuffer(capacity: 1024)
        _ = buffer.read(5)

        buffer.resetUnderrunCount()

        XCTAssertEqual(buffer.underrunCount, 0)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentWriteAndRead() async {
        let buffer = SampleBuffer(capacity: 10000)
        let writeCount = 1000
        let samplesPerWrite = 10

        let writeTask = Task.detached {
            for i in 0..<writeCount {
                let samples = (0..<samplesPerWrite).map { Float(i * samplesPerWrite + $0) }
                buffer.write(samples)
                try? await Task.sleep(nanoseconds: 100)
            }
        }

        let readTask = Task.detached {
            var totalRead = 0
            while totalRead < writeCount * samplesPerWrite / 2 {
                if let samples = buffer.read(samplesPerWrite) {
                    totalRead += samples.count
                }
                try? await Task.sleep(nanoseconds: 150)
            }
        }

        await writeTask.value
        await readTask.value

        // Test passes if no crashes occur during concurrent access
        XCTAssertGreaterThanOrEqual(buffer.capacity, 0)
    }
}
