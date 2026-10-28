import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutOracleTests {

    // MARK: - Text and style

    @Test func editTextRebuildsOnlyContainingBlock() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="first">one two</p><p id="second">three four</p>"#,
            rules: """
                body { display: block; }
                p { display: block; width: 200px; }
                """
        )
        let first: Element = try element("first", in: page)
        let second: Element = try element("second", in: page)
        let text: TextNode = try #require(first.children.first as? TextNode)
        let secondBefore: BlockLayout = try #require(second.layoutObject as? BlockLayout)

        text.append(" more words that wrap")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let secondAfter: BlockLayout = try #require(second.layoutObject as? BlockLayout)
        #expect(secondAfter === secondBefore)
        #expect(profiler.snapshot()["layout.children.rebuilt"] == nil)
        expectIncrementalMatchesFull(page)
    }

    @Test func textEditStopsAtUnchangedSiblings() throws {
        // One line on purpose: whitespace between block tags would create
        // anonymous blocks and change the visit count.
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="first">alpha</p><p>beta</p><p>gamma</p><p>delta</p><p>epsilon</p><p>zeta</p><p>eta</p><p>theta</p>"#,
            rules: """
                body { display: block; }
                p { display: block; width: 120px; height: 20px; }
                """
        )
        let first: Element = try element("first", in: page)
        let text: TextNode = try #require(first.children.first as? TextNode)

        text.append(" and more words")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 3)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 7)
        expectIncrementalMatchesFull(page)
    }

    @Test func displayChangeRegroupsParentChildren() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="parent"><span id="child">alpha</span></div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                span { display: block; }
                """
        )
        let parent: Element = try element("parent", in: page)
        let child: Element = try element("child", in: page)
        let block: BlockLayout = try #require(parent.layoutObject as? BlockLayout)
        #expect(!block.children.contains(where: { $0 is LineLayout }))

        InlineStyle.set(child, property: "display", value: "inline")
        page.frame.setNeedsRender()
        page.frame.render()

        let after: BlockLayout = try #require(parent.layoutObject as? BlockLayout)
        #expect(after === block)
        #expect(after.children.contains(where: { $0 is LineLayout }))

        InlineStyle.set(child, property: "display", value: "block")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(!after.children.contains(where: { $0 is LineLayout }))
        #expect(after.children.contains(where: { $0 is BlockLayout }))
        expectIncrementalMatchesFull(page)
    }

    @Test func widthChangePropagatesDown() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="para">one two three four five six seven</p></div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
                """
        )
        let box: Element = try element("box", in: page)
        let paragraph: Element = try element("para", in: page)
        let boxBlock: BlockLayout = try #require(box.layoutObject as? BlockLayout)
        let paragraphBlock: BlockLayout = try #require(
            paragraph.layoutObject as? BlockLayout
        )
        #expect(paragraphBlock.width == boxBlock.width)

        InlineStyle.set(box, property: "width", value: "240px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(boxBlock.width == CGFloat(240))
        let paragraphAfter: BlockLayout = try #require(
            paragraph.layoutObject as? BlockLayout
        )
        #expect(paragraphAfter.width == CGFloat(240))
        let line: LineLayout = try #require(
            paragraphAfter.children.compactMap({ $0 as? LineLayout }).first
        )
        #expect(line.width == CGFloat(240))
        expectIncrementalMatchesFull(page)
    }

    // MARK: - Viewport and zoom

    @Test func viewportResizeUpdatesRootWidth() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">text</div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                """
        )
        let document: DocumentLayout = try #require(page.frame.document)
        #expect(document.width == page.frame.frameWidth - 2 * HSTEP)

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let body: Element = try #require(page.firstElement(tag: "body"))
        let bodyBlock: BlockLayout = try #require(body.layoutObject as? BlockLayout)
        #expect(document.width == CGFloat(400) - 2 * HSTEP)
        #expect(bodyBlock.width == document.width)
        expectIncrementalMatchesFull(page)
    }

    @Test func pageZoomDoesNotLeaveStaleMetrics() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">zoom me</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
                """
        )
        let paragraph: Element = try element("para", in: page)
        let block: BlockLayout = try #require(paragraph.layoutObject as? BlockLayout)
        let text: TextLayout = try #require(
            treeToList(block).compactMap({ $0 as? TextLayout }).first
        )
        let heightBefore: CGFloat = text.height
        let textWidthBefore: CGFloat = text.textWidth

        page.frame.setPageZoom(2)
        page.frame.render()

        let document: DocumentLayout = try #require(page.frame.document)
        let paragraphAfter: BlockLayout = try #require(
            paragraph.layoutObject as? BlockLayout
        )
        let zoomed: TextLayout = try #require(
            treeToList(paragraphAfter).compactMap({ $0 as? TextLayout }).first
        )
        // Page zoom shrinks the layout viewport and is applied at paint time;
        // it is not a layout `zoom` field.
        #expect(document.zoom == CGFloat(1))
        #expect(document.pageZoom == CGFloat(2))
        #expect(document.width == page.frame.frameWidth - 2 * HSTEP)
        #expect(paragraphAfter.width == document.width)
        #expect(zoomed.height == heightBefore)
        #expect(zoomed.textWidth == textWidthBefore)
        expectIncrementalMatchesFull(page)
    }

    // MARK: - Embedded content

    @Test func lazyImageLoadChangesBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="photo"></p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
                """
        )
        let image: Element = try element("photo", in: page)
        let layout: ImageLayout = try #require(
            page.firstLayout(ImageLayout.self, in: image)
        )
        #expect(layout.width == 0)

        image.image = makeImage(width: 40, height: 30)
        LayoutInvalidation.imageChanged(image)
        page.frame.setNeedsLayout()
        page.frame.render()

        let after: ImageLayout = try #require(
            page.firstLayout(ImageLayout.self, in: image)
        )
        #expect(after.width == CGFloat(40))
        #expect(after.height >= CGFloat(30))
        expectIncrementalMatchesFull(page)
    }

    // MARK: - DOM structure

    @Test func innerHTMLRebuildsOnlyTargetBlock() throws {
        let css: String = """
            body { display: block; }
            div { display: block; }
            p { display: block; width: 180px; }
            """
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="left"><p id="old">old</p></div>
                <div id="right"><p>right</p></div>
                """,
            rules: css
        )
        let left: Element = try element("left", in: page)
        let right: Element = try element("right", in: page)
        let leftBefore: any LayoutObject = try #require(left.layoutObject)
        let rightBefore: any LayoutObject = try #require(right.layoutObject)

        let js: JSRuntime = JSRuntime(frame: page.frame)
        page.frame.js = js
        js.run(
            script: "test",
            code: #"document.getElementById("left").innerHTML = "<p id='new'>new text</p>";"#
        )
        // The JS DOM helpers reload stylesheets, which drops rules that were
        // installed directly by the test instead of through a <style> element.
        page.frame.rules = CSSParser(css).parse().rules
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(left.layoutObject === leftBefore)
        #expect(right.layoutObject === rightBefore)
        let rebuilt: Element = try element("new", in: page)
        #expect(rebuilt.layoutObject != nil)
        expectIncrementalMatchesFull(page)
    }

    @Test func appendChildRebuildsParentChildren() throws {
        let css: String = """
            body { display: block; }
            div { display: block; }
            p { display: block; }
            """
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="target"><p>one</p></div>
                <div id="sibling">side</div>
                """,
            rules: css
        )
        let target: Element = try element("target", in: page)
        let sibling: Element = try element("sibling", in: page)
        let targetBlock: BlockLayout = try #require(target.layoutObject as? BlockLayout)
        let siblingBefore: any LayoutObject = try #require(sibling.layoutObject)
        #expect(targetBlock.children.count == 1)

        let js: JSRuntime = JSRuntime(frame: page.frame)
        page.frame.js = js
        js.run(
            script: "test",
            code: """
                var added = document.createElement("p");
                added.textContent = "two";
                document.getElementById("target").appendChild(added);
                """
        )
        page.frame.rules = CSSParser(css).parse().rules
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(target.children.count == 2)
        #expect(targetBlock.children.count == 2)
        #expect(sibling.layoutObject === siblingBefore)
        expectIncrementalMatchesFull(page)
    }

    // MARK: - Caret and field lifecycle

    @Test func contenteditableCaretFollowsText() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="edit" contenteditable="true">hello</p>"#,
            rules: """
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
        let editable: Element = try element("edit", in: page)
        let text: TextNode = try #require(editable.children.first as? TextNode)
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.focusElement(editable)
        page.frame.render()
        let before: CGFloat = try #require(caretX(in: page.frame))

        page.frame.keypress("x")
        page.frame.render()
        let after: CGFloat = try #require(caretX(in: page.frame))

        #expect(text.text.hasSuffix("x"))
        #expect(after > before)
        expectIncrementalMatchesFull(page)
    }

    @Test func noDirtyFieldAfterRender() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">words <button>Go</button> <input type="text"></div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                button { display: inline; }
                """
        )
        let box: Element = try element("box", in: page)

        InlineStyle.set(box, property: "width", value: "240px")
        page.frame.setNeedsRender()
        page.frame.render()

        let document: DocumentLayout = try #require(page.frame.document)
        expectAllLayoutFieldsClean(document)
        for node in treeToList(page.frame.nodes) {
            #expect(!node.style.isDirty)
        }
        expectIncrementalMatchesFull(page)
    }
}

@MainActor
private func element(_ id: String, in page: LayoutTestPage) throws -> Element {
    return try #require(
        treeToList(page.frame.nodes)
            .compactMap({ $0 as? Element })
            .first(where: { $0.attributes["id"] == id })
    )
}

@MainActor
private func caretX(in frame: Frame) -> CGFloat? {
    frame.setNeedsPaint()
    frame.paint()
    return frame.displayList
        .compactMap({ $0 as? DrawLine })
        .last(where: { $0.color == "red" })?
        .rect.left
}

private func makeImage(width: Int, height: Int) -> CGImage {
    let context: CGContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
