import XCTest
@testable import SynheartSession

final class SampleRingBufferTests: XCTestCase {

    private func makeSample(ts: Int64, bpm: Double) -> BiosignalSample {
        BiosignalSample(timestampMs: ts, bpm: bpm, source: "test")
    }

    func testAppendAndReadBack() {
        let buffer = SampleRingBuffer(windowSec: 60)
        buffer.append(makeSample(ts: 1000, bpm: 72.0))
        buffer.append(makeSample(ts: 2000, bpm: 74.0))

        XCTAssertEqual(buffer.count, 2)
        let tuples = buffer.asTuples()
        XCTAssertEqual(tuples.count, 2)
        XCTAssertEqual(tuples[0].bpm, 72.0)
        XCTAssertEqual(tuples[1].bpm, 74.0)
    }

    func testEvictionRemovesOldSamples() {
        let buffer = SampleRingBuffer(windowSec: 5)
        // Add samples spanning 10 seconds
        for i in 0..<10 {
            buffer.append(makeSample(ts: Int64(i) * 1000, bpm: 70.0 + Double(i)))
        }

        // Window is 5 seconds. Latest sample ts = 9000, cutoff = 9000 - 5000 = 4000.
        // Samples with ts < 4000 (i.e. 0,1,2,3) should be evicted.
        let tuples = buffer.asTuples()
        XCTAssertEqual(tuples.count, 6) // ts 4000..9000
        XCTAssertEqual(tuples.first?.timestampMs, 4000)
        XCTAssertEqual(tuples.last?.timestampMs, 9000)
    }

    func testAsTuplesReturnsCorrectFormat() {
        let buffer = SampleRingBuffer(windowSec: 60)
        buffer.append(BiosignalSample(timestampMs: 5000, bpm: 80.0, rrIntervalsMs: [750.0], source: "ble_hrm"))

        let tuples = buffer.asTuples()
        XCTAssertEqual(tuples.count, 1)
        XCTAssertEqual(tuples[0].timestampMs, 5000)
        XCTAssertEqual(tuples[0].bpm, 80.0)
    }

    func testGetAllReturnsBiosignalSamples() {
        let buffer = SampleRingBuffer(windowSec: 60)
        buffer.append(BiosignalSample(timestampMs: 1000, bpm: 72.0, rrIntervalsMs: [833.3], deviceId: "dev1", source: "ble_hrm"))

        let all = buffer.getAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].source, "ble_hrm")
        XCTAssertEqual(all[0].deviceId, "dev1")
        XCTAssertEqual(all[0].rrIntervalsMs, [833.3])
    }

    func testEmptyBuffer() {
        let buffer = SampleRingBuffer(windowSec: 60)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.asTuples().isEmpty)
        XCTAssertTrue(buffer.getAll().isEmpty)
    }

    func testConcurrentAppendAndRead() {
        let buffer = SampleRingBuffer(windowSec: 60)
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for i in 0..<100 {
                buffer.append(self.makeSample(ts: Int64(i) * 100, bpm: 72.0))
            }
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<100 {
                _ = buffer.asTuples()
                _ = buffer.count
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        // If we get here without a crash, thread safety holds.
        XCTAssertGreaterThan(buffer.count, 0)
    }
}
