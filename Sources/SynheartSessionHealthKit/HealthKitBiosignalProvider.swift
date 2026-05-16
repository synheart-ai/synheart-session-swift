import Foundation
import Combine
import SynheartSession
import SynheartWear

/// Biosignal provider that wraps a `SynheartWear` instance configured with
/// the `.platformHealth` adapter. Bridges the Combine `streamHR()` publisher
/// into the callback-based `BiosignalProvider` protocol expected by `SessionEngine`.
///
/// The caller is responsible for calling `wear.initialize()` before passing
/// the instance to this provider.
@available(iOS 13.0, watchOS 6.0, macOS 13.0, *)
public class HealthKitBiosignalProvider: BiosignalProvider {

    private let wear: SynheartWear
    private var cancellable: AnyCancellable?

    public var isAvailable: Bool { true }
    public var name: String { "apple_healthkit" }

    public init(wear: SynheartWear) {
        self.wear = wear
    }

    public func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        cancellable = wear.streamHR(interval: 1.0)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { metrics in
                    guard let bpm = metrics.getMetric(.hr) else { return }
                    let timestampMs = Int64(metrics.timestamp.timeIntervalSince1970 * 1000)

                    let sample = BiosignalSample(
                        timestampMs: timestampMs,
                        bpm: bpm,
                        rrIntervalsMs: metrics.rrIntervals ?? [60000.0 / bpm],
                        source: "apple_healthkit"
                    )
                    onSample(sample)
                }
            )
    }

    public func stopStreaming() {
        cancellable?.cancel()
        cancellable = nil
    }
}
