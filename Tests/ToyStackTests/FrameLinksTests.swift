import Testing

@testable import Engine

@Suite
@MainActor
struct FrameLinksTests {
    @Test func childFrameResolvesItsParentThroughTheTab() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let root: Frame = try #require(tab.rootFrame)
        let iframe: NodeID = root.dom.createElement(tag: "iframe", attributes: [:])
        root.dom.append(iframe, to: root.dom.root)

        let child: Frame = Frame(
            tab: tab,
            parent: FrameParent(frame: root, element: iframe),
            frameWidth: 100,
            frameHeight: 50
        )

        #expect(tab.frame(child.links.id) === child)
        #expect(child.parentFrame === root)
        #expect(child.frameElement == iframe)
        #expect(child.windowID == child.links.id.raw)
    }
}
