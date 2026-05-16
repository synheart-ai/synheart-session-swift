import Foundation

/// Typed event hierarchy emitted by `SynheartSession.startSession`.
///
/// Stream lifecycle: `.sessionStarted` → `.sessionFrame`\* → `.sessionSummary`
/// (or terminating `.sessionError`). When raw samples are requested,
/// `.biosignalFrame` events interleave between session frames.
///
/// Mirrors the Flutter / Kotlin sibling SDKs' `SessionEvent`. The wire
/// format (returned by `toDictionary()`) uses snake_case keys identical
/// across all three.
public enum SessionEvent {
    case sessionStarted(sessionId: String, startedAtMs: Int64)
    case sessionFrame(
        sessionId: String,
        seq: Int,
        emittedAtMs: Int64,
        metrics: [String: Any],
        behavior: [String: Any]?
    )
    case sessionSummary(
        sessionId: String,
        durationActualSec: Int,
        metrics: [String: Any],
        behavior: [String: Any]?
    )
    case sessionError(sessionId: String, code: SessionErrorCode, message: String)
    case biosignalFrame(
        sessionId: String,
        seq: Int,
        emittedAtMs: Int64,
        samples: [[String: Any]]
    )

    /// The session this event belongs to.
    public var sessionId: String {
        switch self {
        case .sessionStarted(let id, _),
             .sessionError(let id, _, _):
            return id
        case .sessionFrame(let id, _, _, _, _),
             .sessionSummary(let id, _, _, _),
             .biosignalFrame(let id, _, _, _):
            return id
        }
    }

    /// Wire-format dictionary representation. Keys match the Flutter / Kotlin
    /// SDKs exactly (snake_case throughout).
    public func toDictionary() -> [String: Any] {
        switch self {
        case .sessionStarted(let sessionId, let startedAtMs):
            return [
                "type": "session_started",
                "session_id": sessionId,
                "started_at_ms": startedAtMs,
            ]
        case .sessionFrame(let sessionId, let seq, let emittedAtMs, let metrics, let behavior):
            var dict: [String: Any] = [
                "type": "session_frame",
                "session_id": sessionId,
                "seq": seq,
                "emitted_at_ms": emittedAtMs,
                "metrics": metrics,
            ]
            if let behavior = behavior { dict["behavior"] = behavior }
            return dict
        case .sessionSummary(let sessionId, let durationActualSec, let metrics, let behavior):
            var dict: [String: Any] = [
                "type": "session_summary",
                "session_id": sessionId,
                "duration_actual_sec": durationActualSec,
                "metrics": metrics,
            ]
            if let behavior = behavior { dict["behavior"] = behavior }
            return dict
        case .sessionError(let sessionId, let code, let message):
            return [
                "type": "session_error",
                "session_id": sessionId,
                "error_code": code.rawValue,
                "message": message,
            ]
        case .biosignalFrame(let sessionId, let seq, let emittedAtMs, let samples):
            return [
                "type": "biosignal_frame",
                "session_id": sessionId,
                "seq": seq,
                "emitted_at_ms": emittedAtMs,
                "samples": samples,
            ]
        }
    }
}
