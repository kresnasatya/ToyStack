import Testing

@testable import Engine

@Suite struct CSSParserTests {

    // MARK: - CSSParser.parse()

    @Test func parseSingleRule() {
        let css = "p { color: red; font-size: 16px; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 1)
        let (_, _, declarations) = rules[0]
        #expect(declarations["color"] == "red")
        #expect(declarations["font-size"] == "16px")
    }

    @Test func tagSelectorMatches() {
        let selector = TagSelector(tag: "p")
        let el = Element(tag: "p", attributes: [:], parent: nil)
        #expect(selector.matches(el))
        #expect(!selector.matches(Element(tag: "div", attributes: [:], parent: nil)))
    }

    @Test func parseMultipleRules() {
        let css = "p { color: red; } div { margin: 0 }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 2)
    }

    @Test func parseEmptyInput() {
        let rules = CSSParser("").parse().rules
        #expect(rules.count == 0)
    }

    @Test func parseMalformedRuleRecovery() {
        let css = "!invalid { } p { color: red; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 1)
        let (_, _, declarations) = rules[0]
        #expect(declarations["color"] == "red")
    }

    @Test func parseDescendantSelectorFromCSS() {
        let css = "div p { color: blue; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 1)
        let (_, selector, declarations) = rules[0]
        #expect(selector is DescendantSelector)
        #expect(declarations["color"] == "blue")
    }

    // MARK: - CSSParser.body()

    @Test func bodyMalformedDeclarationRecovery() {
        let css = "p { !!!; color: red; }"
        let rules = CSSParser(css).parse().rules
        let (_, _, declarations) = rules[0]
        #expect(declarations["color"] == "red")
    }

    @Test func bodyLowercasesProperties() {
        let css = "P { Color: Red; }"
        let rules = CSSParser(css).parse().rules
        let (_, _, declarations) = rules[0]
        #expect(declarations["color"] == "Red")
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
        let selector = DescendantSelector(selectors: [ancestor, descendant])
        #expect(selector.priority == 2)
    }

    @Test func descendantSelectorMatches() {
        let div = Element(tag: "div", attributes: [:], parent: nil)
        let p = Element(tag: "p", attributes: [:], parent: div)
        div.children = [p]

        let selector = DescendantSelector(selectors:[
            TagSelector(tag: "div"),
            TagSelector(tag: "p")
        ])

        #expect(selector.matches(p))
    }

    @Test func descendantSelectorDoesNotMatchWrongAncestor() {
        let span = Element(tag: "span", attributes: [:], parent: nil)
        let p = Element(tag: "p", attributes: [:], parent: span)

        let selector = DescendantSelector(selectors: [
            TagSelector(tag: "div"),
            TagSelector(tag: "p")
        ])

        #expect(!selector.matches(p))
    }
}
