import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutInvalidationTests {
    @Test func paintOnlyPropertiesDoNotAffectLayout() {
        #expect(StyleProperty.width.affectsLayout)
        #expect(StyleProperty.height.affectsLayout)
        #expect(StyleProperty.aspectRatio.affectsLayout)
        #expect(StyleProperty.fontSize.affectsLayout)
        #expect(StyleProperty.marginBottom.affectsLayout)

        #expect(!StyleProperty.opacity.affectsLayout)
        #expect(!StyleProperty.transform.affectsLayout)
        #expect(!StyleProperty.backgroundColor.affectsLayout)
        #expect(!StyleProperty.borderRadius.affectsLayout)
    }

    @Test func cleanSecondLayoutKeepsBlockChildren() throws {
        let fixture = makeFixture()

        let bodyBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        let childrenBefore: [LayoutID] = bodyBefore.children.map({ $0.id })

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let bodyAfter: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        #expect(bodyAfter.id == bodyBefore.id)
        #expect(bodyAfter.children.map({ $0.id }) == childrenBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func mediaRuleChangeUpdatesWidth() throws {
        let fixture = makeFixture(mediaBody: "width: 200px;")
        let narrowBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.narrow).layout)
        #expect(narrowBefore.width == CGFloat(200))

        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let narrowAfter: LayoutRef = try #require(fixture.frame.dom.ref(fixture.narrow).layout)
        #expect(narrowAfter.width == CGFloat(100))
    }

    @Test func removingMarginBottomRebuildsHeight() throws {
        let fixture = makeFixture(mediaBody: "margin-bottom: 50px;")
        let bodyBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        #expect(bodyBefore.height == CGFloat(50))
        let wideBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.wide).layout)
        let wideYBefore: CGFloat = wideBefore.y

        fixture.frame.frameWidth = 400
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let bodyAfter: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        #expect(bodyAfter.height == 0)
        let wideAfter: LayoutRef = try #require(fixture.frame.dom.ref(fixture.wide).layout)
        #expect(wideAfter.y == wideYBefore - 50)
    }

    @Test func widthChangeOnOneBlockKeepsSiblings() throws {
        let fixture = makeFixture()
        let narrowBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.narrow).layout)
        let bodyBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        let wideBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.wide).layout)

        InlineStyle.set(fixture.narrow, property: "width", value: "200px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let narrow: LayoutRef = try #require(fixture.frame.dom.ref(fixture.narrow).layout)
        #expect(narrow.width == CGFloat(200))

        #expect(narrow.id == narrowBefore.id)
        #expect(fixture.frame.dom.ref(fixture.body).layout?.id == bodyBefore.id)
        #expect(fixture.frame.dom.ref(fixture.wide).layout?.id == wideBefore.id)
    }

    @Test func nonReusableStylePassKeepsLayoutObjects() throws {
        let fixture = makeFixture()
        fixture.frame.rules = CSSParser("""
            html { width: 600px; }
            body { display: block; }
            div { display: block; width: 120px; }
            """).parse().rules
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        let bodyBefore: LayoutRef = try #require(fixture.frame.dom.ref(fixture.body).layout)
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        #expect(fixture.frame.dom.ref(fixture.body).layout?.id == bodyBefore.id)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func textEditRefreshesScrollTargets() throws {
        let page: LayoutTestPage = makeScrollTargetPage()
        let paragraph: Element = try #require(page.firstElement(tag: "p"))
        let text: TextNode = try #require(paragraph.children.first as? TextNode)

        text.append(" more")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        #expect((profiler.snapshot()["scrollTargets.reused"]?.count ?? 0) == 1)
        #expect(profiler.snapshot()["scrollTargets.rebuilt"] == nil)
    }

    @Test func structuralEditRebuildsScrollTargets() {
        let page: LayoutTestPage = makeScrollTargetPage()

        page.frame.markStructureChanged()
        page.frame.setNeedsLayout()
        profiler.reset()
        page.frame.render()

        #expect((profiler.snapshot()["scrollTargets.rebuilt"]?.count ?? 0) == 1)
        #expect(profiler.snapshot()["scrollTargets.reused"] == nil)
    }

    @Test func overflowStyleChangeRebuildsScrollTargets() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="scroller">one two</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; height: 20px; }
                """
        )
        let scroller: Element = try #require(page.firstElement(tag: "div"))

        InlineStyle.set(scroller, property: "overflow", value: "scroll")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        #expect((profiler.snapshot()["scrollTargets.rebuilt"]?.count ?? 0) == 1)
        #expect(profiler.snapshot()["scrollTargets.reused"] == nil)
    }

    @Test func animatingFontSizeOnTextParentRebuildsText() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">one two three four five</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
        let p: Element = try #require(page.firstElement(tag: "p"))
        let before: CGFloat = try #require(page.lines(in: p).first).height

        page.frame.addAnimation(PixelAnimation(
            animatedProperty: .fontSize,
            oldValue: 14,
            newValue: 28,
            timing: FrameTiming(totalFrames: 60, easing: .linear)
        ), to: p)

        page.frame.setNeedsRender()
        page.frame.render()

        page.frame.js = JSRuntime(frame: page.frame)
        profiler.reset()
        for _ in 0..<40 {
            page.frame.runAnimationFrame()
        }

        let after: CGFloat = try #require(page.lines(in: p).first).height
        #expect(after > before)
        #expect((profiler.snapshot()["layout.rebuilt"]?.count ?? 0) > 0)
        #expect((profiler.snapshot()["layout.animation.fallback"]?.count ?? 0) == 0)
    }

    @Test func animatingOpacityDoesNotRebuildLayout() {
        let fixture = makeFixture()
        fixture.frame.addAnimation(NumericAnimation(
            animatedProperty: .opacity,
            oldValue: 1,
            newValue: 0.5,
            timing: FrameTiming(totalFrames: 60, easing: .linear)
        ), to: fixture.narrow)
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        fixture.frame.js = JSRuntime(frame: fixture.frame)
        profiler.reset()
        fixture.frame.runAnimationFrame()

        #expect(profiler.snapshot()["layout.rebuilt"] == nil)
        #expect(fixture.narrow.style.computed.visual.effects.opacity < 1)
    }

    @Test func animatingTransformDoesNotRebuiltLayout() {
        let fixture = makeFixture()
        fixture.frame.addAnimation(TransformAnimation(
            animatedProperty: .transform,
            oldPoint: CGPoint.zero,
            newPoint: CGPoint(x: 20, y: 0),
            timing: FrameTiming(totalFrames: 60, easing: .linear)
        ), to: fixture.narrow)
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        fixture.frame.js = JSRuntime(frame: fixture.frame)
        profiler.reset()
        fixture.frame.runAnimationFrame()

        #expect(profiler.snapshot()["layout.rebuilt"] == nil)
        #expect(fixture.narrow.style.computed.visual.effects.translation != nil)
    }
}

@MainActor
private func makeScrollTargetPage() -> LayoutTestPage {
    return LayoutTestPage(
        html: #"<p id="p">one two</p>"#,
        rules: """
            html { width: 600px; }
            body { display: block; }
            p { display: block; }
            """
    )
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
    frame.setNeedsRender()
    frame.render()
    return Fixture(tab: tab, frame: frame, body: body, narrow: narrow)
}
