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
        #expect(AddressInput.url(for: typed)?.toString() == typed)
    }

    @Test func bareHostGetsHTTPS() {
        #expect(AddressInput.url(for: "example.com")?.toString() == "https://example.com/")
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(AddressInput.url(for: "  example.com \n")?.toString() == "https://example.com/")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func blankInputLoadsNothing(_ typed: String) {
        #expect(AddressInput.url(for: typed) == nil)
    }

    @Test func wordsBecomeASearch() {
        #expect(AddressInput.url(for: "hello world")?.toString() == "https://google.com/search?q=hello+world")
    }

    @Test func dottedTextWithSpacesIsASearch() {
        #expect(AddressInput.url(for: "example.com is down")?.toString() == "https://google.com/search?q=example.com+is+down")
    }

    @Test func searchEscapesSymbolsThatWouldBreakTheQuery() {
        #expect(AddressInput.url(for: "c++ & rust #1")?.toString() == "https://google.com/search?q=c%2B%2B+%26+rust+%231")
    }

    @Test func searchEscapesNonASCIIText() {
        #expect(AddressInput.url(for: "café")?.toString() == "https://google.com/search?q=caf%C3%A9")
    }
}
