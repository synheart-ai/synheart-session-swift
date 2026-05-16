import XCTest
@testable import SynheartSession
@testable import SynheartSessionHealthKit
import SynheartWear

@available(iOS 13.0, watchOS 6.0, macOS 13.0, *)
final class HealthKitBiosignalProviderTests: XCTestCase {

    func testProviderNameIsCorrect() {
        let wear = SynheartWear()
        let provider = HealthKitBiosignalProvider(wear: wear)
        XCTAssertEqual(provider.name, "apple_healthkit")
    }

    func testIsAvailableReturnsTrue() {
        let wear = SynheartWear()
        let provider = HealthKitBiosignalProvider(wear: wear)
        // isAvailable is always true when a wear instance is provided
        XCTAssertTrue(provider.isAvailable)
    }

    func testStopStreamingIsIdempotent() {
        let wear = SynheartWear()
        let provider = HealthKitBiosignalProvider(wear: wear)
        // Double stop should not crash
        provider.stopStreaming()
        provider.stopStreaming()
    }

    func testStartStreamingSubscribesToWear() throws {
        let wear = SynheartWear()
        let provider = HealthKitBiosignalProvider(wear: wear)

        // startStreaming subscribes to wear's streamHR() publisher.
        // On CI without real HealthKit authorization, the wear SDK
        // won't emit samples, but the subscription should succeed.
        try provider.startStreaming { _ in }

        // Clean up
        provider.stopStreaming()
    }
}
