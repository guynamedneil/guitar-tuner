import Foundation
import os

// MARK: - Sample Buffer

/// A lock-free ring buffer for storing audio samples that can provide frames of N samples on demand.
/// Designed for real-time audio thread safety using os_unfair_lock for minimal latency.
final class SampleBuffer {
    // MARK: - Properties

    /// The total capacity of the buffer in samples
    let capacity: Int

    /// The number of buffer underruns (read requests when insufficient samples available)
    private(set) var underrunCount: Int = 0

    // MARK: - Private Properties

    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var availableCount: Int = 0
    private var lock = os_unfair_lock()

    // MARK: - Initialization

    /// Creates a new sample buffer with the specified capacity
    /// - Parameter capacity: The maximum number of samples the buffer can hold
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    // MARK: - Public Methods

    /// The number of samples currently available for reading
    var availableSamples: Int {
        os_unfair_lock_lock(&lock)
        let count = availableCount
        os_unfair_lock_unlock(&lock)
        return count
    }

    /// Writes samples to the buffer. Called from the audio thread.
    /// If the buffer is full, older samples will be overwritten.
    /// - Parameter samples: The audio samples to write
    func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity

            if availableCount < capacity {
                availableCount += 1
            } else {
                // Buffer overflow - advance read index to maintain FIFO
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// Writes samples to the buffer using an unsafe pointer for better performance.
    /// - Parameters:
    ///   - pointer: Pointer to the sample data
    ///   - count: Number of samples to write
    func write(from pointer: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for i in 0..<count {
            buffer[writeIndex] = pointer[i]
            writeIndex = (writeIndex + 1) % capacity

            if availableCount < capacity {
                availableCount += 1
            } else {
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// Reads the specified number of samples from the buffer.
    /// - Parameter count: The number of samples to read
    /// - Returns: An array of samples, or nil if insufficient samples are available
    func read(_ count: Int) -> [Float]? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard availableCount >= count else {
            underrunCount += 1
            return nil
        }

        let result = copySamples(count: count, fromIndex: readIndex)
        readIndex = (readIndex + count) % capacity
        availableCount -= count

        return result
    }

    /// Peeks at samples without consuming them from the buffer.
    /// - Parameter count: The number of samples to peek
    /// - Returns: An array of samples, or nil if insufficient samples are available
    func peek(_ count: Int) -> [Float]? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard availableCount >= count else {
            return nil
        }

        return copySamples(count: count, fromIndex: readIndex)
    }

    /// Copies samples from the buffer starting at the given index, handling wrap-around.
    /// Must be called while holding the lock.
    private func copySamples(count: Int, fromIndex startIndex: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)

        if startIndex + count <= capacity {
            result.withUnsafeMutableBufferPointer { destPtr in
                buffer.withUnsafeBufferPointer { srcPtr in
                    destPtr.baseAddress?.update(from: srcPtr.baseAddress! + startIndex, count: count)
                }
            }
        } else {
            let firstPartCount = capacity - startIndex
            let secondPartCount = count - firstPartCount

            result.withUnsafeMutableBufferPointer { destPtr in
                buffer.withUnsafeBufferPointer { srcPtr in
                    destPtr.baseAddress?.update(from: srcPtr.baseAddress! + startIndex, count: firstPartCount)
                    (destPtr.baseAddress! + firstPartCount).update(from: srcPtr.baseAddress!, count: secondPartCount)
                }
            }
        }

        return result
    }

    /// Resets the buffer to its initial empty state
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        writeIndex = 0
        readIndex = 0
        availableCount = 0
    }

    /// Resets the underrun counter to zero
    func resetUnderrunCount() {
        os_unfair_lock_lock(&lock)
        underrunCount = 0
        os_unfair_lock_unlock(&lock)
    }
}
