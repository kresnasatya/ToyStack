import Testing

@testable import Engine

@Suite
@MainActor
struct CSSParserTests {

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
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "p", attributes: [:])
        let div: NodeID = dom.createElement(tag: "div", attributes: [:])
        #expect(matches(selector, dom.ref(el)))
        #expect(!matches(selector, dom.ref(div)))
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

    @Test func parseSelectorListAsOneRulePerSelector() {
        let css = "#source, #target { width: 420px; border: 1px solid black; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 2)
        #expect(rules.allSatisfy({ $0.2["width"] == "420px" }))
        #expect(rules.allSatisfy({ $0.2["border-width"] == "1px" }))
        #expect(rules.allSatisfy({ $0.2["border-style"] == "solid" }))
        #expect(rules.allSatisfy({ $0.2["border-color"] == "black" }))
        let ids: [String] = rules.compactMap({ ($0.1 as? IDSelector)?.id })
        #expect(ids == ["source", "target"])
    }

    @Test func selectorListKeepsEachSpecificity() {
        let css = "#source, p { color: red; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 2)
        #expect(rules[0].1.priority == 100)
        #expect(rules[1].1.priority == 1)
    }

    @Test func selectorListWithImportantWrapsEverySelector() {
        let css = "p, .note { color: red !important; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 2)
        #expect(rules.allSatisfy({ $0.1 is ImportantSelector }))
    }

    @Test func malformedSelectorListRecoversWithoutUniversalRule() {
        let css = "p, { color: red; } div { color: blue; }"
        let rules = CSSParser(css).parse().rules
        #expect(rules.count == 1)
        #expect(rules[0].2["color"] == "blue")
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
        let dom: DOMTree = DOMTree()
        let textNode: NodeID = dom.createText("hello")
        #expect(!matches(selector, dom.ref(textNode)))
    }

    // MARK: - DescendantSelector

    @Test func descendantSelectorPriority() {
        let ancestor = TagSelector(tag: "div")
        let descendant = TagSelector(tag: "p")
        let selector = DescendantSelector(selectors: [ancestor, descendant])
        #expect(selector.priority == 2)
    }

    @Test func descendantSelectorMatches() {
        let dom: DOMTree = DOMTree()
        let div: NodeID = dom.createElement(tag: "div", attributes: [:])
        let p: NodeID = dom.createElement(tag: "p", attributes: [:])
        dom.append(p, to: div)

        let selector = DescendantSelector(selectors:[
            TagSelector(tag: "div"),
            TagSelector(tag: "p")
        ])

        #expect(matches(selector, dom.ref(p)))
    }

    @Test func descendantSelectorDoesNotMatchWrongAncestor() {
        let dom: DOMTree = DOMTree()
        let span: NodeID = dom.createElement(tag: "span", attributes: [:])
        let p: NodeID = dom.createElement(tag: "p", attributes: [:])
        dom.append(p, to: span)

        let selector = DescendantSelector(selectors: [
            TagSelector(tag: "div"),
            TagSelector(tag: "p")
        ])

        #expect(!matches(selector, dom.ref(p)))
    }

    private func matches(_ selector: any CSSSelector, _ ref: DOMRef) -> Bool {
        let snapshot: StyleSnapshot = StyleSnapshotBuilder.build(dom: ref.dom)
        guard let index: Int = snapshot.index(of: ref.id) else { return false }
        return selector.matches(snapshot, index)
    }
}
