import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct EmbedBoxModelTests {
    private static let baseRules: String = """
        html { width: 400px; }
        body { display: block; }
        p { display: block; }
        """

    private func embed(_ page: LayoutTestPage, id: String) throws -> LayoutID {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return try #require(page.firstEmbedID(in: element))
    }

    @Test func imagePaddingAndBorderTakeRoomOnTheLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="a" width="50" height="40"><img id="b" width="50" height="40"></p>"#,
            rules: Self.baseRules + "#a { padding: 5px; border: 2px solid black; }"
        )
        let a: LayoutID = try embed(page, id: "a")
        let b: LayoutID = try embed(page, id: "b")
        let line: LayoutID = try #require(page.tree.parentID(of: a))
        let box: Rect = page.tree.selfRect(a)

        #expect(page.tree.width(a) == 50)
        #expect(page.tree.height(a) == 40)
        #expect(box == Rect(
            left: page.tree.x(a) - 7,
            top: page.tree.y(a) - 7,
            right: page.tree.x(a) + 57,
            bottom: page.tree.y(a) + 47
        ))
        #expect(box.left == page.tree.x(line))
        #expect(box.top == page.tree.y(line))
        #expect(page.tree.x(b) == box.right + page.tree.font(a).spaceWidth)
        #expect(page.tree.height(line) == 54)
        #expect(page.tree.selfRect(b).bottom == box.bottom)
    }

    @Test func imageBorderIsClickable() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="a" width="50" height="40"></p>"#,
            rules: Self.baseRules + "#a { border: 6px solid black; }"
        )
        let image: ElementRef = try #require(page.firstElement(id: "a"))
        let a: LayoutID = try embed(page, id: "a")
        let box: Rect = page.tree.selfRect(a)
        let document: LayoutTree = page.tree

        #expect(document.hitTest(document.rootID, x: box.left + 2, y: box.top + 2)?.dom == image.id)
    }

    @Test func borderBoxShrinksAnImageInsideItsSizeAttributes() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="a" width="50" height="40"></p>"#,
            rules: Self.baseRules + "#a { box-sizing: border-box; padding: 5px; }"
        )
        let a: LayoutID = try embed(page, id: "a")
        let box: Rect = page.tree.selfRect(a)

        #expect(page.tree.width(a) == 40)
        #expect(page.tree.height(a) == 30)
        #expect(box.right - box.left == 50)
        #expect(box.bottom - box.top == 40)
    }

    @Test func iframeKeepsItsContentSizeInsideItsBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><iframe id="f" width="100" height="80"></iframe></p>"#,
            rules: Self.baseRules + "#f { border: 2px solid black; padding: 3px; }"
        )
        let f: LayoutID = try embed(page, id: "f")
        let box: Rect = page.tree.selfRect(f)
        let origin: Point = page.tree.absoluteContentOrigin(f)

        #expect(page.tree.width(f) == 100)
        #expect(page.tree.height(f) == 80)
        #expect(box.right - box.left == 110)
        #expect(box.bottom - box.top == 90)
        #expect(origin.x == box.left + 5)
        #expect(origin.y == box.top + 5)
    }

    @Test func inputBorderWidensItsSpot() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input id="i"></p>"#,
            rules: Self.baseRules + "#i { border: 1px solid black; padding-left: 4px; }"
        )
        let input: LayoutID = try embed(page, id: "i")
        let box: Rect = page.tree.selfRect(input)

        #expect(page.tree.width(input) == inputWidthPx)
        #expect(box.right - box.left == inputWidthPx + 6)
        #expect(page.tree.x(input) - box.left == 5)
    }

    @Test func paddingChangeOnAnImageRelaysOutTheLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="a" width="50" height="40"><img id="b" width="50" height="40"></p>"#,
            rules: Self.baseRules
        )
        let image: ElementRef = try #require(page.firstElement(id: "a"))

        InlineStyle.set(image, property: "padding", value: "10px")
        InlineStyle.set(image, property: "border-bottom", value: "3px solid black")
        page.frame.setNeedsRender()
        page.frame.render()

        let a: LayoutID = try embed(page, id: "a")
        let b: LayoutID = try embed(page, id: "b")
        let line: LayoutID = try #require(page.tree.parentID(of: a))
        #expect(page.tree.x(b) == page.tree.selfRect(a).right + page.tree.font(a).spaceWidth)
        #expect(page.tree.height(line) == 63)
        expectAllLayoutFieldsClean(try #require(page.frame.document))
        expectIncrementalMatchesFull(page)
    }
}
