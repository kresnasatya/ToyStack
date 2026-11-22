import Foundation
import Testing

@testable import Engine

@Suite struct CookieJarTests {
    private static let secure: WebURL = WebURL("https://example.test/")
    private static let plain: WebURL = WebURL("http://example.test/")

    @Test func twoCookiesFromOneHostAreBothSent() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1", from: Self.secure)
        await jar.receive("b=2", from: Self.secure)

        #expect(await Self.sent(by: jar) == "a=1; b=2")
    }

    @Test func cookieWithTheSameNameReplacesTheOldOneInItsPlace() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1", from: Self.secure)
        await jar.receive("b=2", from: Self.secure)
        await jar.receive("a=3", from: Self.secure)

        #expect(await Self.sent(by: jar) == "a=3; b=2")
    }

    @Test func cookiesOfOneHostAreNotSentToAnother() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1", from: Self.secure)

        #expect(await jar.header(for: WebURL("https://other.test/"), method: "GET", referrerHost: nil) == nil)
    }

    @Test func foldedSetCookieHeaderKeepsEveryCookie() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Path=/, b=2; Expires=Wed, 21 Oct 2099 07:28:00 GMT, c=3", from: Self.secure)

        #expect(await Self.sent(by: jar) == "a=1; b=2; c=3")
    }

    @Test func expiredCookieRemovesTheOneItReplaces() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1, b=2", from: Self.secure)
        await jar.receive("a=; Max-Age=0", from: Self.secure)

        #expect(await Self.sent(by: jar) == "b=2")
    }

    @Test func cookieWithAnExpiresDateInThePastIsNotSent() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT, b=2", from: Self.secure)

        #expect(await Self.sent(by: jar) == "b=2")
    }

    @Test func setCookieWithoutAnEqualsSignIsIgnored() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1", from: Self.secure)
        await jar.receive("broken", from: Self.secure)

        #expect(await Self.sent(by: jar) == "a=1")
    }

    @Test func laxCookieStaysHomeOnACrossSitePostButOthersAreSent() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; SameSite=Lax, b=2", from: Self.secure)

        #expect(await jar.header(for: Self.secure, method: "POST", referrerHost: "other.test") == "b=2")
        #expect(await jar.header(for: Self.secure, method: "POST", referrerHost: "example.test") == "a=1; b=2")
    }

    @Test func secureCookieIsSentOnlyOverHTTPS() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure, b=2", from: Self.secure)

        #expect(await jar.header(for: Self.secure, method: "GET", referrerHost: nil) == "a=1; b=2")
        #expect(await jar.header(for: Self.plain, method: "GET", referrerHost: nil) == "b=2")
    }

    @Test func onlySecureCookiesMeanNoHeaderOverHTTP() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure", from: Self.secure)

        #expect(await jar.header(for: Self.plain, method: "GET", referrerHost: nil) == nil)
    }

    @Test func scriptOnAnHTTPPageDoesNotSeeSecureCookies() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure, b=2", from: Self.secure)

        #expect(await jar.scriptCookies(for: Self.secure) == "a=1; b=2")
        #expect(await jar.scriptCookies(for: Self.plain) == "b=2")
    }

    @Test func plainHTTPResponseCannotSetASecureCookie() async {
        let jar: CookieJar = CookieJar()

        await jar.receive("a=1; Secure", from: Self.plain)

        #expect(await Self.sent(by: jar) == nil)
    }

    @Test func plainHTTPResponseCannotReplaceOrDeleteASecureCookie() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure", from: Self.secure)

        await jar.receive("a=2", from: Self.plain)
        await jar.receive("a=; Max-Age=0", from: Self.plain)

        #expect(await Self.sent(by: jar) == "a=1")
    }

    @Test func plainHTTPResponseCanStillSetOtherCookiesBesideASecureOne() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure", from: Self.secure)

        await jar.receive("b=2", from: Self.plain)

        #expect(await Self.sent(by: jar) == "a=1; b=2")
    }

    @Test func plainHTTPResponseCanReplaceAnExpiredSecureCookie() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure; Max-Age=0", from: Self.secure)

        await jar.receive("a=2", from: Self.plain)

        #expect(await Self.sent(by: jar) == "a=2")
    }

    @Test func httpsResponseCanReplaceASecureCookie() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure", from: Self.secure)

        await jar.receive("a=2", from: Self.secure)

        #expect(await Self.sent(by: jar) == "a=2")
    }

    @Test func scriptOnAnHTTPPageCannotSetOrReplaceASecureCookie() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; Secure", from: Self.secure)

        await jar.receiveFromScript("a=2", page: Self.plain)
        await jar.receiveFromScript("b=3; Secure", page: Self.plain)

        #expect(await Self.sent(by: jar) == "a=1")
    }

    @Test func scriptOnAnHTTPSPageCanSetASecureCookie() async {
        let jar: CookieJar = CookieJar()

        await jar.receiveFromScript("a=1; Secure", page: Self.secure)

        #expect(await Self.sent(by: jar) == "a=1")
    }

    @Test func scriptSeesEveryCookieExceptHTTPOnlyOnes() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; HttpOnly, b=2, c=3", from: Self.secure)

        #expect(await jar.scriptCookies(for: Self.secure) == "b=2; c=3")
    }

    @Test func scriptCannotReplaceAnHTTPOnlyCookieButCanAddAnother() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("a=1; HttpOnly", from: Self.secure)

        await jar.receiveFromScript("a=2", page: Self.secure)
        await jar.receiveFromScript("b=3", page: Self.secure)

        #expect(await Self.sent(by: jar) == "a=1; b=3")
    }

    @Test func scriptCannotCreateAnHTTPOnlyCookie() async {
        let jar: CookieJar = CookieJar()

        await jar.receiveFromScript("a=1; HttpOnly", page: Self.secure)

        #expect(await Self.sent(by: jar) == nil)
    }

    @Test func scriptCookieWithACommaInItsExpiresDateIsOneCookie() async {
        let jar: CookieJar = CookieJar()

        await jar.receiveFromScript("a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT", page: Self.secure)

        #expect(await jar.scriptCookies(for: Self.secure) == "a=1")
    }

    @Test(arguments: [
        "__Secure-SID=1",
        "__secure-SID=1; Domain=example.test",
        "__SECURE-SID=1; HttpOnly",
        "__Host-SID=1",
        "__host-SID=1; Secure",
        "__Host-SID=1; Secure; Path=/login",
        "__HOST-SID=1; Secure; Domain=example.test; Path=/",
        "__HoSt-SID=1; Domain=example.test; Path=/",
    ])
    func prefixedCookieWithoutWhatItsPrefixPromisesIsIgnored(_ setCookie: String) async {
        let jar: CookieJar = CookieJar()

        await jar.receive(setCookie, from: Self.secure)

        #expect(await Self.sent(by: jar) == nil)
    }

    @Test(arguments: [
        "__Secure-SID=1; Secure",
        "__secure-SID=1; Domain=example.test; Secure",
        "__Host-SID=1; Secure; Path=/",
        "__HOST-SID=1; Secure; Path=/",
        "__Host-SID=1; Secure; Path=/; Domain=",
    ])
    func prefixedCookieThatKeepsItsPromiseIsStored(_ setCookie: String) async {
        let jar: CookieJar = CookieJar()

        await jar.receive(setCookie, from: Self.secure)

        #expect(await Self.sent(by: jar)?.hasSuffix("SID=1") == true)
    }

    @Test func prefixedCookieWithoutItsPromiseCannotReplaceAGoodOne() async {
        let jar: CookieJar = CookieJar()
        await jar.receive("__Host-SID=1; Secure; Path=/", from: Self.secure)

        await jar.receive("__Host-SID=evil; Secure", from: Self.secure)

        #expect(await Self.sent(by: jar) == "__Host-SID=1")
    }

    @Test func scriptCannotSetAPrefixedCookieWithoutItsPromise() async {
        let jar: CookieJar = CookieJar()

        await jar.receiveFromScript("__Host-SID=1; Secure", page: Self.secure)
        await jar.receiveFromScript("__Secure-ID=2", page: Self.secure)

        #expect(await Self.sent(by: jar) == nil)
    }

    @Test func otherCookieNamesNeedNothingExtra() async {
        let jar: CookieJar = CookieJar()

        await jar.receive("Secure-SID=1, _Host-SID=2", from: Self.secure)

        #expect(await Self.sent(by: jar) == "Secure-SID=1; _Host-SID=2")
    }

    @Test func responseWithTwoSetCookieHeadersKeepsBoth() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let address: String = try await server.start()
        let port: Int = WebURL(address).port
        let first: String = "first\(UUID().uuidString.prefix(8))=1"
        let second: String = "second\(UUID().uuidString.prefix(8))=2"
        server.setReply(
            .canonicalHost(
                "127.0.0.1:\(port)", page: "<p>two cookies</p>",
                cookies: [first, second + "; Expires=Wed, 21 Oct 2099 07:28:00 GMT"]
            )
        )

        _ = try await WebURL(address).request(bypassingCache: true)

        let sent: [String] = (await CookieJar.shared.header(for: WebURL(address), method: "GET", referrerHost: nil) ?? "")
            .components(separatedBy: "; ")
        #expect(sent.contains(first))
        #expect(sent.contains(second))
    }

    @Test func secureCookieIsNotSentOnAPlainHTTPRequest() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain</p>"))
        defer { server.stop() }
        let address: String = try await server.start()
        let cookie: String = "secure\(UUID().uuidString.prefix(8))=1"
        await CookieJar.shared.receive(cookie + "; Secure", from: WebURL("https://\(WebURL(address).host)/"))

        _ = try await WebURL(address).request(bypassingCache: true)

        let cookieHeader: String = server.cookies.first.flatMap({ (header: String?) -> String? in header }) ?? ""
        #expect(server.cookies.count == 1)
        #expect(!cookieHeader.components(separatedBy: "; ").contains(cookie))
    }

    @Test func secureCookieFromAPlainHTTPResponseIsDropped() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let address: String = try await server.start()
        let port: Int = WebURL(address).port
        let cookie: String = "planted\(UUID().uuidString.prefix(8))=1"
        server.setReply(.canonicalHost("127.0.0.1:\(port)", page: "<p>plain</p>", cookies: [cookie + "; Secure"]))

        _ = try await WebURL(address).request(bypassingCache: true)

        let sent: [String] = (await CookieJar.shared.header(for: WebURL("https://127.0.0.1/"), method: "GET", referrerHost: nil) ?? "")
            .components(separatedBy: "; ")
        #expect(!sent.contains(cookie))
    }

    private static func sent(by jar: CookieJar) async -> String? {
        await jar.header(for: secure, method: "GET", referrerHost: nil)
    }
}
