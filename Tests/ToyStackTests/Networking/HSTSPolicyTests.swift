import Testing

@testable import Engine

@Suite struct HSTSPolicyTests {
    @Test func readsMaxAge() {
        #expect(HSTSPolicy(header: "max-age=31536000") == HSTSPolicy(maxAge: 31_536_000, includesSubdomains: false))
    }

    @Test func readsIncludeSubDomains() {
        #expect(HSTSPolicy(header: "max-age=60; includeSubDomains")?.includesSubdomains == true)
    }

    @Test func directiveNamesIgnoreLetterCase() {
        #expect(HSTSPolicy(header: "MAX-AGE=60; INCLUDESUBDOMAINS") == HSTSPolicy(maxAge: 60, includesSubdomains: true))
    }

    @Test func maxAgeMayBeQuoted() {
        #expect(HSTSPolicy(header: "max-age=\"60\"")?.maxAge == 60)
    }

    @Test func spacesAndEmptyDirectivesAreAllowed() {
        #expect(HSTSPolicy(header: " ; max-age = 60 ;; includeSubDomains ; ") == HSTSPolicy(maxAge: 60, includesSubdomains: true))
    }

    @Test func unknownDirectivesAreIgnored() {
        #expect(HSTSPolicy(header: "max-age=60; preload; report-uri=\"x\"") == HSTSPolicy(maxAge: 60, includesSubdomains: false))
    }

    @Test func zeroMaxAgeIsKept() {
        #expect(HSTSPolicy(header: "max-age=0")?.maxAge == 0)
    }

    @Test(arguments: [
        "",
        "includeSubDomains",
        "max-age",
        "max-age=",
        "max-age=-1",
        "max-age=1e3",
        "max-age=soon",
        "max-age=60; max-age=120",
        "max-age=60; includeSubDomains; includeSubDomains",
        "max-age=99999999999999999999999",
    ])
    func malformedHeaderIsIgnored(_ header: String) {
        #expect(HSTSPolicy(header: header) == nil)
    }
}
