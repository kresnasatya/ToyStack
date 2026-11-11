import CoreGraphics
import Testing

@testable import Engine

/// A width reflow places lines with `collectsBoxes == true`: each line keeps
/// its text as `LineData.content.boxes` values and has no text children. A
/// later pass that only moves those lines used to rebuild the boxes from the
/// (empty) child list, erasing the text while keeping the line's height. The
/// visible result was a list bullet with no text, in a block that still
/// occupied its full height.
@Suite(.serialized)
@MainActor
struct LineBoxWipeTests {
    @Test func verticalLineMoveKeepsInlineBoxes() throws {
        // The first paragraph must change height with the width; the second
        // must change its line plan once (to enter the value path) and then
        // only move.
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
        let below: ElementRef = try #require(page.firstElement(id: "below"))
        let block: LayoutID = try #require(page.firstBlockID(in: below))

        var sawValueLines: Bool = false
        var sawInvisible: Bool = false
        for width in [CGFloat(1000), 950, 900, 850, 800, 780, 700] {
            page.tab.resize(width: width, height: page.frame.frameHeight)
            page.frame.render()

            let tree: LayoutTree = page.tree
            let lines: [LayoutID] = treeToList(tree, block).filter({ tree.isLine($0) })
            #expect(!lines.isEmpty, "the target paragraph must keep its lines")
            for line in lines {
                let children: [LayoutID] = tree.childrenIDs(of: line)
                let valueLine: Bool = children.isEmpty
                    && !tree[line: line].content.boxes.isEmpty
                if valueLine { sawValueLines = true }
                guard (tree.heightIfUsed(at: line) ?? 0) > 0 else { continue }
                let paintable: Bool = tree.currentInlineBoxes(line) != nil
                    || !children.isEmpty
                if !paintable { sawInvisible = true }
                #expect(
                    paintable,
                    "width \(Int(width)): line \(line.raw) keeps its height but has neither inline boxes nor text children"
                )
            }
        }
        #expect(sawValueLines, "the reflow must exercise the value-line path")
        #expect(!sawInvisible, "no line may lose its text while keeping its height")
    }
}
