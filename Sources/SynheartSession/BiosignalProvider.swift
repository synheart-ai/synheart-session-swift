import Foundation

/// A single biosignal sample from any heart-rate source.
public struct BiosignalSample {
    public let timestampMs: Int64
    public let bpm: Double
    public let rrIntervalsMs: [Double]?
    public let deviceId: String?
    public let source: String

    public init(timestampMs: Int64, bpm: Double, rrIntervalsMs: [Double]? = nil,
                deviceId: String? = nil, source: String) {
        self.timestampMs = timestampMs
        self.bpm = bpm
        self.rrIntervalsMs = rrIntervalsMs
        self.deviceId = deviceId
        self.source = source
    }
}

/// Abstraction over any heart-rate data source (mock, BLE HRM, HealthKit, Health Connect).
public protocol BiosignalProvider {
    var isAvailable: Bool { get }
    var name: String { get }
    func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws
    func stopStreaming()
}
