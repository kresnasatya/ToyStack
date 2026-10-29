import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutIdempotenceTests {

    @Test func secondLayoutIsIdentical() throws {
        let fixture: Fixture = makeFixture()
        let document: DocumentLayout = try #require(fixture.frame.document)

        let first: [Snapshot] = snapshot(of: document)

        let zoom: CGFloat = document.zoom
        let pageZoom: CGFloat = document.pageZoom
        profiler.reset()
        markAllFields(document)
        document.layout(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(snapshot(of: document) == first)
    }

    @Test func redundantLayoutKeepsBlockIdentity() throws {
        let fixture: Fixture = makeFixture()
        let document: DocumentLayout = try #require(fixture.frame.document)

        let objectsBefore: [ObjectIdentifier] = blockIDs(of: document)
        let first: [Snapshot] = snapshot(of: document)

        let zoom: CGFloat = document.zoom
        let pageZoom: CGFloat = document.pageZoom
        profiler.reset()
        markAllFields(document)
        document.layout(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(blockIDs(of: document) == objectsBefore)
        #expect(snapshot(of: document) == first)
    }

    @Test func buttonKeepsOneLinePerLayout() throws {
        let fixture: Fixture = makeFixture()
        let document: DocumentLayout = try #require(fixture.frame.document)
        let button: ButtonLayout = try #require(treeToList(document).compactMap({ $0 as? ButtonLayout }).first)

        let first: [Snapshot] = snapshot(of: button)

        profiler.reset()
        button.widthField.mark()
        button.layout()

        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) > 0)
        #expect(snapshot(of: button) == first)
    }
}

private struct Snapshot: Equatable {
    let path: String
    let kind: String
    let rect: Rect
    let childCount: Int
}

@MainActor
private struct Fixture {
    let tab: BrowserTab
    let frame: Frame
    let button: Element
}

@MainActor
private func makeFixture() -> Fixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
    let frame: Frame = tab.rootFrame!
    let html: Element = Element(tag: "html", attributes: [:], parent: nil)
    let body: Element = Element(tag: "body", attributes: [:], parent: html)
    let section: Element = Element(tag: "section", attributes: [:], parent: body)
    let article: Element = Element(tag: "article", attributes: [:], parent: body)
    let button: Element = Element(tag: "button", attributes: [:], parent: section)

    let before: TextNode = TextNode(text: "before ", parent: section)
    let after: TextNode = TextNode(text: " after", parent: section)
    let label: TextNode = TextNode(text: "Go", parent: button)
    let prose: TextNode = TextNode(text: "block text that wraps", parent: article)
    let br: Element = Element(tag: "br", attributes: [:], parent: section)

    section.children = [before, button, after, br]
    button.children = [label]
    article.children = [prose]
    body.children = [section, article]
    html.children = [body]

    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 240px; }
        body { display: block; }
        section { display: block; }
        article { display: block; }
        """).parse().rules
    frame.setNeedsRender()
    frame.render()
    return Fixture(tab: tab, frame: frame, button: button)
}

@MainActor
private func snapshot(of object: any LayoutObject) -> [Snapshot] {
    var result: [Snapshot] = []
    appendSnapshot(object, path: "0", into: &result)
    return result
}

@MainActor
private func appendSnapshot(
    _ object: any LayoutObject,
    path: String,
    into result: inout [Snapshot]
) {
    result.append(
        Snapshot(
            path: path,
            kind: String(describing: type(of: object)),
            rect: object.selfRect(),
            childCount: object.children.count
        )
    )

    for (index, child) in object.children.enumerated() {
        appendSnapshot(child, path: "\(path).\(index)", into: &result)
    }
}

@MainActor
private func blockIDs(of object: any LayoutObject) -> [ObjectIdentifier] {
    return treeToList(object).compactMap({ $0 as? BlockLayout }).map({ ObjectIdentifier($0) })
}

@MainActor
private func markAllFields(_ object: any LayoutObject) {
    object.xField.mark()
    object.yField.mark()
    object.widthField.mark()
    object.heightField.mark()
    object.zoomField.mark()
    for child in object.children {
        markAllFields(child)
    }
}
