import CoreGraphics
import Testing

@testable import Engine

@Suite
@MainActor
struct InlineBoxTests {

    @Test func paintSceneUsesBoxesForTextLines() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>Hello world</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let tree: LayoutTree = page.tree
        var builder: PaintSceneBuilder = PaintSceneBuilder()
        _ = builder.build(root: tree.rootID, tree: tree, frame: page.frame)
        let nodes: [PaintNode] = try #require(builder.sink.scenes.first?.nodes)
        let lineWithBoxes: Bool = nodes.contains { node in
            guard case .line(let line) = node.content else { return false }
            return !line.inlineText.isEmpty
        }
        #expect(lineWithBoxes)
        let lineWithTextChildren: Bool = nodes.contains { node in
            guard case .line = node.content else { return false }
            return node.links.children.contains { child in
                if case .text = nodes[child].content { return true }
                return false
            }
        }
        #expect(!lineWithTextChildren)
    }

    @Test func hitTestAndAccessibilityUseLineBoxes() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><a id="link" href="/x">link text</a></p>"#,
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let link: ElementRef = try #require(page.firstElement(id: "link"))
        let textNode: DOMRef = try #require(link.children.first(where: { $0.text != nil }))
        let tree: LayoutTree = page.tree
        let box: InlineBox = try #require(tree.inlineBoxes(for: textNode.id).first)
        let x: CGFloat = box.geometry.x + 1
        let y: CGFloat = box.geometry.y + 1
        let hit: LayoutHit? = tree.hitTest(tree.rootID, x: x, y: y)

        #expect(hit?.dom == textNode.id)
        #expect(tree.linkHref(tree.rootID, x: x, y: y) == "/x")

        let node: AccessibilityNode = AccessibilityNode(node: textNode)
        #expect(abs(node.bounds.left - box.geometry.x) < 0.01)
        #expect(abs(node.bounds.top - box.geometry.y) < 0.01)
    }

    @Test func boxRevisionTracksInlineContent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">one two</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))
        let line: LayoutID = try #require(page.firstLineID(in: paragraph))
        let block: LayoutID = try #require(page.tree.parentID(of: line))
        #expect(page.tree.lineData(line).paint.boxRevision == page.tree.inlineContent(block))
    }

    @Test func textEditRefreshesBoxes() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">one two</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))
        let text: TextRef = try #require(paragraph.children.first?.text)
        text.append(" three four")
        page.frame.setNeedsRender()
        page.frame.render()
        let line: LayoutID = try #require(page.firstLineID(in: paragraph))
        let boxes: [InlineBox] = page.tree.lineData(line).content.boxes
        let content: String = boxes.map({ page.tree.inlineText($0) }).joined()
        #expect(content.contains("three four"))
    }

    @Test func fontSizeChangeRefreshesBoxMetrics() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">one two three four</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))
        let beforeLine: LayoutID = try #require(page.firstLineID(in: paragraph))
        let before: CGFloat = page.tree.lineData(beforeLine).content.boxes.reduce(0, { $0 + $1.geometry.width })
        paragraph.attributes["style"] = "font-size: 32px;"
        page.frame.setNeedsRender()
        page.frame.render()
        let afterLine: LayoutID = try #require(page.firstLineID(in: paragraph))
        let after: CGFloat = page.tree.lineData(afterLine).content.boxes.reduce(0, { $0 + $1.geometry.width })
        #expect(after > before)
    }

    @Test func verticalMoveRefreshesBoxY() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="first">one</p><p id="second">two</p>"#,
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let second: ElementRef = try #require(page.firstElement(id: "second"))
        let beforeLine: LayoutID = try #require(page.firstLineID(in: second))
        let beforeY: CGFloat = try #require(
            page.tree.lineData(beforeLine).content.boxes.first.map({
                page.tree.y(beforeLine) + $0.geometry.y
            })
        )
        let first: ElementRef = try #require(page.firstElement(id: "first"))
        first.attributes["style"] = "margin-top: 40px;"
        page.frame.setNeedsRender()
        page.frame.render()
        let afterLine: LayoutID = try #require(page.firstLineID(in: second))
        let afterY: CGFloat = try #require(
            page.tree.lineData(afterLine).content.boxes.first.map({
                page.tree.y(afterLine) + $0.geometry.y
            })
        )
        #expect(afterY > beforeY)
    }

    @Test func boxRevisionChangesWithLineGeometry() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>Hello world this is a long line</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let beforeLine: LayoutID = try #require(page.firstLineID(in: paragraph))
        let before: UInt = page.tree.lineData(beforeLine).paint.generation
        page.frame.setViewport(width: 220, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()
        let afterLine: LayoutID = try #require(page.firstLineID(in: paragraph))
        let after: UInt = page.tree.lineData(afterLine).paint.generation
        #expect(after != before)
    }

    @Test func lineBoxesMatchTextChildren() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>Hello world this is a line with enough words to wrap.</p>",
            rules: "body { display: block; font-size: 20px; } p { display: block; }"
        )
        page.withTree { tree in
            tree.collectsInlineBoxes = true
        }
        page.frame.setViewport(width: 320, height: 600)
        page.frame.setNeedsViewportResize()
        page.frame.render()
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let line: LayoutID = try #require(page.firstLineID(in: paragraph))
        let tree: LayoutTree = page.tree
        let children: [LayoutID] = tree.childrenIDs(of: line).filter({ tree.isText($0) })
        let boxes: [InlineBox] = tree.lineData(line).content.boxes

        #expect(!boxes.isEmpty)
        if children.isEmpty {
            #expect(boxes.allSatisfy({ $0.geometry.width > 0 }))
        } else {
            #expect(boxes.count == children.count)
            for (box, child) in zip(boxes, children) {
                let data: TextData = tree.textData(child)
                #expect(box.dom == tree.domID(of: child))
                #expect(box.fragment == data.fragment)
                #expect(box.geometry.x == tree.x(child))
                #expect(tree.y(line) + box.geometry.y == tree.textAbsoluteY(child))
                #expect(box.geometry.width == tree.textTextWidth(child))
            }
        }
    }
}
