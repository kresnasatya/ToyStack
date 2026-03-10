import Testing

@testable import Engine

@Suite struct CSSParserTests {

    // MARK: - CSSParser.parse()

    @Test func parseSingleRule() {
        let css = "p { color: red; font-size: 16px; }"
        let rules = CSSParser(css).parse()
        #expect(rules.count == 1)
        #expect(rules[0].1["color"] == "red")
        #expect(rules[0].1["font-size"] == "16px")
    }

    @Test func tagSelectorMatches() {
        let selector = TagSelector(tag: "p")
        let el = Element(tag: "p", attributes: [:], parent: nil)
        #expect(selector.matches(el))
        #expect(!selector.matches(Element(tag: "div", attributes: [:], parent: nil)))
    }

    @Test func parseMultipleRules() {
        let css = "p { color: red; } div { margin: 0 }"
        let rules = CSSParser(css).parse()
        #expect(rules.count == 2)
    }

    @Test func parseEmptyInput() {
        let rules = CSSParser("").parse()
        #expect(rules.count == 0)
    }

    @Test func parseMalformedRuleRecovery() {
        // Bad selector rule should be skipped; valid rule should still be parsed.
        let css = "!invalid { } p { color: red; }"
        let rules = CSSParser(css).parse()
        #expect(rules.count == 1)
        #expect(rules[0].1["color"] == "red")
    }

    @Test func parseDescendantSelectorFromCSS() {
        let css = "div p { color: blue; }"
        let rules = CSSParser(css).parse()
        #expect(rules.count == 1)
        #expect(rules[0].0 is DescendantSelector)
        #expect(rules[0].1["color"] == "blue")
    }

    // MARK: - CSSParser.body()

    @Test func bodyMalformedDeclarationRecovery() {
        // "!!!" is invalid but parser should skip it and still parse color.
        let css = "p { !!!; color: red; }"
        let rules = CSSParser(css).parse()
        #expect(rules[0].1["color"] == "red")
    }

    @Test func bodyLowercasesProperties() {
        let css = "P { Color: Red; }"
        let rules = CSSParser(css).parse()
        #expect(rules[0].1["color"] == "Red")
    }

    // MARK: - TagSelector

    @Test func tagSelectorPriority() {
        let selector = TagSelector(tag: "p")
        #expect(selector.priority == 1)
    }

    @Test func tagSelectorDoesNotMatchTextNode() {
        let selector = TagSelector(tag: "p")
        let textNode = TextNode(text: "hello", parent: nil)
        #expect(!selector.matches(textNode))
    }

    // MARK: - DescendantSelector

    @Test func descendantSelectorPriority() {
        let ancestor = TagSelector(tag: "div")
        let descendant = TagSelector(tag: "p")
        let selector = DescendantSelector(ancestor: ancestor, descendant: descendant)
        #expect(selector.priority == 2)
    }

    @Test func descendantSelectorMatches() {
        // <div><p></p></div> - p inside div should match DescendantSelector(div, p)
        let div = Element(tag: "div", attributes: [:], parent: nil)
        let p = Element(tag: "p", attributes: [:], parent: div)
        div.children = [p]

        let selector = DescendantSelector(
            ancestor: TagSelector(tag: "div"),
            descendant: TagSelector(tag: "p")
        )

        #expect(selector.matches(p))
    }

    @Test func descendantSelectorDoesNotMatchWrongAncestor() {
        // <span><p></p></span> - p inside span should NOT match DescendantSelector (div, p)
        let span = Element(tag: "span", attributes: [:], parent: nil)
        let p = Element(tag: "p", attributes: [:], parent: span)

        let selector = DescendantSelector(
            ancestor: TagSelector(tag: "div"),
            descendant: TagSelector(tag: "p")
        )

        #expect(!selector.matches(p))
    }
}
