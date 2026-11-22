import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ButtonPaintTests {
    private func page(rules: String = "", forcedColors: Bool = false) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: #"<p><button id="go">Go</button></p>"#, rules: "")
        page.tab.forcedColors = forcedColors
        page.frame.setStyleRules(defaultStyleSheet + CSSParser("html { width: 600px; } " + rules).parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        page.frame.setNeedsPaint()
        page.frame.paint()
        return page
    }

    private func buttonBox(_ page: LayoutTestPage) throws -> Rect {
        let button: ElementRef = try #require(page.firstElement(id: "go"))
        return page.tree.selfRect(try #require(page.firstEmbedID(in: button)))
    }

    private func pixels(_ page: LayoutTestPage) -> PagePixels {
        return PagePixels(page.frame.displayList, width: 700, height: 200)
    }

    @Test func defaultButtonFillsARoundedFaceInsideAGrayRing() throws {
        let page: LayoutTestPage = page()
        let box: Rect = try buttonBox(page)
        let middleY: CGFloat = (box.top + box.bottom) / 2

        let faces: [(rect: Rect, radii: CornerRadii, color: BrowserColor)] =
            page.frame.displayList.compactMap { op in
                guard case .rrect(let rect, let radii, let color) = op else { return nil }
                return (rect, radii, color)
            }
        #expect(faces.count == 1)
        #expect(faces.first?.rect == box)
        #expect(faces.first?.radii == .uniform(.px(2)))
        #expect(faces.first?.color == BrowserColor(cssName: "#efefef"))
        #expect(pixels(page).matches(BrowserColor(cssName: "#767676"), x: box.left + 0.5, y: middleY))
        #expect(!page.frame.displayList.contains(where: { $0.name == "outline" }))
    }

    @Test func buttonWithoutABorderPaintsNoEdge() throws {
        let page: LayoutTestPage = page(rules: "button { border: none; }")
        let box: Rect = try buttonBox(page)
        let middleY: CGFloat = (box.top + box.bottom) / 2

        #expect(!pixels(page).matches(BrowserColor(cssName: "black"), x: box.left + 0.5, y: middleY))
        #expect(!page.frame.displayList.contains(where: { $0.name == "outline" }))
    }

    @Test func transparentButtonShowsWhatIsBehindIt() throws {
        let page: LayoutTestPage = page(rules: "button { background-color: transparent; }")
        let box: Rect = try buttonBox(page)

        #expect(pixels(page).isClear(x: box.right - 4, y: (box.top + box.bottom) / 2))
    }

    @Test func forcedColorsButtonKeepsAVisibleRing() throws {
        let page: LayoutTestPage = page(forcedColors: true)
        let box: Rect = try buttonBox(page)
        let middleY: CGFloat = (box.top + box.bottom) / 2
        let pixels: PagePixels = pixels(page)

        #expect(pixels.matches(BrowserColor(cssName: ForcedColor.buttonBorder), x: box.left + 0.5, y: middleY))
        #expect(pixels.matches(BrowserColor(cssName: ForcedColor.buttonFace), x: box.right - 4, y: middleY))
    }
}
