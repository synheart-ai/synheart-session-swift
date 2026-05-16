import Foundation

/// Timer-driven session engine. Collects HR data from a `BiosignalProvider`,
/// buffers samples in a sliding window, and emits typed `SessionEvent`s
/// with computed metrics on an `AsyncStream`.
///
/// Mirrors the Flutter sibling `SynheartSession` and the Kotlin sibling
/// `SynheartSession`. The on-the-wire shape (returned by
/// `SessionEvent.toDictionary()`) is identical across all three SDKs.
public class SynheartSession {

    private let provider: BiosignalProvider
    private let behaviorProvider: BehaviorProvider?
    private var config: SessionConfig?
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    private var emitTimer: Timer?
    private var durationTimer: Timer?
    private var rawEmitTimer: Timer?
    private var startedAtMs: Int64 = 0
    private var seq: Int = 0
    private var rawSeq: Int = 0
    private var sampleBuffer: SampleRingBuffer?
    private var lastHsiMetrics: [String: Any]?
    private var disposed: Bool = false

    public init(
        provider: BiosignalProvider = MockBiosignalProvider(),
        behaviorProvider: BehaviorProvider? = nil
    ) {
        self.provider = provider
        self.behaviorProvider = behaviorProvider
    }

    /// Ingest pre-computed HRV metrics from the runtime, scoped to a session.
    ///
    /// The session SDK does not compute HRV locally; the runtime supplies
    /// artifact-filtered, authoritative values. No-op if `sessionId` does
    /// not match the currently active session.
    public func ingestHsiMetrics(sessionId: String, hsiMetrics: [String: Any]) {
        guard !disposed, config?.sessionId == sessionId else { return }
        lastHsiMetrics = hsiMetrics
    }

    /// Start a new session and return an `AsyncStream` of `SessionEvent`s.
    ///
    /// Stream lifecycle: `.sessionStarted` → `.sessionFrame`* → `.sessionSummary`
    /// (or `.sessionError` on failure). When `config.includeRawSamples`
    /// is `true`, `.biosignalFrame` events interleave between session
    /// frames.
    ///
    /// Eagerly starts the biosignal provider and emission timers.
    ///
    /// - Throws: `SessionError.invalidState` if a session is already running
    ///   or the instance has been disposed.
    public func startSession(config: SessionConfig) throws -> AsyncStream<SessionEvent> {
        if disposed {
            throw SessionError.invalidState("SynheartSession has been disposed")
        }
        if let existing = self.config {
            throw SessionError.invalidState("Session \(existing.sessionId) is already running")
        }

        var capturedContinuation: AsyncStream<SessionEvent>.Continuation!
        let stream = AsyncStream<SessionEvent>(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        self.config = config
        self.seq = 0
        self.rawSeq = 0
        self.startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        self.sampleBuffer = SampleRingBuffer(windowSec: config.profile.windowSec)

        emit(.sessionStarted(sessionId: config.sessionId, startedAtMs: startedAtMs))

        // Start the biosignal provider. On error, emit session_error and bail.
        do {
            try provider.startStreaming { [weak self] sample in
                self?.sampleBuffer?.append(sample)
            }
        } catch {
            emit(.sessionError(
                sessionId: config.sessionId,
                code: .sensorUnavailable,
                message: error.localizedDescription
            ))
            resetState()
            capturedContinuation.finish()
            return stream
        }

        // Schedule timers on RunLoop.main explicitly. Tests run async test
        // methods on the cooperative executor where no run loop is pumping,
        // so `Timer.scheduledTimer` (which uses the current run loop) would
        // never fire.
        let interval = TimeInterval(config.profile.emitIntervalSec)
        let frameTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }
        RunLoop.main.add(frameTimer, forMode: .common)
        emitTimer = frameTimer

        let duration = TimeInterval(config.durationSec)
        let durTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self, let cfg = self.config else { return }
            self.doStop(sessionId: cfg.sessionId)
        }
        RunLoop.main.add(durTimer, forMode: .common)
        durationTimer = durTimer

        if config.includeRawSamples {
            let rawInterval = TimeInterval(
                config.profile.rawEmitIntervalSec ?? config.profile.emitIntervalSec
            )
            let rawTimer = Timer(timeInterval: rawInterval, repeats: true) { [weak self] _ in
                self?.emitBiosignalFrame()
            }
            RunLoop.main.add(rawTimer, forMode: .common)
            rawEmitTimer = rawTimer
        }

