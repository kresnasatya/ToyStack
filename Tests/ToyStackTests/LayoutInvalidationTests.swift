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

        let bodyBefore: LayoutID = try #require(fixture.body.ref.layoutID)
        let childrenBefore: [LayoutID] = fixture.tree.childrenIDs(of: bodyBefore)

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let bodyAfter: LayoutID = try #require(fixture.body.ref.layoutID)
        #expect(bodyAfter == bodyBefore)
        #expect(fixture.tree.childrenIDs(of: bodyAfter) == childrenBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func mediaRuleChangeUpdatesWidth() throws {
        let fixture = makeFixture(mediaBody: "width: 200px;")
        let narrowBefore: LayoutID = try #require(fixture.narrow.ref.layoutID)
        #expect(fixture.tree.width(narrowBefore) == CGFloat(200))

        fixture.frame.setViewport(width: 400, height: fixture.frame.frameHeight)
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let narrowAfter: LayoutID = try #require(fixture.narrow.ref.layoutID)
        #expect(fixture.tree.width(narrowAfter) == CGFloat(100))
    }

    @Test func removingMarginBottomRebuildsHeight() throws {
        let fixture = makeFixture(mediaBody: "margin-bottom: 50px;")
        let bodyBefore: LayoutID = try #require(fixture.body.ref.layoutID)
        #expect(fixture.tree.height(bodyBefore) == CGFloat(50))
        let wideBefore: LayoutID = try #require(fixture.wide.ref.layoutID)
        let wideYBefore: CGFloat = fixture.tree.y(wideBefore)

        fixture.frame.setViewport(width: 400, height: fixture.frame.frameHeight)
        fixture.frame.setNeedsViewportResize()
        fixture.frame.render()

        let bodyAfter: LayoutID = try #require(fixture.body.ref.layoutID)
        #expect(fixture.tree.height(bodyAfter) == 0)
        let wideAfter: LayoutID = try #require(fixture.wide.ref.layoutID)
        #expect(fixture.tree.y(wideAfter) == wideYBefore - 50)
    }

    @Test func widthChangeOnOneBlockKeepsSiblings() throws {
        let fixture = makeFixture()
        let narrowBefore: LayoutID = try #require(fixture.narrow.ref.layoutID)
        let bodyBefore: LayoutID = try #require(fixture.body.ref.layoutID)
        let wideBefore: LayoutID = try #require(fixture.wide.ref.layoutID)

        InlineStyle.set(fixture.narrow, property: "width", value: "200px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let narrow: LayoutID = try #require(fixture.narrow.ref.layoutID)
        #expect(fixture.tree.width(narrow) == CGFloat(200))

        #expect(narrow == narrowBefore)
        #expect(fixture.body.ref.layoutID == bodyBefore)
        #expect(fixture.wide.ref.layoutID == wideBefore)
    }

    @Test func nonReusableStylePassKeepsLayoutObjects() throws {
        let fixture = makeFixture()
        fixture.frame.setStyleRules(CSSParser("""
            html { width: 600px; }
            body { display: block; }
            div { display: block; width: 120px; }
            """).parse().rules)
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        let bodyBefore: LayoutID = try #require(fixture.body.ref.layoutID)
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        #expect(fixture.body.ref.layoutID == bodyBefore)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func textEditRefreshesScrollTargets() throws {
        let page: LayoutTestPage = makeScrollTargetPage()
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let text: TextRef = try #require(paragraph.children.first?.text)

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
        let scroller: ElementRef = try #require(page.firstElement(tag: "div"))

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
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let beforeID: LayoutID = try #require(page.lineIDs(in: p).first)
        let before: CGFloat = page.tree.height(beforeID)

        page.frame.addAnimation(PixelAnimation(
            animatedProperty: .fontSize,
            oldValue: 14,
            newValue: 28,
            timing: FrameTiming(totalFrames: 60, easing: .linear)
        ), to: p.ref)

        page.frame.setNeedsRender()
        page.frame.render()

        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        profiler.reset()
        for _ in 0..<40 {
            page.frame.runAnimationFrame()
        }

        let afterID: LayoutID = try #require(page.lineIDs(in: p).first)
        let after: CGFloat = page.tree.height(afterID)
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
        ), to: fixture.narrow.ref)
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        fixture.frame.setJSRuntime(JSRuntime(frame: fixture.frame))
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
        ), to: fixture.narrow.ref)
        fixture.frame.setNeedsRender()
        fixture.frame.render()

        fixture.frame.setJSRuntime(JSRuntime(frame: fixture.frame))
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
    let body: ElementRef
    let narrow: ElementRef
    let wide: ElementRef

    var tree: LayoutTree {
        guard let tree: LayoutTree = frame.document else {
            preconditionFailure("fixture has no layout tree")
        }
        return tree
    }
}

@MainActor
private func makeFixture(mediaBody: String = "margin-bottom: 50px;") -> Fixture {
    let tab = BrowserTab(tabHeight: 600, tabWidth: 800)
    let frame = tab.rootFrame
    let dom: DOMTree = HTMLParser(
        body: #"<div class="narrow"></div><div class="wide"></div>"#
    ).parse()
    frame.replaceDOM(dom)
    frame.setStyleRules(CSSParser("""
        html { width: 600px; }
        body { display: block; }
        div { display: block; width: 100px; }
        @media (min-width: 600px) { div.narrow { \(mediaBody) } }
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    let body: ElementRef = treeToList(dom.ref(dom.root)).compactMap({ $0.element }).first(where: { $0.tag == "body" })!
    let narrow: ElementRef = treeToList(dom.ref(dom.root)).compactMap({ $0.element }).first(where: { $0.attributes["class"] == "narrow" })!
    let wide: ElementRef = treeToList(dom.ref(dom.root)).compactMap({ $0.element }).first(where: { $0.attributes["class"] == "wide" })!
    return Fixture(tab: tab, frame: frame, body: body, narrow: narrow, wide: wide)
}
