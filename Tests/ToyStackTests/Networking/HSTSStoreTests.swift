import Foundation
import Testing

@testable import Engine

@Suite struct HSTSStoreTests {
    private static let start: Date = Date(timeIntervalSince1970: 1_000_000)

    @Test func secureResponseMakesTheHostHTTPSOnly() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/login"), now: Self.start)

        #expect(await store.upgrade(WebURL("http://bank.example/a?b#c"), now: Self.start).toString() == "https://bank.example/a?b#c")
    }

    @Test func headerOverPlainHTTPIsIgnored() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("http://bank.example/"), now: Self.start)

        #expect(await store.isKnown("bank.example", now: Self.start) == false)
    }

    @Test func headerFromAnIPAddressIsIgnored() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://127.0.0.1/"), now: Self.start)
        await store.note("max-age=60", from: WebURL("https://[::1]/"), now: Self.start)

        #expect(await store.isKnown("127.0.0.1", now: Self.start) == false)
        #expect(await store.isKnown("[::1]", now: Self.start) == false)
    }

    @Test func malformedHeaderChangesNothing() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)
        await store.note("max-age=soon", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.isKnown("bank.example", now: Self.start))
    }

    @Test func ruleEndsWhenMaxAgeRunsOut() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.isKnown("bank.example", now: Self.start.addingTimeInterval(59)))
        #expect(await store.isKnown("bank.example", now: Self.start.addingTimeInterval(61)) == false)
    }

    @Test func zeroMaxAgeRemovesTheRule() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)
        await store.note("max-age=0", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.isKnown("bank.example", now: Self.start) == false)
    }

    @Test func includeSubDomainsCoversEverySubdomain() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60; includeSubDomains", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.isKnown("api.bank.example", now: Self.start))
        #expect(await store.isKnown("a.b.bank.example", now: Self.start))
        #expect(await store.isKnown("notbank.example", now: Self.start) == false)
    }

    @Test func withoutIncludeSubDomainsOnlyTheHostItselfIsCovered() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.isKnown("api.bank.example", now: Self.start) == false)
    }

    @Test func hostNamesIgnoreLetterCase() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://Bank.Example/"), now: Self.start)

        #expect(await store.isKnown("BANK.example", now: Self.start))
    }

    // RFC 6797 §8.3 item 5: port 80 becomes 443, any other port stays.
    @Test func upgradeMovesPort80To443AndKeepsOtherPorts() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(await store.upgrade(WebURL("http://bank.example:80/"), now: Self.start).toString() == "https://bank.example/")
        #expect(await store.upgrade(WebURL("http://bank.example:8080/"), now: Self.start).toString() == "https://bank.example:8080/")
    }

    @Test func unknownHostIsNotUpgraded() async {
        let store: HSTSStore = HSTSStore()
        let url: WebURL = WebURL("http://plain.example/")

        #expect(await store.upgrade(url, now: Self.start) === url)
    }

    @Test func preloadedEndingIsHTTPSOnlyBeforeAnyVisit() async {
        let store: HSTSStore = HSTSStore()

        #expect(await store.isKnown("web.dev", now: Self.start))
        #expect(await store.isKnown("my.site.app", now: Self.start))
    }

    @Test func preloadedRuleCannotBeRemovedByAHeader() async {
        let store: HSTSStore = HSTSStore()
        await store.note("max-age=0", from: WebURL("https://web.dev/"), now: Self.start)

        #expect(await store.isKnown("web.dev", now: Self.start))
    }

    // MARK: - Saved to disk

    @Test func rulesSurviveARestart() async throws {
        let file: URL = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let first: HSTSStore = HSTSStore()
        await first.persist(to: file)
        await first.note("max-age=60; includeSubDomains", from: WebURL("https://bank.example/"), now: Self.start)

        let second: HSTSStore = HSTSStore()
        await second.persist(to: file)

        #expect(await second.isKnown("api.bank.example", now: Self.start))
    }

    @Test func removedRuleStaysRemovedAfterARestart() async throws {
        let file: URL = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let first: HSTSStore = HSTSStore()
        await first.persist(to: file)
        await first.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)
        await first.note("max-age=0", from: WebURL("https://bank.example/"), now: Self.start)

        let second: HSTSStore = HSTSStore()
        await second.persist(to: file)

        #expect(await second.isKnown("bank.example", now: Self.start) == false)
    }

    @Test func damagedFileStartsEmptyAndIsReplaced() async throws {
        let file: URL = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{not json".utf8).write(to: file)
        let store: HSTSStore = HSTSStore()
        await store.persist(to: file)

        #expect(await store.isKnown("bank.example", now: Self.start) == false)

        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)
        let reopened: HSTSStore = HSTSStore()
        await reopened.persist(to: file)
        #expect(await reopened.isKnown("bank.example", now: Self.start))
    }

    @Test func missingFolderIsCreated() async throws {
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("hsts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file: URL = folder.appendingPathComponent("hsts.json")
        let store: HSTSStore = HSTSStore()
        await store.persist(to: file)
        await store.note("max-age=60", from: WebURL("https://bank.example/"), now: Self.start)

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hsts-\(UUID().uuidString).json")
    }
}
