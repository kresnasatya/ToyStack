import Foundation
import Testing

@testable import Engine

@Suite struct HTTPOnlyHostsTests {
    private static let start: Date = Date(timeIntervalSince1970: 1_000_000)

    @Test func rememberedHostIsKnown() async {
        let hosts: HTTPOnlyHosts = HTTPOnlyHosts()
        await hosts.remember("old.example", now: Self.start)

        #expect(await hosts.contains("old.example", now: Self.start))
        #expect(await hosts.contains("other.example", now: Self.start) == false)
    }

    @Test func hostNamesIgnoreLetterCase() async {
        let hosts: HTTPOnlyHosts = HTTPOnlyHosts()
        await hosts.remember("Old.Example", now: Self.start)

        #expect(await hosts.contains("OLD.example", now: Self.start))
    }

    @Test func memoryFadesAfterAWeekSoHTTPSIsTriedAgain() async {
        let hosts: HTTPOnlyHosts = HTTPOnlyHosts()
        await hosts.remember("old.example", now: Self.start)
        let day: TimeInterval = 24 * 60 * 60

        #expect(await hosts.contains("old.example", now: Self.start.addingTimeInterval(6 * day)))
        #expect(await hosts.contains("old.example", now: Self.start.addingTimeInterval(8 * day)) == false)
    }

    @Test func forgottenHostIsTriedOverHTTPSAgain() async {
        let hosts: HTTPOnlyHosts = HTTPOnlyHosts()
        await hosts.remember("old.example", now: Self.start)
        await hosts.forget("old.example")

        #expect(await hosts.contains("old.example", now: Self.start) == false)
    }
}
