import Testing

@testable import Engine

@Suite
@MainActor
struct CustomPropertyParsingTests {
    @Test func keepsTheWholeValueOfACustomProperty() {
        let body: [String: String] = CSSParser(
            "--shadow: 0 1px 2px rgb(0 0 0 / 50%), 0 0 1px red; color: red"
        ).body()
        #expect(body["--shadow"] == "0 1px 2px rgb(0 0 0 / 50%), 0 0 1px red")
        #expect(body["color"] == "red")
    }

    @Test func customPropertyNamesKeepTheirCase() {
        let body: [String: String] = CSSParser("--Main: 1px; --main: 2px; --snake_case: 3px").body()
        #expect(body["--Main"] == "1px")
        #expect(body["--main"] == "2px")
        #expect(body["--snake_case"] == "3px")
    }

    @Test func emptyCustomPropertyIsKept() {
        let body: [String: String] = CSSParser("--empty:; --space: ; width: 1px").body()
        #expect(body["--empty"] == "")
        #expect(body["--space"] == "")
        #expect(body["width"] == "1px")
    }

    @Test func importantCustomPropertyDropsTheFlag() {
        let body: [String: String] = CSSParser("--x: 5px !important; --y: 1px").body()
        #expect(body["--x"] == "5px")
        #expect(body["--y"] == "1px")
    }

    @Test func semicolonInsideAStringDoesNotEndTheValue() {
        let body: [String: String] = CSSParser(#"--label: "a;b"; width: 1px"#).body()
        #expect(body["--label"] == #""a;b""#)
        #expect(body["width"] == "1px")
    }

    @Test func customPropertyEndsAtTheRuleBrace() {
        let rules: [RuleIndex.Rule] = CSSParser(":root { --gap: 4px } p { color: red }").parse().rules
        #expect(rules.count == 2)
        #expect(rules[0].2["--gap"] == "4px")
        #expect(rules[1].2["color"] == "red")
    }
}
