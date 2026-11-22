import CoreGraphics
import Testing

@testable import Engine

/// CSS Backgrounds 3 §3.2: what each border-style looks like on screen.
@Suite(.serialized)
@MainActor
struct BorderStylePaintTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; height: 40px; }
        """

    private func painted(_ style: String) throws -> PaintedBorder {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { \(style) }"
        )
        page.frame.setNeedsPaint()
        page.frame.paint()
        let layout: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        return PaintedBorder(
            box: page.tree.selfRect(layout),
            pixels: PagePixels(page.frame.displayList, width: 700, height: 100),
            dashes: page.frame.displayList.compactMap { op in
                guard case .borderSide(let side) = op else { return nil }
                return side.dash
            }
        )
    }

    private func runs(_ pixels: PagePixels, y: CGFloat, from left: CGFloat, to right: CGFloat) -> [PixelRun] {
        var runs: [PixelRun] = []
        var x: CGFloat = left + 0.5
        while x < right {
            let painted: Bool = !pixels.isClear(x: x, y: y)
            if let last: PixelRun = runs.last, last.painted == painted {
                runs[runs.count - 1].length += 1
            } else {
                runs.append(PixelRun(painted: painted, length: 1))
            }
            x += 1
        }
        return runs
    }

    @Test func dashedBorderStartsAndEndsEachSideWithADash() throws {
        let border: PaintedBorder = try painted("border: 2px dashed red;")
        let box: Rect = border.box
        let top: [PixelRun] = runs(border.pixels, y: box.top + 1, from: box.left, to: box.right)
        let dashLengths: [Int] = top.filter({ $0.painted }).map({ $0.length })

        #expect(top.first?.painted == true)
        #expect(top.last?.painted == true)
        #expect(top.contains(where: { !$0.painted }))
        #expect(Set(dashLengths.dropFirst().dropLast()).count <= 2)
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.left + 0.5, y: box.top + 0.5))
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.right - 0.5, y: box.bottom - 0.5))
        #expect(border.dashes.count == 4)
    }

    @Test func dottedBorderIsARowOfRoundDots() throws {
        let border: PaintedBorder = try painted("border: 6px dotted red;")
        let box: Rect = border.box
        let row: [PixelRun] = runs(border.pixels, y: box.top + 3, from: box.left, to: box.right)

        #expect(border.dashes.allSatisfy({ $0.on == 0 && $0.lineWidth == 6 }))
        #expect(row.filter({ $0.painted }).count > 10)
        #expect(border.pixels.isClear(x: box.left + 0.5, y: box.top + 0.5))
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.left + 3, y: box.top + 3))
    }

    @Test func doubleBorderIsTwoLinesWithAGapBetween() throws {
        let border: PaintedBorder = try painted("border: 6px double red;")
        let box: Rect = border.box
        let red: BrowserColor = BrowserColor(cssName: "red")

        #expect(border.pixels.matches(red, x: box.middleX, y: box.top + 1))
        #expect(border.pixels.isClear(x: box.middleX, y: box.top + 3))
        #expect(border.pixels.matches(red, x: box.middleX, y: box.top + 5))
        #expect(border.pixels.matches(red, x: box.left + 1, y: box.middleY))
        #expect(border.pixels.isClear(x: box.left + 3, y: box.middleY))
        #expect(border.pixels.matches(red, x: box.left + 5, y: box.middleY))
    }

    @Test func insetBorderShadesTopAndLeftDarker() throws {
        let border: PaintedBorder = try painted("border: 4px inset red;")
        let box: Rect = border.box
        let top: BrowserColor = border.pixels.color(x: box.middleX, y: box.top + 2)
        let left: BrowserColor = border.pixels.color(x: box.left + 2, y: box.middleY)

        #expect(top.red < 0.8 && top.alpha > 0.9)
        #expect(left == top)
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.middleX, y: box.bottom - 2))
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.right - 2, y: box.middleY))
    }

    @Test func outsetBorderShadesBottomAndRightDarker() throws {
        let border: PaintedBorder = try painted("border: 4px outset red;")
        let box: Rect = border.box
        let bottom: BrowserColor = border.pixels.color(x: box.middleX, y: box.bottom - 2)

        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.middleX, y: box.top + 2))
        #expect(border.pixels.matches(BrowserColor(cssName: "red"), x: box.left + 2, y: box.middleY))
        #expect(bottom.red < 0.8 && bottom.alpha > 0.9)
        #expect(border.pixels.color(x: box.right - 2, y: box.middleY) == bottom)
    }

    @Test func grooveBorderIsCarvedInAndRidgeStandsOut() throws {
        let groove: PaintedBorder = try painted("border: 6px groove red;")
        let ridge: PaintedBorder = try painted("border: 6px ridge red;")

        #expect(groove.red(top: 1) < groove.red(top: 5))
        #expect(groove.red(bottom: 1) > groove.red(bottom: 5))
        #expect(ridge.red(top: 1) > ridge.red(top: 5))
        #expect(ridge.red(bottom: 1) < ridge.red(bottom: 5))
    }

    @Test func darkShadeOfBlackIsGraySoTheEffectStaysVisible() throws {
        let border: PaintedBorder = try painted("border: 4px inset black;")
        let box: Rect = border.box
        let top: BrowserColor = border.pixels.color(x: box.middleX, y: box.top + 2)

        #expect(top.red > 0.2 && top.alpha > 0.9)
        #expect(border.pixels.matches(BrowserColor(cssName: "black"), x: box.middleX, y: box.bottom - 2))
    }

    @Test func dashedRoundedBorderFollowsTheCurve() throws {
        let border: PaintedBorder = try painted("border: 4px dashed red; border-radius: 20px;")
        let box: Rect = border.box
        let top: [PixelRun] = runs(border.pixels, y: box.top + 2, from: box.left + 20, to: box.right - 20)

        #expect(border.dashes.count == 4)
        #expect(border.pixels.isClear(x: box.left + 1, y: box.top + 1))
        #expect(top.contains(where: { !$0.painted }))
    }
}

// MARK: - PaintedBorder

private struct PaintedBorder {
    let box: Rect
    let pixels: PagePixels
    let dashes: [BorderDash]

    func red(top offset: CGFloat) -> Double {
        return pixels.color(x: box.middleX, y: box.top + offset).red
    }

    func red(bottom offset: CGFloat) -> Double {
        return pixels.color(x: box.middleX, y: box.bottom - offset).red
    }
}

// MARK: - PixelRun

private struct PixelRun {
    let painted: Bool
    var length: Int
}

// MARK: - Rect middles

private extension Rect {
    var middleX: CGFloat { (left + right) / 2 }
    var middleY: CGFloat { (top + bottom) / 2 }
}
