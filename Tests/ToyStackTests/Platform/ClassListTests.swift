import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ClassListTests {
    private func makePage(_ html: String) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: "")
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        return page
    }

    @Test func addAndRemoveRewriteTheClassAttribute() {
        let page: LayoutTestPage = makePage(#"<p id="p" class="a  b a">x</p>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var list = document.getElementById('p').classList;
            list.add('c', 'a');
            list.remove('b', 'missing');
            [document.getElementById('p').getAttribute('class'), list.length, list.contains('a'), list.contains('b')].join('|')
        """)
        #expect(result?.toString() == "a c|2|true|false")
    }

    @Test func toggleFollowsForce() {
        let page: LayoutTestPage = makePage(#"<p id="p" class="on">x</p>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var list = document.getElementById('p').classList;
            [list.toggle('on'), list.toggle('on'), list.toggle('on', true), list.toggle('off', false),
             document.getElementById('p').getAttribute('class')].join('|')
        """)
        #expect(result?.toString() == "false|true|true|false|on")
    }

    @Test func removingFromAnElementWithoutClassDoesNotAddTheAttribute() {
        let page: LayoutTestPage = makePage(#"<p id="p">x</p>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var p = document.getElementById('p');
            p.classList.remove('dark');
            [p.classList.length, p.hasAttribute('class')].join('|')
        """)
        #expect(result?.toString() == "0|false")
    }

    @Test func emptyOrSpacedTokensThrowAndLeaveTheClassAlone() {
        let page: LayoutTestPage = makePage(#"<p id="p" class="keep">x</p>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var p = document.getElementById('p');
            var names = [];
            try { p.classList.add('ok', ''); } catch (e) { names.push(e.name); }
            try { p.classList.toggle('a b'); } catch (e) { names.push(e.name); }
            names.concat(p.getAttribute('class')).join('|')
        """)
        #expect(result?.toString() == "SyntaxError|InvalidCharacterError|keep")
    }

    @Test func themeScriptPutsTheThemeClassOnTheRootElement() {
        let page: LayoutTestPage = makePage(#"<html class="light"><body><p>x</p></body></html>"#)
        page.frame.js.run(script: "inline", code: #"""
            ((e,i,s,u,m,a,l,h)=>{let d=document.documentElement,w=["light","dark"];function p(n){(Array.isArray(e)?e:[e]).forEach(y=>{let k=y==="class",S=k&&a?m.map(f=>a[f]||f):m;k?(d.classList.remove(...S),d.classList.add(a&&a[n]?a[n]:n)):d.setAttribute(y,n)}),R(n)}function R(n){h&&w.includes(n)&&(d.style.colorScheme=n)}function c(){return window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"}if(u)p(u);else try{let n=localStorage.getItem(i)||s,y=l&&n==="system"?c():n;p(y)}catch(n){}})("class","theme","dark","dark",["light","dark"],null,false,true)
            """#)
        #expect(page.frame.dom.attribute("class", of: page.frame.dom.root) == "dark")
    }
}
