import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutIdempotenceTests {

    @Test func secondLayoutIsIdentical() throws {
        let fixture: Fixture = makeFixture()
        let document: LayoutTree = try #require(fixture.frame.document)

        let first: [Snapshot] = snapshot(of: document.root)

        let zoom: CGFloat = document.root.zoom
        let pageZoom: CGFloat = document.root.documentData.pageZoom
        profiler.reset()
        markAllFields(document.root)
        document.layoutDocument(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(snapshot(of: document.root) == first)
    }

    @Test func redundantLayoutKeepsBlockIdentity() throws {
        let fixture: Fixture = makeFixture()
        let document: LayoutTree = try #require(fixture.frame.document)

        let objectsBefore: [LayoutID] = blockIDs(of: document.root)
        let textsBefore: [LayoutRef] = blockTexts(in: document.root)
        let textIDsBefore: [LayoutID] = textsBefore.map({ $0.id })
        let first: [Snapshot] = snapshot(of: document.root)

        let zoom: CGFloat = document.root.zoom
        let pageZoom: CGFloat = document.root.documentData.pageZoom
        profiler.reset()
        markAllFields(document.root)
        document.layoutDocument(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(blockIDs(of: document.root) == objectsBefore)
        #expect(blockTextIDs(of: document.root) == textIDsBefore)
        #expect(snapshot(of: document.root) == first)
        withExtendedLifetime(textsBefore) {}
    }

    @Test func buttonKeepsOneLinePerLayout() throws {
        let fixture: Fixture = makeFixture()
        let document: LayoutTree = try #require(fixture.frame.document)
        let button: LayoutRef = try #require(
            treeToList(document.root).first(where: {
                guard $0.isEmbed else { return false }
                return EmbedMatch.button.matches($0.embedData)
            })
        )

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
private func snapshot(of object: LayoutRef) -> [Snapshot] {
    var result: [Snapshot] = []
    appendSnapshot(object, path: "0", into: &result)
    return result
}

@MainActor
private func appendSnapshot(
    _ object: LayoutRef,
    path: String,
    into result: inout [Snapshot]
) {
    result.append(
        Snapshot(
            path: path,
            kind: layoutKindName(object.kind),
            rect: object.selfRect(),
            childCount: object.children.count
        )
    )

    for (index, child) in object.children.enumerated() {
        appendSnapshot(child, path: "\(path).\(index)", into: &result)
    }
}

@MainActor
private func blockIDs(of object: LayoutRef) -> [LayoutID] {
    return treeToList(object).filter({ $0.isBlock }).map({ $0.id })
}

@MainActor
private func textIDs(of object: LayoutRef) -> [LayoutID] {
    return treeToList(object).filter({ $0.isText }).map({ $0.id })
}

@MainActor
private func blockTexts(in object: LayoutRef) -> [LayoutRef] {
    return treeToList(object)
        .filter({ $0.isText })
        .filter { text in
            guard let line = text.parent else { return false }
            return line.isLine && line.parent?.isBlock == true
        }
}

@MainActor
private func blockTextIDs(of object: LayoutRef) -> [LayoutID] {
    return blockTexts(in: object).map { $0.id }
}

@MainActor
private func markAllFields(_ object: LayoutRef) {
    object.xField.mark()
    object.yField.mark()
    object.widthField.mark()
    object.heightField.mark()
    object.zoomField.mark()
    for child in object.children {
        markAllFields(child)
    }
}
