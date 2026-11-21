import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutInputsCacheTests {

    @Test func widthResizeReusesLayoutInputs() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">one two three four</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; width: 300px; }
                """
        )

        page.frame.setViewport(width: 500, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.inputs.reused"]?.count ?? 0) > 0)
        #expect(metrics["layout.inputs.rebuilt"] == nil)
    }

    @Test func styleChangeRebuildsOnlyTouchedInputs() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">text</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))

        box.style.mutate({ style in
            style.text.color = BrowserColor(cssName: "blue")
        })
        page.frame.setNeedsLayout()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.inputs.style"]?.count ?? 0) > 0)
        #expect((metrics["layout.inputs.reused"]?.count ?? 0) > 0)
        #expect(box.style.computed.text.color == BrowserColor(cssName: "blue"))
    }

    @Test func textEditRebuildsOnlyTheEditedText() throws {
        let html: String = (0..<20).map({ "<p id=\"p\($0)\">paragraph \($0)</p>" }).joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
                """
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p7"))
        let text: TextRef = try #require(paragraph.children.first?.text)

        text.append(" more")
        page.frame.setNeedsRender()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.inputs.rebuilt"]?.count == 1)
        #expect((metrics["layout.inputs.reused"]?.count ?? 0) > 20)
        #expect(page.tree.inputs.text(text.ref.id) == "paragraph 7 more")
        expectIncrementalMatchesFull(page)
    }

    @Test func appendedElementIsBuiltAndItsParentListsIt() throws {
        let dom: DOMTree = HTMLParser(body: #"<div id="box"><p>one</p></div>"#).parse()
        let first: LayoutInputs = LayoutInputsBuilder.build(dom: dom)
        let box: NodeID = try #require(elementID("box", in: dom))

        let added: NodeID = dom.createElement(tag: "p", attributes: ["id": "two"])
        dom.append(added, to: box)
        let second: LayoutInputs = LayoutInputsBuilder.build(dom: dom, previous: first)

        #expect(second.allChildren(box).last == added)
        #expect(second.tag(added) == "p")
        #expect(second.parent(added) == box)
    }

    @Test func buildingFromOlderInputsCatchesEveryChangeSinceThem() throws {
        let dom: DOMTree = HTMLParser(body: #"<p id="a">one</p><p id="b">two</p>"#).parse()
        let a: NodeID = try #require(elementID("a", in: dom))
        let b: NodeID = try #require(elementID("b", in: dom))
        let aText: NodeID = try #require(dom.children(of: a).first)
        let older: LayoutInputs = LayoutInputsBuilder.build(dom: dom)

        dom.setText("changed", of: aText)
        _ = LayoutInputsBuilder.build(dom: dom, previous: older)
        dom.setAttribute("title", "late", of: b)
        dom.setFlag(\.isFocused, true, of: b)
        let latest: LayoutInputs = LayoutInputsBuilder.build(dom: dom, previous: older)

        #expect(latest.text(aText) == "changed")
        #expect(latest.attributes(b)["title"] == "late")
        #expect(latest.isFocused(b))
    }

    @Test func textFollowsAFontWrittenOnlyToItsParent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">one two</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
                """
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))
        let text: TextRef = try #require(paragraph.children.first?.text)

        paragraph.style.mutate({ style in
            style.text.font.size = 40
        })
        page.frame.setNeedsLayout()
        page.frame.render()

        #expect(page.tree.inputs.font(text.ref.id).size == 40)
    }

    @Test func imageChangeRebuildsInputs() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<img id="pic" src="missing.png">"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                img { display: block; width: 20px; height: 20px; }
                """
        )
        let image: ElementRef = try #require(page.firstElement(id: "pic"))

        image.image = makeTestImage()
        LayoutInvalidation.imageChanged(image.ref)
        page.frame.setNeedsLayout()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.inputs.reused"] == nil)
    }
}

@MainActor
private func elementID(_ id: String, in dom: DOMTree) -> NodeID? {
    var found: NodeID? = nil
    dom.forEachNode({ node in
        if found == nil, dom.ref(node).element?.attributes["id"] == id {
            found = node
        }
    })
    return found
}

private func makeTestImage() -> CGImage {
    let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let pixels: [UInt8] = [255, 0, 0, 255]
    let provider: CGDataProvider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
