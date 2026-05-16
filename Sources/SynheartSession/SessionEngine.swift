import Foundation

/// Timer-driven session engine. Collects HR data from a `BiosignalProvider`,
/// buffers samples in a sliding window, and emits session frames with computed metrics.
public class SessionEngine {

    public typealias EventCallback = ([String: Any]) -> Void

    private let provider: BiosignalProvider
    private let behaviorProvider: BehaviorProvider?
    private var config: SessionConfig?
    private var callback: EventCallback?
    private var emitTimer: Timer?
    private var durationTimer: Timer?
    private var rawEmitTimer: Timer?
    private var startedAtMs: Int64 = 0
    private var seq: Int = 0
    private var rawSeq: Int = 0
    private var sampleBuffer: SampleRingBuffer?
    private var lastHsiMetrics: [String: Any]?

    /// Ingest pre-computed HRV metrics from the native session runtime.
    /// These are artifact-filtered and authoritative — the session SDK does not
    /// compute HRV locally.
    public func ingestHsiMetrics(_ hsiMetrics: [String: Any]) {
        lastHsiMetrics = hsiMetrics
    }

    public init(provider: BiosignalProvider = MockBiosignalProvider(),
                behaviorProvider: BehaviorProvider? = nil) {
        self.provider = provider
        self.behaviorProvider = behaviorProvider
    }

    /// Start a new session.
    ///
    /// - Parameters:
    ///   - config: Session configuration.
    ///   - callback: Closure called for each event map.
    /// - Throws: `SessionError.invalidState` if a session is already running.
    public func start(config: SessionConfig, callback: @escaping EventCallback) throws {
        guard self.config == nil else {
            throw SessionError.invalidState("Session \(self.config!.sessionId) is already running")
        }

        self.config = config
        self.callback = callback
        self.seq = 0
        self.rawSeq = 0
        self.startedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        self.sampleBuffer = SampleRingBuffer(windowSec: config.profile.windowSec)

        callback([
            "type": "session_started",
            "session_id": config.sessionId,
            "started_at_ms": startedAtMs
        ])

        // Start the biosignal provider. On error, emit session_error and bail.
        do {
            try provider.startStreaming { [weak self] sample in
                self?.sampleBuffer?.append(sample)
            }
        } catch {
            self.config = nil
            self.callback = nil
            self.sampleBuffer = nil
            callback([
                "type": "session_error",
                "session_id": config.sessionId,
                "error_code": SessionErrorCode.sensorUnavailable.rawValue,
                "message": error.localizedDescription
            ])
            return
        }

        let interval = TimeInterval(config.profile.emitIntervalSec)
        emitTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }

        let duration = TimeInterval(config.durationSec)
        durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self, let cfg = self.config else { return }
            self.doStop(sessionId: cfg.sessionId)
        }

        if config.includeRawSamples {
            let rawInterval = TimeInterval(config.profile.rawEmitIntervalSec ?? config.profile.emitIntervalSec)
            rawEmitTimer = Timer.scheduledTimer(withTimeInterval: rawInterval, repeats: true) { [weak self] _ in
                self?.emitBiosignalFrame()
            }
        }
    }

    /// Stop a running session.
    ///
    /// - Parameter sessionId: The session ID to stop.
    /// - Throws: `SessionError.invalidState` if no session is running or IDs don't match.
    public func stop(sessionId: String) throws {
        guard let cfg = config else {
            throw SessionError.invalidState("No active session")
        }
        guard cfg.sessionId == sessionId else {
            throw SessionError.invalidState("Session ID mismatch: expected \(cfg.sessionId), got \(sessionId)")
        }
        doStop(sessionId: sessionId)
    }

    /// Get the status of the current session.
    ///
    /// - Returns: A status map or `nil` if no session is active.
    public func getStatus() -> [String: Any]? {
        guard let cfg = config else { return nil }
        return [
            "session_id": cfg.sessionId,
            "active": true,
            "last_seq": seq
        ]
    }

    // MARK: - Private

    private func emitFrame() {
        guard let cfg = config, let cb = callback, let buffer = sampleBuffer else { return }

        let samples = buffer.asTuples()
        guard !samples.isEmpty else { return }

        seq += 1
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let metrics = computeMetrics(from: samples)

        var frame: [String: Any] = [
            "type": "session_frame",
            "session_id": cfg.sessionId,
            "seq": seq,
            "emitted_at_ms": nowMs,
            "metrics": metrics
        ]

        if let bp = behaviorProvider, bp.isAvailable, let snapshot = bp.currentSnapshot() {
            frame["behavior"] = snapshotToMap(snapshot)
        }

        cb(frame)
    }

    private func doStop(sessionId: String) {
        emitTimer?.invalidate()
        emitTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        rawEmitTimer?.invalidate()
        rawEmitTimer = nil

        provider.stopStreaming()

        guard let cfg = config, let cb = callback, let buffer = sampleBuffer else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let durationActualSec = Int((nowMs - startedAtMs) / 1000)

        let samples = buffer.asTuples()
        let metrics = computeMetrics(from: samples)

        var summary: [String: Any] = [
            "type": "session_summary",
            "session_id": cfg.sessionId,
            "duration_actual_sec": durationActualSec,
            "metrics": metrics
        ]

        if let bp = behaviorProvider, bp.isAvailable, let snapshot = bp.currentSnapshot() {
            summary["behavior"] = snapshotToMap(snapshot)
        }

        cb(summary)

        self.config = nil
        self.callback = nil
        self.sampleBuffer = nil
        self.lastHsiMetrics = nil
    }

    private func emitBiosignalFrame() {
        guard let cfg = config, let cb = callback, let buffer = sampleBuffer else { return }

        let allSamples = buffer.getAll()
        guard !allSamples.isEmpty else { return }

        rawSeq += 1
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        cb([
            "type": "biosignal_frame",
            "session_id": cfg.sessionId,
            "seq": rawSeq,
            "emitted_at_ms": nowMs,
            "samples": allSamples.map { sample -> [String: Any] in
                var dict: [String: Any] = [
                    "timestamp_ms": sample.timestampMs,
                    "bpm": sample.bpm,
                    "source": sample.source,
                ]
                if let rr = sample.rrIntervalsMs {
                    dict["rr_intervals_ms"] = rr
                }
                if let deviceId = sample.deviceId {
                    dict["device_id"] = deviceId
                }
                return dict
            }
        ])
    }

    /// Convert a `BehaviorSnapshot` to a wire-format map with snake_case keys.
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
    /// HRV metrics (SDNN, RMSSD, pNN50) come from the native runtime which applies
    /// artifact filtering — the session SDK only computes mean HR locally.
    private func computeMetrics(from samples: [(timestampMs: Int64, bpm: Double)]) -> [String: Any] {
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

        // HRV metrics come from the runtime (artifact-filtered, authoritative)
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
