import XCTest
@testable import OpenMouseCore

final class ReleaseVersionTests: XCTestCase {
    func testNumericComponentsAreNotComparedLexically() {
        XCTAssertLessThan(ReleaseVersion("v1.9.0")!, ReleaseVersion("1.10.0")!)
        XCTAssertLessThan(ReleaseVersion("0.1.9")!, ReleaseVersion("0.2.0")!)
    }
    func testStableBeatsPrereleaseAndPrereleaseNumbersAreNumeric() {
        XCTAssertLessThan(ReleaseVersion("1.0.0-beta.10")!, ReleaseVersion("1.0.0")!)
        XCTAssertLessThan(ReleaseVersion("1.0.0-beta.2")!, ReleaseVersion("1.0.0-beta.10")!)
        XCTAssertLessThan(ReleaseVersion("1.0.0-alpha")!, ReleaseVersion("1.0.0-beta")!)
        XCTAssertEqual(ReleaseVersion("v1.2.3+build.4"), ReleaseVersion("1.2.3"))
    }
    func testRejectsMalformedVersions() {
        for value in ["", "1", "1.2", "1.2.3.4", "1.2.-3", "01.2.3", "1.0.0-", "1.0.0-beta.01", "1.0.0-β", "https://example.com"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }
}
