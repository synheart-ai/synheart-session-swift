import Foundation
import SynheartSession
import SynheartBehavior

/// Wraps `SynheartBehavior.getCurrentStats()` from synheart-behavior-swift
/// into the `BehaviorProvider` protocol expected by `SessionEngine`.
public class BehaviorSdkProvider: BehaviorProvider {

    private let sdk: SynheartBehavior

    public var isAvailable: Bool { true }
    public var name: String { "synheart_behavior" }

    public init(sdk: SynheartBehavior) {
        self.sdk = sdk
    }

    public func currentSnapshot() -> BehaviorSnapshot? {
        guard let stats = try? sdk.getCurrentStats() else { return nil }
        return BehaviorSnapshot(
            typingCadence: stats.typingCadence,
            interKeyLatency: stats.interKeyLatency,
            burstLength: stats.burstLength,
            scrollVelocity: stats.scrollVelocity,
            scrollAcceleration: stats.scrollAcceleration,
            scrollJitter: stats.scrollJitter,
            tapRate: stats.tapRate,
            appSwitchesPerMinute: stats.appSwitchesPerMinute,
            foregroundDuration: stats.foregroundDuration,
            idleGapSeconds: stats.idleGapSeconds,
            stabilityIndex: stats.stabilityIndex,
            fragmentationIndex: stats.fragmentationIndex,
            timestamp: stats.timestamp
        )
    }
}
