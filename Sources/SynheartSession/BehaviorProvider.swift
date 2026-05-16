import Foundation

/// A point-in-time snapshot of behavioral signals.
/// Mirrors `BehaviorStats` from synheart-behavior-swift field-for-field
/// but lives in SynheartSession to avoid an import dependency.
public struct BehaviorSnapshot {
    /// Current typing cadence (keys per second).
    public let typingCadence: Double?
    /// Current inter-key latency in milliseconds.
    public let interKeyLatency: Double?
    /// Current burst length (number of keys in current burst).
    public let burstLength: Int?
    /// Current scroll velocity (pixels per second).
    public let scrollVelocity: Double?
    /// Current scroll acceleration (pixels per second squared).
    public let scrollAcceleration: Double?
    /// Current scroll jitter (variance in scroll speed).
    public let scrollJitter: Double?
    /// Current tap rate (taps per second).
    public let tapRate: Double?
    /// Number of app switches in the last minute.
    public let appSwitchesPerMinute: Int
    /// Current foreground duration in seconds.
    public let foregroundDuration: Double?
    /// Current idle gap duration in seconds.
    public let idleGapSeconds: Double?
    /// Current session stability index (0.0 to 1.0).
    public let stabilityIndex: Double?
    /// Current fragmentation index (0.0 to 1.0).
    public let fragmentationIndex: Double?
    /// Timestamp when these stats were captured.
    public let timestamp: Int64

    public init(
        typingCadence: Double? = nil,
        interKeyLatency: Double? = nil,
        burstLength: Int? = nil,
        scrollVelocity: Double? = nil,
        scrollAcceleration: Double? = nil,
        scrollJitter: Double? = nil,
        tapRate: Double? = nil,
        appSwitchesPerMinute: Int = 0,
        foregroundDuration: Double? = nil,
        idleGapSeconds: Double? = nil,
        stabilityIndex: Double? = nil,
        fragmentationIndex: Double? = nil,
        timestamp: Int64
    ) {
        self.typingCadence = typingCadence
        self.interKeyLatency = interKeyLatency
        self.burstLength = burstLength
        self.scrollVelocity = scrollVelocity
        self.scrollAcceleration = scrollAcceleration
        self.scrollJitter = scrollJitter
        self.tapRate = tapRate
        self.appSwitchesPerMinute = appSwitchesPerMinute
        self.foregroundDuration = foregroundDuration
        self.idleGapSeconds = idleGapSeconds
        self.stabilityIndex = stabilityIndex
        self.fragmentationIndex = fragmentationIndex
        self.timestamp = timestamp
    }
}

/// Abstraction over any behavioral signal source (mock, synheart-behavior SDK).
/// Pull-based — `SessionEngine` queries `currentSnapshot()` at each frame tick.
public protocol BehaviorProvider {
    var isAvailable: Bool { get }
    var name: String { get }
    func currentSnapshot() -> BehaviorSnapshot?
}
