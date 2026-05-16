import Foundation
import SynheartSession
import SynheartWear

/// Biosignal provider that wraps a `BleHrmProvider` from synheart-wear.
/// Bridges the `AsyncStream<HeartRateSample>` into the callback-based
/// `BiosignalProvider` protocol expected by `SessionEngine`.
public class WearBiosignalProvider: BiosignalProvider {

    private let bleHrmProvider: BleHrmProvider
    private var streamTask: Task<Void, Never>?

    public var isAvailable: Bool {
        bleHrmProvider.isConnected()
    }

    public var name: String { "ble_hrm" }

    public init(bleHrmProvider: BleHrmProvider) {
        self.bleHrmProvider = bleHrmProvider
    }

    public func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        guard bleHrmProvider.isConnected() else {
            throw SessionError.sensorUnavailable("BLE HRM not connected")
        }

        streamTask = Task { @MainActor in
            for await hrSample in bleHrmProvider.onHeartRate {
                let sample = BiosignalSample(
                    timestampMs: hrSample.tsMs,
                    bpm: Double(hrSample.bpm),
                    rrIntervalsMs: hrSample.rrIntervalsMs,
                    deviceId: hrSample.deviceId,
                    source: "ble_hrm"
                )
                onSample(sample)
            }
        }
    }

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }
}
