import Testing

@testable import Engine

@Suite
struct BoxSizingStyleTests {
    private func boxSizing(_ value: String, parent: ComputedStyle? = nil) -> BoxSizing {
        let parsed: (style: ComputedStyle, unknown: [String: String]) = ComputedStyleParser.parse(
            ["box-sizing": value],
            parent: parent
        )
        return parsed.style.box.size.boxSizing
    }

    @Test func parsesBothKeywords() {
        #expect(boxSizing("border-box") == .borderBox)
        #expect(boxSizing("content-box") == .contentBox)
    }

    @Test func unsupportedValueFallsBackToContentBox() {
        #expect(boxSizing("padding-box") == .contentBox)
        #expect(boxSizing("10px") == .contentBox)
    }

    @Test func childrenDoNotInheritIt() {
        let parent: ComputedStyle = ComputedStyleParser.parse(["box-sizing": "border-box"], parent: nil).style
        let child: ComputedStyle = ComputedStyleParser.parse([:], parent: parent).style

        #expect(child.box.size.boxSizing == .contentBox)
    }

    @Test func changingItIsALayoutChange() {
        let before: ComputedStyle = ComputedStyleParser.parse([:], parent: nil).style
        let after: ComputedStyle = ComputedStyleParser.parse(["box-sizing": "border-box"], parent: nil).style

        #expect(after.changed(from: before) == [.boxSizing])
        #expect(StyleProperty(cssName: "box-sizing") == .boxSizing)
        #expect(StyleProperty.boxSizing.affectsLayout)
    }
}
