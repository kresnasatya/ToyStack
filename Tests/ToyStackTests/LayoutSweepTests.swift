import CoreGraphics
import Testing

@testable import Engine

/// After a layout pass, the live layout nodes are exactly the ones reachable
/// from the root. The sweep finds the rest, and it should look only at what
/// the pass detached, not at the whole tree.
@Suite(.serialized)
@MainActor
struct LayoutSweepTests {
    private static let rules: String = """
        body { display: block; font-size: 20px; }
        p { display: block; }
        div { display: block; }
        """

    @Test func sweepLooksOnlyAtWhatThePassDetached() throws {
        let short: String = (0..<40).map({ "<p>short \($0)</p>" }).joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <p id="long">alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron</p>
                \(short)
                """,
            rules: Self.rules
        )
        let live: Int = page.tree.liveIDs.count

        // The long paragraph gains lines; nothing else re-breaks.
        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()
        // Back to a width where it loses lines again, so lines are detached.
        page.frame.setViewport(width: 800, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let examined: Int = profiler.snapshot()["layout.sweep.examined"]?.count ?? 0
        #expect(examined > 0, "lines were detached but the sweep did not run")
        #expect(examined < live / 4, "the sweep looked at \(examined) of \(live) nodes")
        expectOnlyReachableNodesAreLive(page.tree)
        expectIncrementalMatchesFull(page)
    }

    /// Re-breaks, moved lines, and DOM edits that detach, re-attach, and
    /// replace subtrees.
    @Test func noUnreachableNodeSurvivesAPass() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box"><p id="one">one two three four five six seven eight</p><p id="two">two</p></div>
                <div id="donor"><p>alpha beta gamma delta epsilon zeta eta theta</p><p>moved</p></div>
                <p id="tail">tail words that wrap when the viewport becomes narrow</p>
                """,
            rules: Self.rules
        )
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        let steps: [() -> Void] = [
            { page.frame.setViewport(width: 260, height: page.frame.frameHeight) },
            { page.frame.setViewport(width: 700, height: page.frame.frameHeight) },
            {
                page.frame.js.run(script: "move", code: """
                    var donor = document.getElementById('donor');
                    document.getElementById('box').replaceChildren(donor.children[1], donor.children[0]);
                """)
            },
            { page.frame.setViewport(width: 300, height: page.frame.frameHeight) },
            {
                page.frame.js.run(script: "edit", code: """
                    var made = document.createElement('p');
                    made.textContent = 'made with several words that wrap';
                    document.getElementById('donor').appendChild(made);
                    document.getElementById('tail').textContent = 'short';
                """)
            },
            { page.frame.setViewport(width: 220, height: page.frame.frameHeight) },
            {
                page.frame.js.run(script: "clear", code: "document.getElementById('box').replaceChildren()")
            },
            { page.frame.setViewport(width: 640, height: page.frame.frameHeight) },
        ]
        for step in steps {
            step()
            page.frame.setNeedsViewportResize()
            page.frame.render()
            expectOnlyReachableNodesAreLive(page.tree)
        }
        expectIncrementalMatchesFull(page)
    }
}

@MainActor
private func expectOnlyReachableNodesAreLive(
    _ tree: LayoutTree,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let reachable: Set<LayoutID> = Set(treeToList(tree, tree.rootID))
    let live: Set<LayoutID> = Set(tree.liveIDs)
    #expect(
        live == reachable,
        "live but unreachable: \(live.subtracting(reachable).count), reachable but removed: \(reachable.subtracting(live).count)",
        sourceLocation: sourceLocation
    )
}
