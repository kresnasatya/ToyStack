import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleInheritanceTests {
    @Test func mediaFontSizeFlipUpdatesInheritedDescendant() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        let dom: DOMTree = HTMLParser(body: #"<div class="narrow"><p id="child">hello</p></div>"#).parse()
        frame.replaceDOM(dom)
        frame.setStyleRules(CSSParser("""
            html { width: 600px; }
            div { font-size: 10px; }
            p { font-size: 150%; }
            @media (min-width: 600px) { div.narrow { font-size: 20px; } }
            """).parse().rules)
        frame.setNeedsRender()
        frame.render()

        let child: ElementRef = try #require(
            treeToList(dom.ref(dom.root)).compactMap(\.element)
                .first(where: { $0.attributes["id"] == "child" })
        )
        #expect(child.style.computed.text.font.size == 30)

        frame.setViewport(width: 400, height: frame.frameHeight)
        frame.setNeedsViewportResize()
        frame.render()

        #expect(child.style.computed.text.font.size == 15)
    }

    /// A percentage chain must resolve to the same number every time it is
    /// applied. Before the single-resolver change, the flip path and the
    /// re-inherit path used different arithmetic orders, so a hover after a
    /// breakpoint resize changed `28.8` into `28.799999999999997` and
    /// scheduled a full layout.
    @Test func hoverAfterFontFlipKeepsPercentageSizesStable() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div class="main"><section id="introduction"><ol><li><a id="link" href="/x">Link text</a><br>description</li></ol></section></div>"#,
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                section, ol, li { display: block; }
                .main ol { font-size: 120%; }
                .main li { font-size: 80%; }
                .main li a { font-size: 125%; }
                a:hover { color: #08f; }
                """
        )
        let link: ElementRef = try #require(page.firstElement(id: "link"))

        page.tab.resize(width: 700, height: page.frame.frameHeight)
        page.frame.render()
        page.tab.resize(width: 900, height: page.frame.frameHeight)
        page.frame.render()

        let doc: LayoutTree = try #require(page.frame.document)
        var point: CGPoint? = nil
        for line in treeToList(doc, doc.rootID) where doc.isLine(line) {
            guard let boxes: [InlineBox] = doc.currentInlineBoxes(line) else { continue }
            if let box: InlineBox = boxes.first(where: { doc.inlineText($0) == "Link text" }) {
                point = CGPoint(x: box.geometry.x + 2, y: doc.y(line) + box.geometry.y + 2)
                break
            }
        }
        let hoverPoint: CGPoint = try #require(point)

        func sizes() -> [CGFloat] {
            var chain: [CGFloat] = []
            var current: DOMRef? = link.ref
            while let ref = current, ref.element != nil {
                chain.append(ref.style.computed.text.font.size)
                current = ref.parent
            }
            return chain
        }
        let before: [CGFloat] = sizes()
        #expect(before.first == 28.8)

        for pass in 1...2 {
            page.tab.hover(x: hoverPoint.x, y: hoverPoint.y)
            profiler.reset()
            page.frame.render()
            #expect(
                sizes() == before,
                "hover pass \(pass) changed a percentage font size"
            )
            #expect(
                (profiler.snapshot()["layout.visited"]?.count ?? 0) == 0,
                "hover pass \(pass) ran a layout"
            )
        }
    }

    /// Growing back across the breakpoint must leave every painted line box
    /// with its owner's font. The layout tree is a value snapshot, so each
    /// check reads the tree the last render installed.
    @Test func growingBackAcrossTheBreakpointRefreshesLineBoxFonts() throws {
        let paragraph: String = String(
            repeating: "alpha beta gamma delta epsilon zeta eta theta ",
            count: 20
        )
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">\(paragraph)</p>",
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                p { display: block; }
                """
        )

        func assertBoxesMatchOwners(_ label: String) throws {
            let doc: LayoutTree = try #require(page.frame.document)
            var stale: [String] = []
            for line in treeToList(doc, doc.rootID) where doc.isLine(line) {
                guard let boxes: [InlineBox] = doc.currentInlineBoxes(line) else { continue }
                for box in boxes {
                    let owner: DOMRef = DOMRef(id: box.dom, dom: doc.dom).inheritedStyleOwner
                    let expected: CGFloat = owner.style.computed.text.font.size
                    if abs(box.text.font.size - expected) > 0.01 {
                        stale.append("\(Int(box.text.font.size)) vs \(Int(expected))")
                    }
                }
            }
            #expect(stale.isEmpty, "\(label): stale boxes \(stale)")
        }

        page.tab.resize(width: 900, height: page.frame.frameHeight)
        page.frame.render()
        page.frame.paint()
        try assertBoxesMatchOwners("after 900")

        page.tab.resize(width: 400, height: page.frame.frameHeight)
        page.frame.render()
        page.frame.paint()
        try assertBoxesMatchOwners("after narrow width")

        page.tab.resize(width: 1192, height: page.frame.frameHeight)
        page.frame.render()
        page.frame.paint()
        try assertBoxesMatchOwners("first layout after growing back")
    }
}
