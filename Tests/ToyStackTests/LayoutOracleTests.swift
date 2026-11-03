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
        let first: ElementRef = try element("first", in: page)
        let second: ElementRef = try element("second", in: page)
        let text: TextRef = try #require(first.children.first?.text)
        let secondBefore: LayoutRef = try #require(page.ref(of: second).layout)

        text.append(" more words that wrap")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let secondAfter: LayoutRef = try #require(page.ref(of: second).layout)
        #expect(secondAfter.id == secondBefore.id)
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
        let first: ElementRef = try element("first", in: page)
        let text: TextRef = try #require(first.children.first?.text)

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
        let parent: ElementRef = try element("parent", in: page)
        let child: ElementRef = try element("child", in: page)
        let block: LayoutRef = try #require(page.ref(of: parent).layout)
        #expect(!block.children.contains(where: { $0.isLine }))

        InlineStyle.set(child, property: "display", value: "inline")
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutRef = try #require(page.ref(of: parent).layout)
        #expect(after.id == block.id)
        #expect(after.children.contains(where: { $0.isLine }))

        InlineStyle.set(child, property: "display", value: "block")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(!after.children.contains(where: { $0.isLine }))
        #expect(after.children.contains(where: { $0.isBlock }))
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
        let box: ElementRef = try element("box", in: page)
        let paragraph: ElementRef = try element("para", in: page)
        let boxBlock: LayoutRef = try #require(page.ref(of: box).layout)
        let paragraphBlock: LayoutRef = try #require(
            page.ref(of: paragraph).layout
        )
        #expect(paragraphBlock.width == boxBlock.width)

        InlineStyle.set(box, property: "width", value: "240px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(boxBlock.width == CGFloat(240))
        let paragraphAfter: LayoutRef = try #require(
            page.ref(of: paragraph).layout
        )
        #expect(paragraphAfter.width == CGFloat(240))
        let line: LayoutRef = try #require(
            paragraphAfter.children.first(where: { $0.isLine })
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
        let document: LayoutTree = try #require(page.frame.document)
        #expect(document.root.width == page.frame.frameWidth - 2 * HSTEP)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let body: ElementRef = try #require(page.firstElement(tag: "body"))
        let bodyBlock: LayoutRef = try #require(page.ref(of: body).layout)
        #expect(document.root.width == CGFloat(400) - 2 * HSTEP)
        #expect(bodyBlock.width == document.root.width)
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
        let paragraph: ElementRef = try element("para", in: page)
        let block: LayoutRef = try #require(page.ref(of: paragraph).layout)
        let text: LayoutRef = try #require(
            treeToList(block).first(where: { $0.isText })
        )
        let heightBefore: CGFloat = text.height
        let textWidthBefore: CGFloat = text.textData.metrics.width

        page.frame.setPageZoom(2)
        page.frame.render()

        let document: LayoutTree = try #require(page.frame.document)
        let paragraphAfter: LayoutRef = try #require(
            page.ref(of: paragraph).layout
        )
        let zoomed: LayoutRef = try #require(
            treeToList(paragraphAfter).first(where: { $0.isText })
        )
        // Page zoom shrinks the layout viewport and is applied at paint time;
        // it is not a layout `zoom` field.
        #expect(document.root.zoom == CGFloat(1))
        #expect(document.root.documentData.pageZoom == CGFloat(2))
        #expect(document.root.width == page.frame.frameWidth - 2 * HSTEP)
        #expect(paragraphAfter.width == document.root.width)
        #expect(zoomed.height == heightBefore)
        #expect(zoomed.textData.metrics.width == textWidthBefore)
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
        let image: ElementRef = try element("photo", in: page)
        let layout: LayoutRef = try #require(
            page.firstEmbed(in: image)
        )
        #expect(layout.width == 0)

        image.image = makeImage(width: 40, height: 30)
        LayoutInvalidation.imageChanged(page.ref(of: image))
        page.frame.setNeedsLayout()
        page.frame.render()

        let after: LayoutRef = try #require(
            page.firstEmbed(in: image)
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
        let left: ElementRef = try element("left", in: page)
        let right: ElementRef = try element("right", in: page)
        let leftBefore: LayoutRef = try #require(page.ref(of: left).layout)
        let rightBefore: LayoutRef = try #require(page.ref(of: right).layout)

        let js: JSRuntime = JSRuntime(frame: page.frame)
        page.frame.setJSRuntime(js)
        js.run(
            script: "test",
            code: #"document.getElementById("left").innerHTML = "<p id='new'>new text</p>";"#
        )
        // The JS DOM helpers reload stylesheets, which drops rules that were
        // installed directly by the test instead of through a <style> element.
        page.frame.setStyleRules(CSSParser(css).parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(page.ref(of: left).layout?.id == leftBefore.id)
        #expect(page.ref(of: right).layout?.id == rightBefore.id)
        let rebuilt: ElementRef = try element("new", in: page)
        #expect(page.ref(of: rebuilt).layout != nil)
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
        let target: ElementRef = try element("target", in: page)
        let sibling: ElementRef = try element("sibling", in: page)
        let targetBlock: LayoutRef = try #require(page.ref(of: target).layout)
        let siblingBefore: LayoutRef = try #require(page.ref(of: sibling).layout)
        #expect(targetBlock.children.count == 1)

        let js: JSRuntime = JSRuntime(frame: page.frame)
        page.frame.setJSRuntime(js)
        js.run(
            script: "test",
            code: """
                var added = document.createElement("p");
                added.textContent = "two";
                document.getElementById("target").appendChild(added);
                """
        )
        page.frame.setStyleRules(CSSParser(css).parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(target.children.count == 2)
        #expect(targetBlock.children.count == 2)
        #expect(page.ref(of: sibling).layout?.id == siblingBefore.id)
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
        let editable: ElementRef = try element("edit", in: page)
        let text: TextRef = try #require(editable.children.first?.text)
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

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
        let box: ElementRef = try element("box", in: page)

        InlineStyle.set(box, property: "width", value: "240px")
        page.frame.setNeedsRender()
        page.frame.render()

        let document: LayoutTree = try #require(page.frame.document)
        expectAllLayoutFieldsClean(document)
        for node in treeToList(page.frame.nodes) {
            #expect(!node.style.isDirty)
        }
        expectIncrementalMatchesFull(page)
    }
}

@MainActor
private func element(_ id: String, in page: LayoutTestPage) throws -> ElementRef {
    return try #require(
        treeToList(page.frame.nodes)
            .compactMap({ $0.element })
            .first(where: { $0.attributes["id"] == id })
    )
}

@MainActor
private func caretX(in frame: Frame) -> CGFloat? {
    frame.setNeedsPaint()
    frame.paint()
    for op in frame.displayList.reversed() {
        if case .line(let from, _, let color, _) = op, color == BrowserColor(cssName: "red") {
            return from.x
        }
    }
    return nil
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
