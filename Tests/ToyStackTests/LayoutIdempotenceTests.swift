import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutIdempotenceTests {

    @Test func secondLayoutIsIdentical() throws {
        let fixture: Fixture = makeFixture()
        var document: LayoutTree = try #require(fixture.frame.document)

        let first: [Snapshot] = snapshot(of: document.rootID, in: document)

        let zoom: CGFloat = document.zoom(document.rootID)
        let pageZoom: CGFloat = document.documentData(document.rootID).pageZoom
        profiler.reset()
        markAllFields(document.rootID, in: &document)
        document.layoutDocument(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(snapshot(of: document.rootID, in: document) == first)
    }

    @Test func redundantLayoutKeepsBlockIdentity() throws {
        let fixture: Fixture = makeFixture()
        var document: LayoutTree = try #require(fixture.frame.document)

        let objectsBefore: [LayoutID] = blockIDs(of: document.rootID, in: document)
        let first: [Snapshot] = snapshot(of: document.rootID, in: document)

        let zoom: CGFloat = document.zoom(document.rootID)
        let pageZoom: CGFloat = document.documentData(document.rootID).pageZoom
        profiler.reset()
        markAllFields(document.rootID, in: &document)
        document.layoutDocument(
            availableWidth: fixture.frame.frameWidth,
            zoom: zoom,
            pageZoom: pageZoom
        )

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(blockIDs(of: document.rootID, in: document) == objectsBefore)
        #expect(snapshot(of: document.rootID, in: document) == first)
    }

    @Test func buttonKeepsOneLinePerLayout() throws {
        let fixture: Fixture = makeFixture()
        var document: LayoutTree = try #require(fixture.frame.document)
        let button: LayoutID = try #require(
            treeToList(document, document.rootID).first(where: {
                guard document.isEmbed($0) else { return false }
                return EmbedMatch.button.matches(document.embedData($0))
            })
        )

        let first: [Snapshot] = snapshot(of: button, in: document)

        profiler.reset()
        document.markField(.width, at: button)
        document.layout(button)

        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) > 0)
        #expect(snapshot(of: button, in: document) == first)
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
    let button: NodeID
}

@MainActor
private func makeFixture() -> Fixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
    let frame: Frame = tab.rootFrame
    let builder: DOMBuilder = DOMBuilder()
    let body: NodeID = builder.element("body", in: builder.dom.root)
    let section: NodeID = builder.element("section", in: body)
    let article: NodeID = builder.element("article", in: body)

    builder.text("before ", in: section)
    let button: NodeID = builder.element("button", in: section)
    builder.text(" after", in: section)
    builder.element("br", in: section)
    builder.text("Go", in: button)
    builder.text("block text that wraps", in: article)

    frame.replaceDOM(builder.dom)
    frame.setStyleRules(CSSParser("""
        html { width: 240px; }
        body { display: block; }
        section { display: block; }
        article { display: block; }
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    return Fixture(tab: tab, frame: frame, button: button)
}

@MainActor
private func snapshot(of id: LayoutID, in tree: LayoutTree) -> [Snapshot] {
    var result: [Snapshot] = []
    appendSnapshot(id, in: tree, path: "0", into: &result)
    return result
}

@MainActor
private func appendSnapshot(
    _ id: LayoutID,
    in tree: LayoutTree,
    path: String,
    into result: inout [Snapshot]
) {
    let children: [LayoutID] = tree.childrenIDs(of: id)
    result.append(
        Snapshot(
            path: path,
            kind: layoutKindName(tree.kind(id)),
            rect: tree.selfRect(id),
            childCount: children.count
        )
    )

    for (index, child) in children.enumerated() {
        appendSnapshot(child, in: tree, path: "\(path).\(index)", into: &result)
    }
}

@MainActor
private func blockIDs(of id: LayoutID, in tree: LayoutTree) -> [LayoutID] {
    return treeToList(tree, id).filter({ tree.isBlock($0) })
}

@MainActor
private func markAllFields(_ id: LayoutID, in tree: inout LayoutTree) {
    tree.markField(.x, at: id)
    tree.markField(.y, at: id)
    tree.markField(.width, at: id)
    tree.markField(.height, at: id)
    tree.markField(.zoom, at: id)
    for child in tree.childrenIDs(of: id) {
        markAllFields(child, in: &tree)
    }
}
