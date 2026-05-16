import Foundation

/// Thread-safe sliding window of `BiosignalSample` values.
/// Evicts samples older than `windowSec` from the most recent sample on each append.
public class SampleRingBuffer {

    private let windowSec: Int
    private var samples: [BiosignalSample] = []
    private let lock = NSLock()

    public init(windowSec: Int) {
        self.windowSec = windowSec
    }

    /// Append a sample and evict anything outside the window.
    public func append(_ sample: BiosignalSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        evict()
    }

    /// Returns `(timestampMs, bpm)` tuples matching the format `computeMetrics()` expects.
    public func asTuples() -> [(timestampMs: Int64, bpm: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return samples.map { ($0.timestampMs, $0.bpm) }
    }

    /// Returns all samples currently in the buffer (for `biosignal_frame`).
    public func getAll() -> [BiosignalSample] {
        lock.lock()
        defer { lock.unlock() }
        return Array(samples)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return samples.isEmpty
    }

    private func evict() {
        guard let latest = samples.last else { return }
        let cutoff = latest.timestampMs - Int64(windowSec) * 1000
        samples.removeAll { $0.timestampMs < cutoff }
    }
}
