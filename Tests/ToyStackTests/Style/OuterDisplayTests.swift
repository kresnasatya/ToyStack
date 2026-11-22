import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct OuterDisplayTests {
    private func display(_ value: String) throws -> LayoutStyle.Display {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div><span>before</span><div id="x">box</div><span>after</span></div>"#,
            rules: "body { display: block; } div { display: block; } #x { display: \(value); }"
        )
        return try #require(page.firstElement(id: "x")).style.computed.layout.display
    }

    // CSS Display 3 §2.2 and §2.3: flex, grid, flow-root, table and list-item boxes are
    // block-level on the outside. ToyStack lays their children out as normal blocks, but
    // the box itself must still start on its own line, not flow inline with its neighbours.
    @Test func blockLevelDisplaysAreBlocks() throws {
        for value in ["flex", "grid", "flow-root", "list-item", "table"] {
            #expect(try display(value) == .block, "display: \(value)")
        }
    }

    @Test func inlineLevelDisplaysStayOffTheBlockPath() throws {
        for value in ["inline-flex", "inline-block", "inline-grid"] {
            #expect(try display(value) != .block, "display: \(value)")
        }
    }
}
