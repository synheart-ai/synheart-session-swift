import Foundation

/// Mock biosignal provider that generates sinusoidal HR data at 1 Hz.
/// Extracts the same waveform previously embedded in SessionEngine:
/// baseline 72 BPM, amplitude 5, cycle 4 s, noise ±2, clamped [40, 200].
public class MockBiosignalProvider: BiosignalProvider {

    public var isAvailable: Bool { true }
    public var name: String { "mock" }

    private var timer: Timer?
    private var startTime: Date?

    public init() {}

    public func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        startTime = Date()
        // Emit an initial sample immediately so the buffer is never empty on the first frame.
        emitSample(onSample: onSample)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.emitSample(onSample: onSample)
        }
    }

    public func stopStreaming() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    private func emitSample(onSample: (BiosignalSample) -> Void) {
        guard let start = startTime else { return }
        let t = Date().timeIntervalSince(start)
        let baseline = 72.0
        let amplitude = 5.0
        let cycleSec = 4.0
        let sinComponent = amplitude * sin(2.0 * .pi * t / cycleSec)
        let noise = Double.random(in: -2.0...2.0)
        let bpm = min(200.0, max(40.0, baseline + sinComponent + noise))
        let rrMs = 60000.0 / bpm

        let sample = BiosignalSample(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            bpm: bpm,
            rrIntervalsMs: [rrMs],
            source: "mock"
        )
        onSample(sample)
    }
}
