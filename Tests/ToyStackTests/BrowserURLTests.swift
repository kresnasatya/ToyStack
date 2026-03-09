import Testing

@testable import Core

@Suite struct BrowserURLTests {
    // MARK - init (parsing)
    @Test func parsesHTTPSScheme() {
        let url = BrowserURL("https://example.com/path")
        #expect(url.scheme == "https")
    }

    @Test func parsesHTTPScheme() {
        let url = BrowserURL("http://example.com/")
        #expect(url.scheme == "http")
    }

    @Test func parsesHost() {
        let url = BrowserURL("https://example.com/path")
        #expect(url.host == "example.com")
    }

    @Test func parsesPath() {
        let url = BrowserURL("https://example.com/some/path")
        #expect(url.path == "/some/path")
    }

    @Test func defaultPortHTTPS() {
        let url = BrowserURL("https://example.com/")
        #expect(url.port == 443)
    }

    @Test func defaultPortHTTP() {
        let url = BrowserURL("http://example.com/")
        #expect(url.port == 80)
    }

    @Test func customPort() {
        let url = BrowserURL("https://example.com:8080/")
        #expect(url.port == 8080)
        #expect(url.host == "example.com")
    }

    @Test func missingPathDefaultsToSlash() {
        let url = BrowserURL("https://example.com")
        #expect(url.path == "/")
    }

    // MARK: - toString

    @Test func toStringOmitsDefaultHTTPSPort() {
        let url = BrowserURL("https://example.com/path")
        #expect(url.toString() == "https://example.com/path")
    }

    @Test func toStringOmitsDefaultHTTPPort() {
        let url = BrowserURL("http://example.com/path")
        #expect(url.toString() == "http://example.com/path")
    }

    @Test func toStringIncludesCustomPort() {
        let url = BrowserURL("http://example.com:8080/path")
        #expect(url.toString() == "http://example.com:8080/path")
    }

    // MARK: - origin

    @Test func origin() {
        let url = BrowserURL("https://example.com/path")
        #expect(url.origin() == "https://example.com:443")
    }

    // MARK: - resolve

    @Test func resolveAbsoluteURL() {
        let base = BrowserURL("https://example.com/a/b")
        let resolved = base.resolve("https://other.com/c")
        #expect(resolved.toString() == "https://other.com/c")
    }

    @Test func resolveAbsolutePath() {
        let base = BrowserURL("https://example.com/a/b")
        let resolved = base.resolve("/c")
        #expect(resolved.toString() == "https://example.com/c")
    }

    @Test func resolveRelativePath() {
        let base = BrowserURL("https://example.com/a/b")
        let resolved = base.resolve("c")
        #expect(resolved.toString() == "https://example.com/a/c")
    }

    @Test func resolveParentRelativePath() {
        let base = BrowserURL("https://example.com/a/b/c")
        let resolved = base.resolve("../d")
        #expect(resolved.toString() == "https://example.com/a/d")
    }

    @Test func resolveProtocolRelative() {
        let base = BrowserURL("https://example.com/path")
        let resolved = base.resolve("//other.com/page")
        #expect(resolved.toString() == "https://other.com/page")
    }
}
