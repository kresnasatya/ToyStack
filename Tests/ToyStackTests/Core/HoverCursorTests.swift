import Combine
import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HoverCursorTests {

    @Test func linkWithHrefShowsPointer() throws {
        let page: LayoutTestPage = Self.page(html: #"<div><a id="link" href="/x">go somewhere</a></div>"#)

        try Self.hover(page, overTextOf: "link")

        #expect(page.tab.cursor == .pointer)
    }

    @Test func anchorWithoutHrefKeepsTheDefaultCursor() throws {
        let page: LayoutTestPage = Self.page(html: #"<div><a id="name">just a name</a></div>"#)

        try Self.hover(page, overTextOf: "name")

        #expect(page.tab.cursor == .auto)
    }

    @Test func buttonKeepsTheArrowLikeRealBrowsers() throws {
        let page: LayoutTestPage = Self.page(html: #"<div><button id="save">Save</button></div>"#)
        let button: ElementRef = try #require(page.firstElement(id: "save"))

        Self.hover(page, at: try Self.center(of: button, in: page))

        #expect(page.tab.cursor == .auto)
    }

    @Test func pageStylesCanGiveButtonsAPointer() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div><button id="save">Save</button></div>"#,
            rules: "button { cursor: pointer; }"
        )
        let button: ElementRef = try #require(page.firstElement(id: "save"))

        Self.hover(page, at: try Self.center(of: button, in: page))

        #expect(page.tab.cursor == .pointer)
    }

    @Test func declaredPointerIsInheritedByDescendants() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div id="card"><span id="label">open card</span></div>"#,
            rules: "#card { cursor: pointer; }"
        )

        try Self.hover(page, overTextOf: "label")

        #expect(page.tab.cursor == .pointer)
    }

    @Test func descendantCanOptOutOfAnInheritedPointer() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div><a href="/x"><span id="plain">not clickable look</span></a></div>"#,
            rules: "#plain { cursor: default; }"
        )

        try Self.hover(page, overTextOf: "plain")

        #expect(page.tab.cursor == .default)
    }

    @Test func explicitAutoResetsAnInheritedPointer() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div id="card"><span id="label">text</span></div>"#,
            rules: "#card { cursor: pointer; } #label { cursor: auto; }"
        )

        try Self.hover(page, overTextOf: "label")

        #expect(page.tab.cursor == .auto)
    }

    @Test func unsupportedValueFallsBackToTheInheritedCursor() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div id="card"><span id="label">text</span></div>"#,
            rules: "#card { cursor: pointer; } #label { cursor: banana; }"
        )

        try Self.hover(page, overTextOf: "label")

        #expect(page.tab.cursor == .pointer)
    }

    @Test func cursorKeywordsIgnoreLetterCase() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div id="card">text</div>"#,
            rules: "#card { cursor: Pointer; }"
        )
        let card: ElementRef = try #require(page.firstElement(id: "card"))

        Self.hover(page, at: try Self.center(of: card, in: page))

        #expect(page.tab.cursor == .pointer)
    }

    @Test func hoverRuleChangesTheCursorOnceTheRestyleLands() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div id="card">text</div>"#,
            rules: "#card:hover { cursor: pointer; }"
        )
        let card: ElementRef = try #require(page.firstElement(id: "card"))

        Self.hover(page, at: try Self.center(of: card, in: page))

        page.frame.render()

        #expect(page.tab.cursor == .pointer)
    }

    @Test func styleChangeUnderAStillPointerUpdatesTheCursor() throws {
        let page: LayoutTestPage = Self.page(html: #"<div id="card">text</div>"#)
        let card: ElementRef = try #require(page.firstElement(id: "card"))
        Self.hover(page, at: try Self.center(of: card, in: page))
        #expect(page.tab.cursor == .auto)

        InlineStyle.set(card, property: "cursor", value: "pointer")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(page.tab.cursor == .pointer)
    }

    @Test func movingOffTheLinkRestoresTheDefaultCursor() throws {
        let page: LayoutTestPage = Self.page(
            html: #"<div><a id="link" href="/x">link</a></div><div id="after">plain text</div>"#
        )
        try Self.hover(page, overTextOf: "link")
        #expect(page.tab.cursor == .pointer)

        try Self.hover(page, overTextOf: "after")

        #expect(page.tab.cursor == .auto)
    }

    @Test func leavingThePageRestoresTheDefaultCursor() throws {
        let page: LayoutTestPage = Self.page(html: #"<div><a id="link" href="/x">link</a></div>"#)
        try Self.hover(page, overTextOf: "link")
        #expect(page.tab.cursor == .pointer)

        page.tab.clearHover()

        #expect(page.tab.cursor == .auto)
    }

    @Test func browserPublishesEachCursorChangeOnce() async throws {
        let pagePath: String = NSTemporaryDirectory() + "hover-cursor-\(UUID().uuidString).html"
        defer { try? FileManager.default.removeItem(atPath: pagePath) }
        try #"<div><a id="link" href="/x">a link</a></div><div id="after">plain text</div>"#
            .write(toFile: pagePath, atomically: true, encoding: .utf8)
        let browser: Browser = Browser()
        defer { browser.stopAnimationTimer() }
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()
        var reported: [CursorKind] = []
        let subscription: AnyCancellable = browser.$cursor.dropFirst().sink { (kind: CursorKind) in
            reported.append(kind)
        }
        defer { subscription.cancel() }
        #expect(await Self.pump({ browser.activeTab?.isLoaded == true }))
        browser.advanceFrame()
        let tab: BrowserTab = try #require(browser.activeTab)
        let zoom: CGFloat = browser.pageZoom
        let link: CGPoint = try Self.textCenter(of: "link", in: tab.rootFrame)
        let after: CGPoint = try Self.textCenter(of: "after", in: tab.rootFrame)

        browser.handleHover(x: link.x * zoom, y: link.y * zoom)
        browser.advanceFrame()
        browser.handleHover(x: link.x * zoom + 1, y: link.y * zoom)
        browser.advanceFrame()
        browser.handleHover(x: after.x * zoom, y: after.y * zoom)
        browser.advanceFrame()

        #expect(reported == [.pointer, .auto])
        #expect(browser.cursor == .auto)
    }

    // MARK: - Helpers

    private static func page(html: String, rules: String = "") -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: "")
        page.frame.setStyleRules(defaultStyleSheet + CSSParser("html { width: 600px; } " + rules).parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        return page
    }

    private static func hover(_ page: LayoutTestPage, at point: CGPoint) {
        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()
    }

    private static func hover(_ page: LayoutTestPage, overTextOf id: String) throws {
        hover(page, at: try textCenter(of: id, in: page.frame))
    }

    private static func center(of element: ElementRef, in page: LayoutTestPage) throws -> CGPoint {
        let id: LayoutID = try #require(element.ref.layoutID)
        return center(page.tree.absoluteBounds(id))
    }

    private static func textCenter(of id: String, in frame: Frame) throws -> CGPoint {
        let doc: LayoutTree = try #require(frame.document)
        let element: ElementRef = try #require(
            treeToList(frame.nodes).compactMap({ $0.element }).first(where: { $0.attributes["id"] == id })
        )
        let text: LayoutID = try #require(
            treeToList(doc, doc.rootID).filter({ doc.isText($0) })
                .first(where: { doc.domRef($0).parent?.id == element.id })
        )
        return center(doc.absoluteBounds(text))
    }

    private static func center(_ rect: Rect) -> CGPoint {
        return CGPoint(x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2)
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
