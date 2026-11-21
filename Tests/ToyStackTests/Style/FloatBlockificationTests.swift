import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FloatBlockificationTests {
    private func style(_ rules: String) throws -> ComputedStyle {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>text <span id="x">note</span></p>"#,
            rules: "body { display: block; } p { display: block; } " + rules
        )
        return try #require(page.firstElement(id: "x")).style.computed
    }

    @Test func floatedInlineElementBecomesABlock() throws {
        let computed: ComputedStyle = try style("#x { float: right; }")
        #expect(computed.layout.display == .block)
        #expect(computed.layout.position.floating.side == .right)
    }

    @Test func displayNoneStaysNone() throws {
        let computed: ComputedStyle = try style("#x { float: left; display: none; }")
        #expect(computed.layout.display == LayoutStyle.Display.none)
    }

    @Test func absolutePositioningCancelsTheFloat() throws {
        let computed: ComputedStyle = try style("#x { float: left; position: absolute; }")
        #expect(computed.layout.position.floating.side == LayoutStyle.FloatSide.none)
    }
}
