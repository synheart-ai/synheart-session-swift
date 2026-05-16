import Foundation

/// Session mode matching the wire protocol values.
public enum SessionMode: String {
    case focus = "focus"
    case breathing = "breathing"

    public init?(from string: String) {
        self.init(rawValue: string)
    }
}

/// Error codes matching the wire protocol values.
public enum SessionErrorCode: String {
    case permissionDenied = "permission_denied"
    case sensorUnavailable = "sensor_unavailable"
    case invalidState = "invalid_state"
    case lowBattery = "low_battery"
    case osTerminated = "os_terminated"
}

/// Compute profile controlling session frame emission timing.
public struct ComputeProfile {
    public let windowSec: Int
    public let emitIntervalSec: Int
    public let rawEmitIntervalSec: Int?

    public init(windowSec: Int = 60, emitIntervalSec: Int = 5, rawEmitIntervalSec: Int? = nil) {
        self.windowSec = windowSec
        self.emitIntervalSec = emitIntervalSec
        self.rawEmitIntervalSec = rawEmitIntervalSec
    }

    public init(from map: [String: Any]) {
        self.windowSec = map["window_sec"] as? Int ?? 60
        self.emitIntervalSec = map["emit_interval_sec"] as? Int ?? 5
        self.rawEmitIntervalSec = map["raw_emit_interval_sec"] as? Int
    }
}

/// Session configuration.
public struct SessionConfig {
    public let sessionId: String
    public let mode: SessionMode
    public let durationSec: Int
    public let profile: ComputeProfile
    public let windowLabel: String?
    public let includeRawSamples: Bool

    public init(sessionId: String, mode: SessionMode, durationSec: Int,
                profile: ComputeProfile = ComputeProfile(),
                windowLabel: String? = nil,
                includeRawSamples: Bool = false) {
        self.sessionId = sessionId
        self.mode = mode
        self.durationSec = durationSec
        self.profile = profile
        self.windowLabel = windowLabel
        self.includeRawSamples = includeRawSamples
    }

    public init(from map: [String: Any]) throws {
        guard let sessionId = map["session_id"] as? String else {
            throw SessionError.invalidState("Missing session_id")
        }
        guard let modeStr = map["mode"] as? String,
              let mode = SessionMode(from: modeStr) else {
            throw SessionError.invalidState("Missing or invalid mode")
        }
        guard let durationSec = map["duration_sec"] as? Int else {
            throw SessionError.invalidState("Missing duration_sec")
        }
        self.sessionId = sessionId
        self.mode = mode
        self.durationSec = durationSec
        if let profileMap = map["profile"] as? [String: Any] {
            self.profile = ComputeProfile(from: profileMap)
        } else {
            self.profile = ComputeProfile()
        }
        self.windowLabel = map["window_label"] as? String
        self.includeRawSamples = map["include_raw_samples"] as? Bool ?? false
    }
}
