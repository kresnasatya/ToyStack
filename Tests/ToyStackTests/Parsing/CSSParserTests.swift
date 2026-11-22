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
        #expect(rules.allSatisfy({ $0.2["border-top-width"] == "1px" }))
        #expect(rules.allSatisfy({ $0.2["border-left-style"] == "solid" }))
        #expect(rules.allSatisfy({ $0.2["border-bottom-color"] == "black" }))
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
        #expect(rules.allSatisfy({ ($0.1 as? OriginSelector)?.isImportant == true }))
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

    // MARK: - Escaped identifiers

    @Test func escapedCharactersStayInTheClassName() {
        let css: String = #".md\:hidden, .w-1\/2, .inset-\[-1px\], .py-2\.5, .min-\[570px\]\:flex { display: none }"#
        let keys: [SelectorKey] = CSSParser(css).parse().rules.map({ $0.1.key })
        #expect(keys == [
            .className("md:hidden"), .className("w-1/2"), .className("inset-[-1px]"),
            .className("py-2.5"), .className("min-[570px]:flex"),
        ])
    }

    @Test func underscoreBelongsToTheClassName() {
        let keys: [SelectorKey] = CSSParser(".UVV31W_gradientBorder { color: red }").parse().rules.map({ $0.1.key })
        #expect(keys == [.className("UVV31W_gradientBorder")])
    }

    // CSS Syntax §4.3.7: a hex escape takes up to six hex digits, and one space after
    // them belongs to the escape, not to the selector.
    @Test func hexEscapeSwallowsOneSpace() {
        let rules: [RuleIndex.Rule] = CSSParser(#".\31 0, #\61 b { color: red }"#).parse().rules
        #expect(rules.map({ $0.1.key }) == [.className("10"), .id("ab")])
    }

    @Test func escapedClassAndTagStillFormOneCompound() throws {
        let rules: [RuleIndex.Rule] = CSSParser(#"div.sm\:flex#main { color: red }"#).parse().rules
        let selector: any CSSSelector = try #require(rules.first?.1)
        let dom: DOMTree = DOMTree()
        let hit: NodeID = dom.createElement(tag: "div", attributes: ["class": "sm:flex", "id": "main"])
        let miss: NodeID = dom.createElement(tag: "div", attributes: ["class": "sm", "id": "main"])
        #expect(matches(selector, dom.ref(hit)))
        #expect(!matches(selector, dom.ref(miss)))
    }

    // CSS Syntax §4.3.8: a backslash before a newline is not a valid escape, so the
    // selector is invalid and only its own rule is dropped.
    @Test func backslashBeforeNewlineDropsOnlyThatRule() {
        let rules: [RuleIndex.Rule] = CSSParser(".a\\\n{ color: red } p { color: blue }").parse().rules
        #expect(rules.map({ $0.1.key }) == [.tag("p")])
    }

    private func matches(_ selector: any CSSSelector, _ ref: DOMRef) -> Bool {
        let snapshot: StyleSnapshot = StyleSnapshotBuilder.build(dom: ref.dom)
        guard let index: Int = snapshot.index(of: ref.id) else { return false }
        return selector.matches(snapshot, index)
    }
}
