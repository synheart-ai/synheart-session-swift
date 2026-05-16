import Foundation

/// Typed status snapshot of an active session. Returned by
/// `SynheartSession.getStatus()` — `nil` when no session is active.
///
/// Mirrors the Flutter / Kotlin sibling SDKs' `SessionStatus`.
public struct SessionStatus: Equatable {
    public let sessionId: String
    public let active: Bool
    public let lastSeq: Int

    public init(sessionId: String, active: Bool, lastSeq: Int) {
        self.sessionId = sessionId
        self.active = active
        self.lastSeq = lastSeq
    }
}
