import Testing

@testable import Engine

@Suite
@MainActor
struct FocusNavigationTests {
    @Test func tabOrderUsesExplicitTabIndex() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"""
                <button id="second" tabindex="2">second</button>
                <button id="first" tabindex="1">first</button>
                """#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                button { display: inline; }
                """
        )

        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "first")
        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "second")
    }
}
