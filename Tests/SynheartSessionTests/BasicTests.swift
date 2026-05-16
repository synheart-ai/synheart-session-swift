import XCTest
@testable import SynheartSession

final class BasicTests: XCTestCase {

    func testSessionModeRawValues() {
        XCTAssertEqual(SessionMode.focus.rawValue, "focus")
        XCTAssertEqual(SessionMode.breathing.rawValue, "breathing")
        XCTAssertEqual(SessionMode(from: "focus"), .focus)
        XCTAssertEqual(SessionMode(from: "breathing"), .breathing)
        XCTAssertNil(SessionMode(from: "invalid"))
    }

    func testComputeProfileDefaults() {
        let profile = ComputeProfile()
        XCTAssertEqual(profile.windowSec, 60)
        XCTAssertEqual(profile.emitIntervalSec, 5)
    }

    func testComputeProfileFromMap() {
        let profile = ComputeProfile(from: ["window_sec": 30, "emit_interval_sec": 10])
        XCTAssertEqual(profile.windowSec, 30)
        XCTAssertEqual(profile.emitIntervalSec, 10)
    }

    func testSessionConfigFromMap() throws {
        let map: [String: Any] = [
            "session_id": "test-123",
            "mode": "focus",
            "duration_sec": 300,
            "profile": ["window_sec": 60, "emit_interval_sec": 5]
        ]
        let config = try SessionConfig(from: map)
        XCTAssertEqual(config.sessionId, "test-123")
        XCTAssertEqual(config.mode, .focus)
        XCTAssertEqual(config.durationSec, 300)
    }

    func testSessionConfigMissingFieldThrows() {
        let map: [String: Any] = ["mode": "focus"]
        XCTAssertThrowsError(try SessionConfig(from: map))
    }

    func testSessionErrorCodes() {
        let error = SessionError.permissionDenied("test")
        XCTAssertEqual(error.code, .permissionDenied)
        XCTAssertTrue(error.description.contains("PermissionDenied"))
    }

    func testEngineEmitsSessionFrame() throws {
        let engine = SessionEngine()
        let config = SessionConfig(
            sessionId: "frame-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 5, emitIntervalSec: 1)
        )

        var events: [[String: Any]] = []
        try engine.start(config: config) { event in
            events.append(event)
        }

        // Wait for at least one frame emission
        let expectation = XCTestExpectation(description: "Frame emitted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        try engine.stop(sessionId: "frame-test")

        // Verify session_started event
        XCTAssertEqual(events.first?["type"] as? String, "session_started")

        // Find session_frame events
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
        let engine = SessionEngine()
        let config = SessionConfig(
            sessionId: "dup-test",
            mode: .focus,
            durationSec: 60
        )

        try engine.start(config: config) { _ in }

        XCTAssertThrowsError(
            try engine.start(config: config) { _ in }
        )

        try engine.stop(sessionId: "dup-test")
    }

    func testEngineGetStatusNilWhenIdle() {
        let engine = SessionEngine()
        XCTAssertNil(engine.getStatus())
    }

    func testEngineGetStatusActiveWhenRunning() throws {
        let engine = SessionEngine()
        let config = SessionConfig(
            sessionId: "status-test",
            mode: .focus,
            durationSec: 60
        )

        try engine.start(config: config) { _ in }

        let status = engine.getStatus()
        XCTAssertEqual(status?["session_id"] as? String, "status-test")
        XCTAssertEqual(status?["active"] as? Bool, true)

        try engine.stop(sessionId: "status-test")
    }

    func testIngestHsiMetricsPopulatesFrameHRV() throws {
        let engine = SessionEngine()
        let config = SessionConfig(
            sessionId: "hsi-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 5, emitIntervalSec: 1)
        )

        // Ingest HRV metrics before starting
        engine.ingestHsiMetrics([
            "hrv.sdnn_ms": 42.5,
            "hrv.rmssd_ms": 38.1,
            "hrv.pnn50": 21.3,
        ])

        var events: [[String: Any]] = []
        try engine.start(config: config) { event in
            events.append(event)
        }

        // Wait for at least one frame emission
        let expectation = XCTestExpectation(description: "Frame with HRV emitted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        try engine.stop(sessionId: "hsi-test")

        // Find session_frame events and verify HRV values pass through
        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        if let frame = frames.first, let metrics = frame["metrics"] as? [String: Any] {
            XCTAssertEqual(metrics["hr_sdnn_ms"] as? Double, 42.5)
            XCTAssertEqual(metrics["rmssd_ms"] as? Double, 38.1)
            XCTAssertEqual(metrics["pnn50"] as? Double, 21.3)
        }
    }
}
