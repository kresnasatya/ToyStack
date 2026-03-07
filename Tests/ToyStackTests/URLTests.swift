import XCTest

@testable import Core

final class URLTests: XCTestCase {
    // MARK - init (parsing)
    func testParsesHTTPSScheme() {
        let url = URL("https://example.com/path")
        XCTAssertEqual(url.scheme, "https")
    }

    func testParsesHTTPScheme() {
        let url = URL("http://example.com/")
        XCTAssertEqual(url.scheme, "http")
    }

    func testParsesHost() {
        let url = URL("https://example.com/path")
        XCTAssertEqual(url.host, "example.com")
    }

    func testParsesPath() {
        let url = URL("https://example.com/some/path")
        XCTAssertEqual(url.path, "/some/path")
    }

    func testDefaultPortHTTPS() {
        let url = URL("https://example.com/")
        XCTAssertEqual(url.port, 443)
    }

    func testDefaultPortHTTP() {
        let url = URL("http://example.com/")
        XCTAssertEqual(url.port, 80)
    }

    func testCustomPort() {
        let url = URL("https://example.com:8080/")
        XCTAssertEqual(url.port, 8080)
        XCTAssertEqual(url.host, "example.com")
    }

    func testMissingPathDefaultsToSlash() {
        let url = URL("https://example.com")
        XCTAssertEqual(url.path, "/")
    }

    // MARK: - toString

    func testToStringOmitsDefaultHTTPSPort() {
        let url = URL("https://example.com/path")
        XCTAssertEqual(url.toString(), "https://example.com/path")
    }

    func testToStringOmitsDefaultHTTPPort() {
        let url = URL("http://example.com/path")
        XCTAssertEqual(url.toString(), "http://example.com/path")
    }

    func testToStringIncludesCustomPort() {
        let url = URL("http://example.com:8080/path")
        XCTAssertEqual(url.toString(), "http://example.com:8080/path")
    }

    // MARK: - origin

    func testOrigin() {
        let url = URL("https://example.com/path")
        XCTAssertEqual(url.origin(), "https://example.com:443")
    }

    // MARK: - resolve

    func testResolveAbsoluteURL() {
        let base = URL("https://example.com/a/b")
        let resolved = base.resolve("https://other.com/c")
        XCTAssertEqual(resolved.toString(), "https://other.com/c")
    }

    func testResolveAbsolutePath() {
        let base = URL("https://example.com/a/b")
        let resolved = base.resolve("/c")
        XCTAssertEqual(resolved.toString(), "https://example.com/c")
    }

    func testResolveRelativePath() {
        let base = URL("https://example.com/a/b")
        let resolved = base.resolve("c")
        XCTAssertEqual(resolved.toString(), "https://example.com/a/c")
    }

    func testResolveParentRelativePath() {
        let base = URL("https://example.com/a/b/c")
        let resolved = base.resolve("../d")
        XCTAssertEqual(resolved.toString(), "https://example.com/a/d")
    }

    func testResolveProtocolRelative() {
        let base = URL("https://example.com/path")
        let resolved = base.resolve("//other.com/page")
        XCTAssertEqual(resolved.toString(), "https://other.com/page")
    }
}