        return stream
    }

    /// Stop a running session — emits a final `.sessionSummary` and finishes
    /// the stream.
    ///
    /// - Throws: `SessionError.invalidState` if no session is running or
    ///   `sessionId` does not match the active session.
    public func stopSession(sessionId: String) throws {
        if disposed { return }
        guard let cfg = config else {
            throw SessionError.invalidState("No active session")
        }
        guard cfg.sessionId == sessionId else {
            throw SessionError.invalidState(
                "Session ID mismatch: expected \(cfg.sessionId), got \(sessionId)"
            )
        }
        doStop(sessionId: sessionId)
    }

    /// Typed status snapshot of the current session, or `nil` if none.
    public func getStatus() -> SessionStatus? {
        if disposed { return nil }
        guard let cfg = config else { return nil }
        return SessionStatus(sessionId: cfg.sessionId, active: true, lastSeq: seq)
    }

    /// Release resources held by this instance.
    public func dispose() {
        guard !disposed else { return }
        disposed = true
        cancelTimers()
        provider.stopStreaming()
        continuation?.finish()
        continuation = nil
        config = nil
        sampleBuffer = nil
        lastHsiMetrics = nil
    }

    // MARK: - Private

    private func emit(_ event: SessionEvent) {
        continuation?.yield(event)
    }

    private func resetState() {
        cancelTimers()
        config = nil
        sampleBuffer = nil
        lastHsiMetrics = nil
    }

    private func cancelTimers() {
        emitTimer?.invalidate()
        emitTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        rawEmitTimer?.invalidate()
        rawEmitTimer = nil
    }

    private func emitFrame() {
        guard let cfg = config, let buffer = sampleBuffer else { return }
        let samples = buffer.asTuples()
        guard !samples.isEmpty else { return }

        seq += 1
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let metrics = computeMetrics(from: samples)
        var behavior: [String: Any]?
        if let bp = behaviorProvider, bp.isAvailable, let snapshot = bp.currentSnapshot() {
            behavior = snapshotToMap(snapshot)
        }

        emit(.sessionFrame(
            sessionId: cfg.sessionId,
            seq: seq,
            emittedAtMs: nowMs,
            metrics: metrics,
            behavior: behavior
        ))
    }

    private func doStop(sessionId: String) {
        cancelTimers()
        provider.stopStreaming()

        guard let cfg = config, let buffer = sampleBuffer else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let durationActualSec = Int((nowMs - startedAtMs) / 1000)
        let samples = buffer.asTuples()
        let metrics = computeMetrics(from: samples)
        var behavior: [String: Any]?
        if let bp = behaviorProvider, bp.isAvailable, let snapshot = bp.currentSnapshot() {
            behavior = snapshotToMap(snapshot)
        }

        emit(.sessionSummary(
            sessionId: cfg.sessionId,
            durationActualSec: durationActualSec,
            metrics: metrics,
            behavior: behavior
        ))

        continuation?.finish()
        continuation = nil
        resetState()
    }

    private func emitBiosignalFrame() {
        guard let cfg = config, let buffer = sampleBuffer else { return }
        let allSamples = buffer.getAll()
        guard !allSamples.isEmpty else { return }

        rawSeq += 1
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let samples: [[String: Any]] = allSamples.map { sample in
            var dict: [String: Any] = [
                "timestamp_ms": sample.timestampMs,
                "bpm": sample.bpm,
                "source": sample.source,
            ]
            if let rr = sample.rrIntervalsMs { dict["rr_intervals_ms"] = rr }
            if let deviceId = sample.deviceId { dict["device_id"] = deviceId }
            return dict
        }

        emit(.biosignalFrame(
            sessionId: cfg.sessionId,
            seq: rawSeq,
            emittedAtMs: nowMs,
            samples: samples
        ))
    }

    /// Convert a `BehaviorSnapshot` to a wire-format dictionary with
    /// snake_case keys.
    private func snapshotToMap(_ snapshot: BehaviorSnapshot) -> [String: Any] {
        var map: [String: Any] = [
            "app_switches_per_minute": snapshot.appSwitchesPerMinute,
            "timestamp": snapshot.timestamp,
        ]
        if let v = snapshot.typingCadence { map["typing_cadence"] = v }
        if let v = snapshot.interKeyLatency { map["inter_key_latency"] = v }
        if let v = snapshot.burstLength { map["burst_length"] = v }
        if let v = snapshot.scrollVelocity { map["scroll_velocity"] = v }
        if let v = snapshot.scrollAcceleration { map["scroll_acceleration"] = v }
        if let v = snapshot.scrollJitter { map["scroll_jitter"] = v }
        if let v = snapshot.tapRate { map["tap_rate"] = v }
        if let v = snapshot.foregroundDuration { map["foreground_duration"] = v }
        if let v = snapshot.idleGapSeconds { map["idle_gap_seconds"] = v }
        if let v = snapshot.stabilityIndex { map["stability_index"] = v }
        if let v = snapshot.fragmentationIndex { map["fragmentation_index"] = v }
        return map
    }

    /// Compute metrics from HR samples + ingested HRV from the session runtime.
    /// HRV metrics (SDNN, RMSSD, pNN50) come from the runtime which applies
    /// artifact filtering — the session SDK only computes mean HR locally.
    internal func computeMetrics(
        from samples: [(timestampMs: Int64, bpm: Double)]
    ) -> [String: Any] {
        guard !samples.isEmpty else {
            return [
                "hr_mean_bpm": 0.0,
                "hr_sdnn_ms": 0.0,
                "rmssd_ms": 0.0,
                "pnn50": 0.0,
                "sample_count": 0,
            ]
        }

        let bpms = samples.map { $0.bpm }
        let meanBpm = bpms.reduce(0, +) / Double(bpms.count)
        let hsi = lastHsiMetrics ?? [:]

        return [
            "hr_mean_bpm": (meanBpm * 10).rounded() / 10,
            "hr_sdnn_ms": (hsi["hrv.sdnn_ms"] as? Double) ?? 0.0,
            "rmssd_ms": (hsi["hrv.rmssd_ms"] as? Double) ?? 0.0,
            "pnn50": (hsi["hrv.pnn50"] as? Double) ?? 0.0,
            "sample_count": samples.count,
            "start_ms": samples.first!.timestampMs,
            "end_ms": samples.last!.timestampMs,
        ]
    }
}
