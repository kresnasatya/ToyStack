import CoreGraphics
import Testing

@testable import Engine

/// A paint-only style change on one element must not throw away the paint
/// caches of every other block and line.
///
/// The paint epoch used to be global: any painted style change bumped it, so a
/// link's hover colour re-emitted all 113 blocks and all 58 lines on the front
/// page. The caches are now keyed by the style revision of the node (or, for a
/// line, of the owners of its boxes), so only the affected line re-emits.
@Suite(.serialized)
@MainActor
struct PaintInvalidationScopeTests {
    @Test func colourChangeReusesUnrelatedPaintCaches() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <ul>
                <li id="one"><a id="link" href="#">link text</a> tail one</li>
                <li id="two">second item text</li>
                </ul>
                <p id="other">an unrelated paragraph</p>
                """,
            rules: """
                body { display: block; }
                ul { display: block; }
                li { display: block; }
                p { display: block; }
                """
        )
        page.frame.paint()
        let link: ElementRef = try #require(page.firstElement(id: "link"))

        profiler.reset()
        InlineStyle.set(link, property: "color", value: "red")
        page.frame.setNeedsStyle(link.ref)
        page.frame.render()
        page.frame.paint()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(
            (metrics["paint.cache.hit.blocks"]?.count ?? 0) > 0,
            "a colour change must not re-emit every block"
        )
        #expect(
            (metrics["paint.cache.store.blocks"]?.count ?? 0) == 0,
            "no block's own style changed, so none may be re-emitted"
        )
        #expect(
            (metrics["paint.cache.hit.lines"]?.count ?? 0) > 0,
            "unaffected lines must keep their cached text"
        )
        #expect(
            (metrics["paint.cache.store.lines"]?.count ?? 0) <= 1,
            "only the line with the link boxes may re-emit"
        )
        let redLinkText: Bool = page.frame.displayList.contains(where: { op in
            guard case .text(let text, _, let color, _) = op else { return false }
            return text.contains("link text") && color == BrowserColor(cssName: "red")
        })
        #expect(redLinkText, "the repainted line must carry the new colour")
    }

    /// An incremental paint must equal a paint with every cache invalidated.
    ///
    /// Crossing the font breakpoint changes both the line generation and the
    /// style revisions of the box owners. Mixing those two inputs into one
    /// number with XOR let the changes cancel out (`8 ^ 1 == 11 ^ 2`) and the
    /// line cache served the old font after the flip.
    @Test func incrementalPaintMatchesFullyInvalidatedPaintAfterFontFlip() throws {
        let aboveWords: String = Array(repeating: "word", count: 80).joined(separator: " ")
        let belowWords: String = Array(repeating: "alpha beta gamma delta", count: 30)
            .joined(separator: " ")
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <p id="above">\(aboveWords)</p>
                <p id="below">\(belowWords)</p>
                """,
            rules: """
                html { font-size: 24px; }
                body { display: block; margin: 8px; }
                p { display: block; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                """
        )
        for width in [CGFloat(1200), 1024, 816, 700] {
            page.tab.resize(width: width, height: page.frame.frameHeight)
            page.frame.render()
            page.frame.paint()
        }
        let incremental: String = displaySignature(page.frame.displayList)

        // Bumping the epoch is the "invalidate everything" switch the paint
        // caches used to follow on every style change.
        page.frame.state.display.paint.epoch += 1
        page.frame.setNeedsPaint()
        page.frame.paint()
        let fullyInvalidated: String = displaySignature(page.frame.displayList)

        #expect(
            incremental == fullyInvalidated,
            "incremental paint differs from a fully invalidated paint after the font flip"
        )
    }
}
