import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutInvalidationTests {
    @Test func denyListClassifiesLayoutInputs() {
        #expect(Frame.affectsLayout("width"))
        #expect(Frame.affectsLayout("height"))
        #expect(Frame.affectsLayout("aspect-ratio"))
        #expect(Frame.affectsLayout("font-size"))
        #expect(Frame.affectsLayout("margin-bottom"))
        #expect(Frame.affectsLayout("future-property"))

        #expect(!Frame.affectsLayout("opacity"))
        #expect(!Frame.affectsLayout("transform"))
        #expect(!Frame.affectsLayout("background-color"))
        #expect(!Frame.affectsLayout("border-radius"))
    }

    @Test func cleanSecondLayoutKeepsBlockChildren() throws {
        let fixture = makeFixture()

        let bodyBefore = try #require(fixture.body.layoutObject as? BlockLayout)
        let childrenBefore: [ObjectIdentifier] = bodyBefore.children.map({ ObjectIdentifier($0 as AnyObject) })

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let bodyAfter = try #require(fixture.body.layoutObject as? BlockLayout)
        #expect(bodyAfter === bodyBefore)
        #expect(bodyAfter.children.map{ ObjectIdentifier($0 as AnyObject) } == childrenBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func mediaRuleChangeUpdatesWidth() throws {
        let fixture = makeFixture(mediaBody: "width: 200px;")
        let narrowBefore = try #require(fixture.narrow.layoutObject as? BlockLayout)
        #expect(narrowBefore.width == CGFloat(200))

        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let narrowAfter = try #require(fixture.narrow.layoutObject as? BlockLayout)
        #expect(narrowAfter.width == CGFloat(100))
        #expect(fixture.narrow.layoutDirty == false)
        #expect(fixture.body.layoutDirty == false)
        #expect(fixture.html.layoutDirty == false)
    }

    @Test func removingMarginBottomRebuildsHeight() throws {
        let fixture = makeFixture(mediaBody: "margin-bottom: 50px;")
        let bodyBefore = try #require(fixture.body.layoutObject as? BlockLayout)
        #expect(bodyBefore.height == CGFloat(50))
        let wideBefore = try #require(fixture.wide.layoutObject)
        let wideYBefore: CGFloat = wideBefore.y

        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let bodyAfter = try #require(fixture.body.layoutObject as? BlockLayout)
        #expect(bodyAfter.height == 0)
        let wideAfter = try #require(fixture.wide.layoutObject)
        #expect(wideAfter.y == wideYBefore - 50)
    }

    @Test func widthChangeOnOneBlockKeepsSiblings() throws {
        let fixture = makeFixture()
        let wideBefore = try #require(fixture.wide.layoutObject)

        fixture.narrow.style["width"] = "200px"
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let narrow = try #require(fixture.narrow.layoutObject as? BlockLayout)
        #expect(narrow.width == CGFloat(200))

        #expect(fixture.wide.layoutObject === wideBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func nonReusableStylePassClearsDirtyFlags() throws {
        let fixture = makeFixture()
        fixture.frame.rules = CSSParser("""
            html { width: 600px; }
            body { display: block; }
            div { display: block; width: 120px; }
            """).parse().rules
        fixture.frame.needsStyle = true
        fixture.frame.render()

        #expect(fixture.html.layoutDirty == false)
        #expect(fixture.body.layoutDirty == false)
        #expect(fixture.narrow.layoutDirty == false)
        #expect(fixture.wide.layoutDirty == false)

        let bodyBefore = try #require(fixture.body.layoutObject as? BlockLayout)
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        #expect(fixture.body.layoutObject === bodyBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func animatingFontSizeRebuildsTheDirtySubtree() {
        let fixture = makeFixture()
        fixture.narrow.animations["font-size"] = PixelAnimation(animatedProperty: "font-size", oldValue: 20, newValue: 10, timing: FrameTiming(totalFrames: 60, easing: .linear))
        fixture.frame.needsStyle = true
        fixture.frame.render()

        fixture.frame.js = JSRuntime(frame: fixture.frame)
        profiler.reset()
        fixture.frame.runAnimationFrame()

        #expect((profiler.snapshot()["layout.rebuilt"]?.count ?? 0) > 0)
        #expect(fixture.narrow.layoutDirty == false)
        #expect(fixture.narrow.style["font-size"] != nil)
    }

    @Test func animatingOpacityDoesNotMarkLayoutDirty() {
        let fixture = makeFixture()
        fixture.narrow.animations["opacity"] = NumericAnimation(animatedProperty: "opacity", oldValue: 1, newValue: 0.5, timing: FrameTiming(totalFrames: 60, easing: .linear))
        fixture.frame.needsStyle = true
        fixture.frame.render()

        fixture.frame.js = JSRuntime(frame: fixture.frame)
        profiler.reset()
        fixture.frame.runAnimationFrame()

        #expect(profiler.snapshot()["layout.rebuilt"] == nil)
        #expect(fixture.narrow.layoutDirty == false)
        #expect(fixture.narrow.style["opacity"] != nil)
    }
}

@MainActor
private struct Fixture {
    let tab: BrowserTab
    let frame: Frame
    let body: Element
    let narrow: Element

    var html: Element { frame.nodes as! Element }
    var wide: Element { body.children[1] as! Element }
}

@MainActor
private func makeFixture(mediaBody: String = "margin-bottom: 50px;") -> Fixture {
    let tab = BrowserTab(tabHeight: 600, tabWidth: 800)
    let frame = tab.rootFrame!
    let html = Element(tag: "html", attributes: [:], parent: nil)
    let body = Element(tag: "body", attributes: [:], parent: html)
    let narrow = Element(tag: "div", attributes: ["class": "narrow"], parent: body)
    let wide = Element(tag: "div", attributes: ["class" : "wide"], parent: body)
    html.children = [body]
    body.children = [narrow, wide]
    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 600px; }
        body { display: block; }
        div { display: block; width: 100px; }
        @media (min-width: 600px) { div.narrow { \(mediaBody) } }
        """).parse().rules
    frame.needsStyle = true
    frame.render()
    return Fixture(tab: tab, frame: frame, body: body, narrow: narrow)
}
