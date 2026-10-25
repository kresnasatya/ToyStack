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

    @Test func cleanSecondLayoutReuses() {
        let fixture = makeFixture()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let metrics = profiler.snapshot()
        #expect((metrics["layout.rebuilt"]?.count ?? 0) == 0)
        #expect((metrics["layout.reusedChildren"]?.count ?? 0) == 1)
    }

    @Test func removingAspectRatioMarksLayoutDirty() {
        let fixture = makeFixture(mediaBody: "aspect-ratio: 2;")
        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let metrics = profiler.snapshot()
        #expect((metrics["layout.reusedChildren"]?.count ?? 0) >= 1)
        #expect((metrics["layout.rebuildReason.dirtyFlag"]?.count ?? 0) >= 3)
        #expect(fixture.narrow.layoutDirty == false)
        #expect(fixture.body.layoutDirty == false)
        #expect(fixture.html.layoutDirty == false)
    }

    @Test func removingMarginBottomRebuildsHeight() throws {
        let fixture = makeFixture(mediaBody: "margin-bottom: 50px;")
        let bodyBefore = try #require(fixture.body.layoutObject as? BlockLayout)
        #expect(bodyBefore.height == CGFloat(50))

        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let bodyAfter = try #require(fixture.body.layoutObject as? BlockLayout)
        #expect(bodyAfter.height == 0)
        let metrics = profiler.snapshot()
        #expect((metrics["layout.reusedChildren"]?.count ?? 0) >= 1)
        #expect((metrics["layout.rebuildReason.dirtyFlag"]?.count ?? 0) >= 3)
    }

    @Test func dirtyLeafRebuildsOnlyItsPath() throws {
        let fixture = makeFixture()
        fixture.narrow.style["width"] = "200px"
        fixture.narrow.layoutDirty = true
        fixture.body.layoutDirty = true
        fixture.html.layoutDirty = true
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let narrow = try #require(fixture.narrow.layoutObject as? BlockLayout)
        #expect(narrow.width == CGFloat(200))
        let metrics = profiler.snapshot()
        #expect((metrics["layout.reusedChildren"]?.count ?? 0) == 1)
        #expect((metrics["layout.rebuildReason.dirtyFlag"]?.count ?? 0) >= 3)

        fixture.narrow.layoutDirty = false
        fixture.body.layoutDirty = false
        fixture.html.layoutDirty = false
    }

    @Test func nonReusableStylePassClearsDirtyFlags() {
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

        fixture.frame.setNeedsLayout()
        fixture.frame.render()
        #expect((profiler.snapshot()["layout.rebuilt"]?.count ?? 0) == 0)
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
