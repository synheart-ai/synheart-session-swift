import XCTest
@testable import SynheartSession

/// A test behavior provider that lets us control availability and snapshot.
private class TestBehaviorProvider: BehaviorProvider {
    var isAvailable: Bool = true
    var name: String { "test" }

    var snapshot: BehaviorSnapshot? = BehaviorSnapshot(
        typingCadence: 3.5,
        interKeyLatency: 120.0,
        burstLength: 8,
        scrollVelocity: 120.5,
        scrollAcceleration: 15.2,
        scrollJitter: 3.1,
        tapRate: 2.3,
        appSwitchesPerMinute: 4,
        foregroundDuration: 45.0,
        idleGapSeconds: 2.1,
        stabilityIndex: 0.82,
        fragmentationIndex: 0.15,
        timestamp: 1708300000000
    )

    func currentSnapshot() -> BehaviorSnapshot? {
        return snapshot
    }
}

/// A test biosignal provider for injecting known samples.
private class TestBiosignalProvider: BiosignalProvider {
    var isAvailable: Bool = true
    var name: String { "test" }

    private var onSample: ((BiosignalSample) -> Void)?

    func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        guard isAvailable else {
            throw SessionError.sensorUnavailable("Test provider unavailable")
        }
        self.onSample = onSample
    }

    func stopStreaming() {
        onSample = nil
    }

    func emit(bpm: Double, ts: Int64? = nil) {
        let timestamp = ts ?? Int64(Date().timeIntervalSince1970 * 1000)
        let sample = BiosignalSample(
            timestampMs: timestamp,
            bpm: bpm,
            rrIntervalsMs: [60000.0 / bpm],
            source: "test"
        )
        onSample?(sample)
    }
}

/// Collect the typed `SessionEvent` stream into a list of wire-format
/// dictionaries (mirrors the on-the-wire shape the Flutter / Kotlin
/// SDKs emit).
private func collectAsDictionaries(
    _ stream: AsyncStream<SessionEvent>
) -> Task<[[String: Any]], Never> {
    return Task<[[String: Any]], Never> {
        var collected: [[String: Any]] = []
        for await event in stream {
            collected.append(event.toDictionary())
        }
        return collected
    }
}

final class BehaviorProviderTests: XCTestCase {

    // MARK: - MockBehaviorProvider

