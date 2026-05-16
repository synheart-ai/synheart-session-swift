import XCTest
@testable import SynheartSession

final class BasicTests: XCTestCase {

    func testSessionModeValues() {
        XCTAssertEqual(SessionMode.focus.rawValue, "focus")
        XCTAssertEqual(SessionMode.breathing.rawValue, "breathing")
    }

    func testSessionErrorCodeValues() {
        XCTAssertEqual(SessionErrorCode.permissionDenied.rawValue, "permission_denied")
        XCTAssertEqual(SessionErrorCode.sensorUnavailable.rawValue, "sensor_unavailable")
        XCTAssertEqual(SessionErrorCode.invalidState.rawValue, "invalid_state")
        XCTAssertEqual(SessionErrorCode.lowBattery.rawValue, "low_battery")
        XCTAssertEqual(SessionErrorCode.osTerminated.rawValue, "os_terminated")
    }

    func testComputeProfileDefaults() {
        let profile = ComputeProfile()
        XCTAssertEqual(profile.windowSec, 60)
        XCTAssertEqual(profile.emitIntervalSec, 5)
    }

    func testSessionConfigInit() {
        let config = SessionConfig(
            sessionId: "test-123",
            mode: .focus,
            durationSec: 300
        )
        XCTAssertEqual(config.sessionId, "test-123")
        XCTAssertEqual(config.mode, .focus)
        XCTAssertEqual(config.durationSec, 300)
    }

    func testSessionConfigFromMap() throws {
        let map: [String: Any] = [
            "session_id": "decode-test",
            "mode": "breathing",
            "duration_sec": 120,
            "profile": ["window_sec": 30, "emit_interval_sec": 2],
        ]
        let config = try SessionConfig(from: map)
        XCTAssertEqual(config.sessionId, "decode-test")
        XCTAssertEqual(config.mode, .breathing)
        XCTAssertEqual(config.durationSec, 120)
        XCTAssertEqual(config.profile.windowSec, 30)
        XCTAssertEqual(config.profile.emitIntervalSec, 2)
    }

    func testSessionError() {
        let error = SessionError.permissionDenied("test")
        XCTAssertEqual(error.code, .permissionDenied)
        XCTAssertTrue(error.description.contains("PermissionDenied"))
    }

    func testEngineEmitsSessionFrame() async throws {
        let engine = SynheartSession()
        let config = SessionConfig(
            sessionId: "frame-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 5, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = Task<[[String: Any]], Never> {
            var collected: [[String: Any]] = []
            for await event in stream {
                collected.append(event.toDictionary())
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "frame-test")
        let events = await collector.value

        XCTAssertEqual(events.first?["type"] as? String, "session_started")

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        if let frame = frames.first {
            let metrics = frame["metrics"] as? [String: Any]
            XCTAssertNotNil(metrics?["hr_mean_bpm"])
            XCTAssertNotNil(metrics?["hr_sdnn_ms"])
            XCTAssertNotNil(metrics?["rmssd_ms"])
            XCTAssertNotNil(metrics?["sample_count"])
        }
    }

    func testEngineRejectsDuplicate() throws {
        let engine = SynheartSession()
        let config = SessionConfig(
            sessionId: "dup-test",
            mode: .focus,
            durationSec: 60
        )

        _ = try engine.startSession(config: config)
        XCTAssertThrowsError(try engine.startSession(config: config))

        try engine.stopSession(sessionId: "dup-test")
    }

    func testEngineGetStatusNilWhenIdle() {
        let engine = SynheartSession()
        XCTAssertNil(engine.getStatus())
    }

    func testEngineGetStatusActiveWhenRunning() throws {
        let engine = SynheartSession()
        let config = SessionConfig(
            sessionId: "status-test",
            mode: .focus,
            durationSec: 60
        )

        _ = try engine.startSession(config: config)

        let status = engine.getStatus()
        XCTAssertEqual(status?.sessionId, "status-test")
        XCTAssertEqual(status?.active, true)

        try engine.stopSession(sessionId: "status-test")
    }

    func testIngestHsiMetricsPopulatesFrameHRV() async throws {
        let engine = SynheartSession()
        let config = SessionConfig(
            sessionId: "hsi-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 5, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        engine.ingestHsiMetrics(sessionId: "hsi-test", hsiMetrics: [
            "hrv.sdnn_ms": 42.5,
            "hrv.rmssd_ms": 38.1,
            "hrv.pnn50": 21.3,
        ])

        let collector = Task<[[String: Any]], Never> {
            var collected: [[String: Any]] = []
            for await event in stream {
                collected.append(event.toDictionary())
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "hsi-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        if let frame = frames.first, let metrics = frame["metrics"] as? [String: Any] {
            XCTAssertEqual(metrics["hr_sdnn_ms"] as? Double, 42.5)
            XCTAssertEqual(metrics["rmssd_ms"] as? Double, 38.1)
            XCTAssertEqual(metrics["pnn50"] as? Double, 21.3)
        }
    }
}
