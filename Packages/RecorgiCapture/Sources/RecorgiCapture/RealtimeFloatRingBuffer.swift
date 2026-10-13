import Foundation

/// A small fixed-capacity circular buffer handing interleaved Float32
/// samples from one realtime audio thread (the writer, e.g. an input tap)
/// to another (the reader, e.g. an output render callback) — the two can
/// run on genuinely different CoreAudio IO threads for input vs. output
/// devices, so this isn't just decoration.
///
/// Uses `os_unfair_lock` rather than being fully lock-free: this only
/// backs a live *monitoring* preview (see `MicrophoneLivePreviewEngine`),
/// never the actual recorded file, so a lock held for the few microseconds
/// it takes to copy some floats is an acceptable, much simpler tradeoff
/// here than a lock-free SPSC queue would be.
final class RealtimeFloatRingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private let capacity: Int
    private var writeIndex = 0
    private var readIndex = 0
    private var filled = 0
    private var lock = os_unfair_lock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [Float](repeating: 0, count: self.capacity)
    }

    /// Overwrites the oldest unread samples if the writer runs ahead of the
    /// reader (should only happen on a real underrun) rather than growing
    /// unbounded.
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let toWrite = min(count, capacity)
        let start = count - toWrite
        for i in 0..<toWrite {
            storage[writeIndex] = samples[start + i]
            writeIndex = (writeIndex + 1) % capacity
        }
        filled = min(capacity, filled + toWrite)
        if filled == capacity {
            readIndex = writeIndex
        }
    }

    /// Returns the number of samples actually available; the caller is
    /// responsible for filling the rest of its own buffer with silence.
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let toRead = min(count, filled)
        for i in 0..<toRead {
            destination[i] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        filled -= toRead
        return toRead
    }
}
