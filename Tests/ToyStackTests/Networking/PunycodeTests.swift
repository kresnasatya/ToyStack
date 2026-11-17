import Testing

@testable import Engine

@Suite struct PunycodeTests {
    @Test(arguments: [
        ("münchen", "mnchen-3ya"),
        ("bücher", "bcher-kva"),
        ("例え", "r8jz45g"),
        ("テスト", "zckzah"),
        ("правительство", "80aealotwbjpid2k"),
    ])
    func encodesUnicodeLabels(_ label: String, _ expected: String) {
        #expect(Punycode.encode(label) == expected)
    }

    @Test func asciiOnlyLabelEndsWithTheDelimiter() {
        #expect(Punycode.encode("abc") == "abc-")
    }

    @Test func emptyLabelEncodesToEmpty() {
        #expect(Punycode.encode("") == "")
    }
}