    func testMockBehaviorProviderReturnsSnapshot() {
        let provider = MockBehaviorProvider()
        let snapshot = provider.currentSnapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.typingCadence, 3.5)
        XCTAssertEqual(snapshot?.interKeyLatency, 120.0)
        XCTAssertEqual(snapshot?.burstLength, 8)
        XCTAssertEqual(snapshot?.scrollVelocity, 120.5)
        XCTAssertEqual(snapshot?.scrollAcceleration, 15.2)
        XCTAssertEqual(snapshot?.scrollJitter, 3.1)
        XCTAssertEqual(snapshot?.tapRate, 2.3)
        XCTAssertEqual(snapshot?.appSwitchesPerMinute, 4)
        XCTAssertEqual(snapshot?.foregroundDuration, 45.0)
        XCTAssertEqual(snapshot?.idleGapSeconds, 2.1)
        XCTAssertEqual(snapshot?.stabilityIndex, 0.82)
        XCTAssertEqual(snapshot?.fragmentationIndex, 0.15)
        XCTAssertGreaterThan(snapshot!.timestamp, 0)
    }

    func testMockBehaviorProviderIsAvailable() {
        let provider = MockBehaviorProvider()
        XCTAssertTrue(provider.isAvailable)
        XCTAssertEqual(provider.name, "mock")
    }

    func testSnapshotToMap() async throws {
        let behaviorProvider = TestBehaviorProvider()
        let biosignalProvider = TestBiosignalProvider()
        let engine = SynheartSession(provider: biosignalProvider, behaviorProvider: behaviorProvider)

        let config = SessionConfig(
            sessionId: "snapshot-map-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        biosignalProvider.emit(bpm: 72.0, ts: baseTs)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "snapshot-map-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        XCTAssertGreaterThanOrEqual(frames.count, 1)

        let behavior = frames.first?["behavior"] as? [String: Any]
        XCTAssertNotNil(behavior)
        XCTAssertEqual(behavior?["typing_cadence"] as? Double, 3.5)
        XCTAssertEqual(behavior?["inter_key_latency"] as? Double, 120.0)
        XCTAssertEqual(behavior?["burst_length"] as? Int, 8)
        XCTAssertEqual(behavior?["scroll_velocity"] as? Double, 120.5)
        XCTAssertEqual(behavior?["scroll_acceleration"] as? Double, 15.2)
        XCTAssertEqual(behavior?["scroll_jitter"] as? Double, 3.1)
        XCTAssertEqual(behavior?["tap_rate"] as? Double, 2.3)
        XCTAssertEqual(behavior?["app_switches_per_minute"] as? Int, 4)
        XCTAssertEqual(behavior?["foreground_duration"] as? Double, 45.0)
        XCTAssertEqual(behavior?["idle_gap_seconds"] as? Double, 2.1)
        XCTAssertEqual(behavior?["stability_index"] as? Double, 0.82)
        XCTAssertEqual(behavior?["fragmentation_index"] as? Double, 0.15)
        XCTAssertEqual(behavior?["timestamp"] as? Int64, 1708300000000)
    }

    // MARK: - Engine integration

    func testEngineWithBehaviorIncludesBehaviorInFrame() async throws {
        let behaviorProvider = TestBehaviorProvider()
        let biosignalProvider = TestBiosignalProvider()
        let engine = SynheartSession(provider: biosignalProvider, behaviorProvider: behaviorProvider)

        let config = SessionConfig(
            sessionId: "behavior-frame-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        biosignalProvider.emit(bpm: 72.0, ts: baseTs)
        biosignalProvider.emit(bpm: 74.0, ts: baseTs + 1000)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "behavior-frame-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        XCTAssertGreaterThanOrEqual(frames.count, 1)
        XCTAssertNotNil(frames.first?["behavior"])
    }

    func testEngineWithoutBehaviorOmitsBehaviorKey() async throws {
        let biosignalProvider = TestBiosignalProvider()
        let engine = SynheartSession(provider: biosignalProvider)

        let config = SessionConfig(
            sessionId: "no-behavior-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        biosignalProvider.emit(bpm: 72.0, ts: baseTs)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "no-behavior-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        XCTAssertGreaterThanOrEqual(frames.count, 1)
        XCTAssertNil(frames.first?["behavior"])
    }

    func testEngineWithUnavailableBehaviorOmits() async throws {
        let behaviorProvider = TestBehaviorProvider()
        behaviorProvider.isAvailable = false
        let biosignalProvider = TestBiosignalProvider()
        let engine = SynheartSession(provider: biosignalProvider, behaviorProvider: behaviorProvider)

        let config = SessionConfig(
            sessionId: "unavail-behavior-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        biosignalProvider.emit(bpm: 72.0, ts: baseTs)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "unavail-behavior-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        XCTAssertGreaterThanOrEqual(frames.count, 1)
        XCTAssertNil(frames.first?["behavior"])
    }

    func testSessionSummaryIncludesBehavior() async throws {
        let behaviorProvider = TestBehaviorProvider()
        let biosignalProvider = TestBiosignalProvider()
        let engine = SynheartSession(provider: biosignalProvider, behaviorProvider: behaviorProvider)

        let config = SessionConfig(
            sessionId: "summary-behavior-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        biosignalProvider.emit(bpm: 72.0, ts: baseTs)

        try engine.stopSession(sessionId: "summary-behavior-test")
        let events = await collector.value

        let summaries = events.filter { ($0["type"] as? String) == "session_summary" }
        XCTAssertEqual(summaries.count, 1)
        XCTAssertNotNil(summaries.first?["behavior"])

        let behavior = summaries.first?["behavior"] as? [String: Any]
        XCTAssertEqual(behavior?["stability_index"] as? Double, 0.82)
    }
}
