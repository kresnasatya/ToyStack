import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct CustomPropertyTests {
    private let html: String = #"<div id="outer"><div id="mid"><div id="x">text</div></div></div>"#

    private func page(_ rules: String, html: String? = nil) -> LayoutTestPage {
        return LayoutTestPage(
            html: html ?? self.html,
            rules: "body { display: block; } div { display: block; } " + rules
        )
    }

    private func style(_ page: LayoutTestPage, id: String = "x") throws -> ComputedStyle {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return element.style.computed
    }

    @Test func rootVariablesReachDescendants() throws {
        let style: ComputedStyle = try style(page("""
            :root { --gap: 12px; --brand: #ff0000; }
            #x { margin-left: var(--gap); color: var(--brand); }
            """))
        #expect(style.box.spacing.margin.left == 12)
        #expect(style.text.color == BrowserColor(red: 1, green: 0, blue: 0))
    }

    @Test func nearestDeclarationWins() throws {
        let page: LayoutTestPage = page("""
            #outer { --w: 50px; }
            #mid { width: var(--w); }
            #x { --w: 80px; width: var(--w); }
            """)
        #expect(try style(page, id: "mid").box.size.width == 50)
        #expect(try style(page).box.size.width == 80)
    }

    @Test func variableNamesAreCaseSensitive() throws {
        let style: ComputedStyle = try style(page("#x { --W: 1px; --w: 2px; width: var(--W); height: var(--w); }"))
        #expect(style.box.size.width == 1)
        #expect(style.box.size.height == 2)
    }

    @Test func fallbackFillsAMissingVariable() throws {
        let style: ComputedStyle = try style(page("""
            #x { width: var(--missing, 40px); height: var(--a, var(--b, 30px)); }
            """))
        #expect(style.box.size.width == 40)
        #expect(style.box.size.height == 30)
    }

    @Test func missingVariableBehavesAsUnset() throws {
        let style: ComputedStyle = try style(page("""
            #mid { color: #0000ff; }
            #x { color: #ff0000; background-color: #ff0000; width: 5px; }
            div#x { color: var(--nope); background-color: var(--nope); width: var(--nope); }
            """))
        #expect(style.text.color == BrowserColor(red: 0, green: 0, blue: 1))
        #expect(style.visual.background.color == nil)
        #expect(style.box.size.width == nil)
    }

    @Test func variablesInACycleAreAllInvalid() throws {
        let style: ComputedStyle = try style(page("""
            #x {
                --a: var(--b); --b: var(--a); --self: var(--self);
                --c: var(--a, 7px);
                width: var(--a, 11px); height: var(--c); margin-left: var(--self, 3px);
            }
            """))
        #expect(style.box.size.width == 11)
        #expect(style.box.size.height == 7)
        #expect(style.box.spacing.margin.left == 3)
    }

    @Test func variableCanHoldAnotherVariable() throws {
        let style: ComputedStyle = try style(page("""
            :root { --base: 6px; }
            #mid { --double: var(--base) var(--base); }
            #x { --base: 9px; margin: var(--double); }
            """))
        #expect(style.box.spacing.margin.top == 6)
        #expect(style.box.spacing.margin.right == 6)
    }

    @Test func shorthandIsSplitAfterSubstitution() throws {
        let style: ComputedStyle = try style(page("""
            :root { --m: 4px 8px; --line: #00ff00; --w: 2px; }
            #x { margin: var(--m); border: var(--w) solid var(--line); }
            """))
        #expect(style.box.spacing.margin == EdgeInsets(top: 4, right: 8, bottom: 4, left: 8))
        let left: BoxStyle.Decoration.Border.Side = style.box.decoration.border.sides.left
        #expect(left.width == 2)
        #expect(left.style == .solid)
        #expect(left.color == BrowserColor(red: 0, green: 1, blue: 0))
    }

    @Test func laterLonghandOverridesAShorthandWithAVariable() throws {
        let style: ComputedStyle = try style(page("""
            :root { --p: 6px; }
            #x { padding: var(--p); }
            div#x { padding-left: 1px; }
            """))
        #expect(style.box.spacing.padding == EdgeInsets(top: 6, right: 6, bottom: 6, left: 1))
    }

    @Test func inlineStyleCanDeclareAndUseVariables() throws {
        let style: ComputedStyle = try style(page(
            "",
            html: #"<div id="outer" style="--w: 33px"><div id="x" style="width: var(--w)">t</div></div>"#
        ))
        #expect(style.box.size.width == 33)
    }

    @Test func ancestorVariableChangeReachesDescendants() throws {
        let page: LayoutTestPage = page("""
            :root { --w: 10px; }
            @media (min-width: 600px) { :root { --w: 20px; } }
            #mid { font-size: 12px; }
            #x { width: var(--w); }
            """)
        #expect(try style(page).box.size.width == 20)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(try style(page).box.size.width == 10)
    }

    @Test func runawaySubstitutionIsInvalid() throws {
        var declarations: String = "--p0: xxxxxxxxxxxxxxxx;"
        for level in 1...40 {
            declarations += " --p\(level): var(--p\(level - 1)) var(--p\(level - 1));"
        }
        let style: ComputedStyle = try style(page("""
            :root { \(declarations) }
            #x { width: var(--p40, 5px); }
            """))
        #expect(style.box.size.width == 5)
    }
}
