import Testing

@testable import Engine

@Suite struct AddressDisplayTests {
    @Test(arguments: [
        ("https://example.com/", "example.com"),
        ("https://example.com/docs?page=2", "example.com/docs?page=2"),
        ("https://example.com/#top", "example.com/#top"),
        ("https://example.com:8443/", "example.com:8443"),
        ("https://www.example.com/a", "example.com/a"),
        ("https://www.com/", "www.com"),
        ("https://wwwexample.com/", "wwwexample.com"),
    ])
    func secureAddressHidesTheParts(_ full: String, _ shown: String) {
        #expect(AddressDisplay.text(for: WebURL(full)) == shown)
    }

    @Test(arguments: [
        "http://example.com/",
        "http://www.example.com/a",
        "file:///tmp/index.html",
        "about:blank",
        "view-source:https://example.com/",
    ])
    func otherAddressIsShownInFull(_ full: String) {
        #expect(AddressDisplay.text(for: WebURL(full)) == full)
    }
}
