import Testing

@testable import Engine

@Suite struct AddressInputTests {
    @Test(arguments: [
        "https://example.com/page",
        "http://example.com/",
        "file:///tmp/index.html",
        "about:blank",
        "view-source:https://example.com/",
        "data:text/html,<p>hi</p>",
    ])
    func keepsTypedURLAsIs(_ typed: String) {
        #expect(Self.url(typed) == typed)
    }

    @Test func bareHostGetsHTTPS() {
        #expect(Self.url("example.com") == "https://example.com/")
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(Self.url("  example.com \n") == "https://example.com/")
    }

    @Test(arguments: ["", "   ", "\n\t", "?", "?  "])
    func blankInputLoadsNothing(_ typed: String) {
        #expect(AddressInput.address(for: typed) == nil)
    }

    @Test func wordsBecomeASearch() {
        #expect(Self.url("hello world") == "https://google.com/search?q=hello+world")
    }

    @Test func dottedTextWithSpacesIsASearch() {
        #expect(Self.url("example.com is down") == "https://google.com/search?q=example.com+is+down")
    }

    @Test func searchEscapesSymbolsThatWouldBreakTheQuery() {
        #expect(Self.url("c++ & rust #1") == "https://google.com/search?q=c%2B%2B+%26+rust+%231")
    }

    @Test func searchEscapesNonASCIIText() {
        #expect(Self.url("café") == "https://google.com/search?q=caf%C3%A9")
    }

    // MARK: - Address or search

    @Test func leadingQuestionMarkForcesASearch() {
        #expect(Self.url("?example.com") == "https://google.com/search?q=example.com")
    }

    @Test func singleWordIsASearch() {
        #expect(Self.url("weather") == "https://google.com/search?q=weather")
    }

    @Test(arguments: ["foo.notarealtld", "1.2.3", "readme.md5"])
    func unknownEndingIsASearch(_ typed: String) {
        #expect(Self.url(typed) == "https://google.com/search?q=\(typed)")
    }

    @Test func emailAddressIsASearch() {
        #expect(Self.url("me@example.com") == "https://google.com/search?q=me%40example.com")
    }

    @Test(arguments: ["note:todo", "example.com:http", "example.com:99999", "example.com:"])
    func colonWithoutAPortIsASearch(_ typed: String) {
        #expect(Self.url(typed)?.hasPrefix("https://google.com/search?q=") == true)
    }

    @Test(arguments: ["exa!mple.com/", "a..b.com", "-example.com", "example-.com"])
    func hostWithCharactersADomainCannotHaveIsASearch(_ typed: String) {
        #expect(Self.url(typed)?.hasPrefix("https://google.com/search?q=") == true)
    }

    // MARK: - Fix up

    @Test func hostIsLowercased() {
        #expect(Self.url("Example.COM/Docs") == "https://example.com/Docs")
    }

    @Test func pathQueryAndFragmentAreKept() {
        #expect(Self.url("example.com/docs?page=2#top") == "https://example.com/docs?page=2#top")
    }

    @Test func queryRightAfterTheHostGetsARootPath() {
        #expect(Self.url("example.com?page=2") == "https://example.com/?page=2")
    }

    @Test func nonASCIIDomainIsSentInItsASCIIForm() {
        #expect(Self.url("München.de") == "https://xn--mnchen-3ya.de/")
    }

    // MARK: - Scheme

    @Test(arguments: [
        ("localhost", "http://localhost/"),
        ("localhost:8000", "http://localhost:8000/"),
        ("app.localhost:3000/a", "http://app.localhost:3000/a"),
        ("127.0.0.1", "http://127.0.0.1/"),
        ("192.168.1.1:8080/admin", "http://192.168.1.1:8080/admin"),
        ("[::1]", "http://[::1]/"),
        ("[::1]:8080/x", "http://[::1]:8080/x"),
    ])
    func localAndIPAddressesUseHTTP(_ typed: String, _ expected: String) {
        #expect(Self.url(typed) == expected)
    }

    @Test func trailingSlashMakesASingleWordAnAddress() {
        #expect(Self.url("intranet/") == "http://intranet/")
    }

    @Test func trailingSlashMakesAnUnknownEndingAnAddress() {
        #expect(Self.url("foo.notarealtld/") == "https://foo.notarealtld/")
    }

    @Test func portMakesAnUnknownEndingAnAddress() {
        #expect(Self.url("printer.lan:631") == "https://printer.lan:631/")
    }

    @Test func malformedIPv6IsASearch() {
        #expect(Self.url("[::zz]")?.hasPrefix("https://google.com/search?q=") == true)
    }

    private static func url(_ typed: String) -> String? {
        AddressInput.address(for: typed)?.url.toString()
    }
}
