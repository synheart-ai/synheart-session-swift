import XCTest
@testable import SynheartSession
@testable import SynheartSessionBehavior
import SynheartBehavior

final class BehaviorSdkProviderTests: XCTestCase {

    func testProviderNameIsCorrect() {
        let sdk = SynheartBehavior()
        let provider = BehaviorSdkProvider(sdk: sdk)
        XCTAssertEqual(provider.name, "synheart_behavior")
    }

    func testProviderIsAvailable() {
        let sdk = SynheartBehavior()
        let provider = BehaviorSdkProvider(sdk: sdk)
        // isAvailable is always true when an SDK instance is provided
        XCTAssertTrue(provider.isAvailable)
    }
}
