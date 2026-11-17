import Testing

@testable import Engine

@Suite struct HostLookupTests {
    @Test func localhostExists() async {
        #expect(await HostLookup.exists("localhost"))
    }

    // RFC 6761 §6.4: names under .invalid never resolve.
    @Test func invalidNameDoesNotExist() async {
        #expect(await HostLookup.exists("no-such-machine.invalid") == false)
    }

    @Test func emptyNameDoesNotExist() async {
        #expect(await HostLookup.exists("") == false)
    }
}
