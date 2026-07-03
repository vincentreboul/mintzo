import XCTest
@testable import MintzoCore

final class MintzoCoreTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(MintzoCore.version.isEmpty)
    }
}
