import XCTest
@testable import SynheartSession

/// A test provider that lets us inject samples on demand.
private class TestBiosignalProvider: BiosignalProvider {
    var isAvailable: Bool = true
    var name: String { "test" }

    private var onSample: ((BiosignalSample) -> Void)?
    private(set) var streaming = false

    func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        guard isAvailable else {
            throw SessionError.sensorUnavailable("Test provider unavailable")
        }
        self.onSample = onSample
        streaming = true
    }

    func stopStreaming() {
        onSample = nil
        streaming = false
    }

    /// Inject a sample from test code.
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

final class BiosignalProviderTests: XCTestCase {

    func testMockProviderEmitsSamples() {
        let provider = MockBiosignalProvider()
        XCTAssertTrue(provider.isAvailable)
        XCTAssertEqual(provider.name, "mock")

        var received: [BiosignalSample] = []
        try? provider.startStreaming { sample in
            received.append(sample)
        }

        // Initial sample emitted immediately
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].source, "mock")
        XCTAssertGreaterThanOrEqual(received[0].bpm, 40.0)
        XCTAssertLessThanOrEqual(received[0].bpm, 200.0)

        // Wait for two more samples (~2 seconds)
        let expectation = XCTestExpectation(description: "More samples")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 4.0)

        XCTAssertGreaterThanOrEqual(received.count, 3)
        provider.stopStreaming()
    }

    func testTestProviderInjectsKnownSamples() throws {
        let provider = TestBiosignalProvider()
        var received: [BiosignalSample] = []

        try provider.startStreaming { sample in
            received.append(sample)
        }

        provider.emit(bpm: 72.0, ts: 1000)
        provider.emit(bpm: 80.0, ts: 2000)

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].bpm, 72.0)
        XCTAssertEqual(received[1].bpm, 80.0)
        XCTAssertEqual(received[0].source, "test")

        provider.stopStreaming()
    }

    func testEngineWithTestProviderReceivesSamplesInBuffer() async throws {
        let provider = TestBiosignalProvider()
        let engine = SynheartSession(provider: provider)
        let config = SessionConfig(
            sessionId: "provider-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 10, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        XCTAssertTrue(provider.streaming)

        let baseTs = Int64(Date().timeIntervalSince1970 * 1000)
        provider.emit(bpm: 72.0, ts: baseTs)
        provider.emit(bpm: 74.0, ts: baseTs + 1000)
        provider.emit(bpm: 76.0, ts: baseTs + 2000)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "provider-test")
        let events = await collector.value

        XCTAssertFalse(provider.streaming)

        XCTAssertEqual(events.first?["type"] as? String, "session_started")

        let summaries = events.filter { ($0["type"] as? String) == "session_summary" }
        XCTAssertEqual(summaries.count, 1)

        let metrics = summaries[0]["metrics"] as? [String: Any]
        XCTAssertNotNil(metrics)
        XCTAssertEqual(metrics?["sample_count"] as? Int, 3)
    }

    func testEngineEmitsSessionErrorOnProviderFailure() async throws {
        let provider = TestBiosignalProvider()
        provider.isAvailable = false
        let engine = SynheartSession(provider: provider)
        let config = SessionConfig(
            sessionId: "error-test",
            mode: .focus,
            durationSec: 60
        )

        let stream = try engine.startSession(config: config)
        let events = await collectAsDictionaries(stream).value

        let errors = events.filter { ($0["type"] as? String) == "session_error" }
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0]["error_code"] as? String, "sensor_unavailable")

        XCTAssertNil(engine.getStatus())
    }

    func testDefaultInitUsessMockProvider() async throws {
        let engine = SynheartSession()
        let config = SessionConfig(
            sessionId: "default-test",
            mode: .focus,
            durationSec: 60,
            profile: ComputeProfile(windowSec: 5, emitIntervalSec: 1)
        )

        let stream = try engine.startSession(config: config)
        let collector = collectAsDictionaries(stream)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try engine.stopSession(sessionId: "default-test")
        let events = await collector.value

        let frames = events.filter { ($0["type"] as? String) == "session_frame" }
        XCTAssertGreaterThanOrEqual(frames.count, 1)
    }
}
