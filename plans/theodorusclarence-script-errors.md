# theodorusclarence.com: `URL`, `o.href.indexOf`, `document.scripts`, `d.classList`, `Unexpected token ':'`

## What the errors are

The console shows **five different problems**, each fixed separately. Reproduced with
`ToyStackHeadless https://theodorusclarence.com/ --run-for 3` on `main` (0d32d62):

| Error | Count | Script | Cause |
|---|---|---|---|
| `SyntaxError: Unexpected token ':'` | 1 | inline `<script id="__NEXT_DATA__" type="application/json">` | ToyStack runs **every** `<script>`, even data blocks. The JSON `{"props":…}` is read as JavaScript |
| `TypeError: … 'document.scripts.length'` | 1 | Cloudflare `email-decode.min.js` | `document.currentScript` and `document.scripts` do not exist |
| `TypeError: … 'd.classList'` | 1 | inline theme script (next-themes) | `document.documentElement` does not exist (and after that, `classList`) |
| `ReferenceError: Can't find variable: URL` | 1 | `turbopack-….js` | The global `URL` class does not exist. Turbopack reads `URL.prototype` on its first line |
| `TypeError: … 'o.href.indexOf'` | 59 | Cloudflare `email-decode.min.js` | `<a>.href` does not exist. The script loops over all 59 links and logs one caught error per link |

### 1. `Unexpected token ':'`: data blocks are run as code

The page has a JSON data block:

```html
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":…}}</script>
```

HTML §4.12.1.1 ("prepare the script element", steps 8–12): a script runs only when its type
is a JavaScript MIME type (or empty/missing). Anything else (`application/json`,
`application/ld+json`, `text/plain`, templates) is data that the page reads itself, and the
browser must not run it.

ToyStack only checks the tag name:

- `Sources/Engine/Core/Frame.swift:389`: external scripts, `$0.tag == "script" && $0.attributes["src"] != nil`
- `Frame.swift:499`: inline scripts, `$0.tag == "script" && $0.attributes["src"] == nil`
- `Frame.swift:771-772`: scripts added later by JavaScript (`runNewScripts`)

### 2. `document.scripts.length`: no `currentScript`

The last thing Cloudflare's decoder does is remove its own `<script>`:

```js
var e = document.currentScript || document.scripts[document.scripts.length - 1];
e.parentNode.removeChild(e);
```

Neither exists in `runtime.js` (`document` is at `Sources/Engine/Resources/runtime.js:9-35`).

Adding only `document.scripts` would be **wrong** for ToyStack. Real browsers run this script
while the page is still being read, so the "last script so far" is the decoder itself.
ToyStack runs scripts after the whole page is read, so the last script is the
`__NEXT_DATA__` block, and the decoder would delete the page's data instead of itself.
`document.currentScript` has to really point at the running script.

Turbopack needs it too: every Next.js chunk starts with
`TURBOPACK.push([document.currentScript, …])`, and the runtime reads its `src` to know which
chunk it got. Without it, the runtime throws `chunk path empty but not in a worker`.

HTML §4.12.1.1 ("execute the script element"): `currentScript` is set to the script element
just before it runs, and set **back to the old value** right after. The "back to the old
value" part matters in ToyStack: a script that does `appendChild(<script src>)` runs the new
script immediately inside that call (`JSRuntime.swift` `_appendChild` → `Frame.runNewScripts`,
`Frame.swift:769`), so scripts nest.

### 3. `d.classList`: no `document.documentElement`, no `classList`

The theme script runs before the page shows and puts the saved theme class on `<html>`:

```js
let d = document.documentElement; … d.classList.remove("light", "dark"); d.classList.add("dark");
```

Both are missing. `classList` (DOM §7.1 "Interface DOMTokenList") is a small view over the
`class` attribute: `add`, `remove`, `contains`, `toggle`, `length`. It can be done in
`runtime.js` on top of `getAttribute`/`setAttribute`, so style invalidation keeps working
through the existing `_setAttribute` (`JSRuntime.swift:122-138`).

DOM §7.1 has two details worth copying:

- `add("")` throws `SyntaxError`, `add("a b")` throws `InvalidCharacterError`.
- `remove()` on an element with no `class` attribute must **not** create an empty
  `class=""` (the "update steps" return early). That needs `hasAttribute`, which ToyStack
  also lacks: `getAttribute` returns `""` for a missing attribute
  (`JSRuntime.swift:118`), so "missing" and "empty" look the same.

### 4. `Can't find variable: URL`

```js
let R = function (e) { let t = new URL(e, "x:/"), r = {}; for (let e in t) r[e] = t[e]; … };
… R.prototype = URL.prototype, u.U = R, …
```

`URL.prototype` is read when the file loads, so the whole Turbopack runtime dies there.
JavaScriptCore on its own does not provide `URL`. It is a browser API (URL Standard §6.1).

### 5. `o.href.indexOf` ×59: no `href` on links

```js
for (var r = t.querySelectorAll("a"), c = 0; c < r.length; c++)
  try { var o = r[c], a = o.href.indexOf(l); … } catch (i) { e(i) }   // e() = console.log
```

`o.href` is `undefined`, the error is caught and logged once per link. HTML §4.6.4
(`href` getter): return the attribute resolved against the page address; if it cannot be
parsed, return the attribute as written; if there is no attribute, return `""`.

The one protected link (`/cdn-cgi/l/email-protection#ec81…`) then hits the next missing
piece: `d.childNodes[0]`. The decoder writes `<a href="…">` into a `div` with `innerHTML`
and reads it back through `childNodes`. Without it the e-mail link stays broken, so
`childNodes` is part of this fix.

## Design decision: what does `URL` use to read addresses?

**Option A: reuse `WebURL` (recommended).** One Swift function, `URLParts.parse`,
resolves with `WebURL.resolve` (`Sources/Engine/Networking/WebURL.swift:342`) and splits the
result into `href`, `protocol`, `host`, `hostname`, `port`, `pathname`, `search`, `hash`,
`origin`.
Good: `new URL(x, location.href)`, `<a>.href`, and the address ToyStack actually fetches or
navigates to all agree, because they use the same code.
Trade-off: `WebURL` only knows `http`, `https`, `file`, `data`, `about`, `view-source`, so
`new URL("mailto:me@x.com")` throws `TypeError` where a real browser would accept it.
`WebURL` turns anything it cannot read into `about:blank` instead of failing, so
`URLParts` has to treat "became about:blank but did not start with `about:`" as "cannot be
parsed".

**Option B: Foundation `URL(string:relativeTo:)`.** Accepts any scheme.
Trade-off: a second URL reader that disagrees with `WebURL`. Checked on this machine:
`URL(string: "not a url")` is **accepted** (it should throw), `""` with a base returns `nil`
(it should return the base), `https://ex.com` has an empty path (it should be `/`), and
`x:/` + `/x` gives `x:///x` (it should be `x:/x`). Every one of those would need its own
patch, and `<a>.href` could point somewhere other than where a click goes.

The steps below use **Option A**.

## Files that change

| File | Why |
|---|---|
| `Sources/Engine/Core/ScriptType.swift` (new) | Decides if a `<script>` is JavaScript (HTML §4.12.1.1) |
| `Sources/Engine/Networking/MIMEType.swift` | Exact (no parameters) JavaScript type match for the `type` attribute |
| `Sources/Engine/Core/Frame.swift` | Skip data blocks; tell `JSRuntime` which `<script>` is running |
| `Sources/Engine/Platform/JSRuntime.swift` | `currentScript` save/restore; new Swift callbacks |
| `Sources/Engine/Platform/URLParts.swift` (new) | Splits a resolved `WebURL` into the fields a `URL` object has |
| `Sources/Engine/Resources/runtime.js` | `document.currentScript/scripts/documentElement`, `hasAttribute`, `classList`, `URL`, `href`, `childNodes` |
| `Tests/ToyStackTests/Core/ScriptTypeTests.swift` (new) | Type rules, including odd cases |
| `Tests/ToyStackTests/Core/PageScriptTests.swift` (new) | Full page load: data blocks skipped; each script sees itself as `currentScript`, also when nested |
| `Tests/ToyStackTests/Platform/JSRuntimeTests.swift` | `currentScript`, `document.scripts`, `href`, `hasAttribute` |
| `Tests/ToyStackTests/Platform/NodeTraversalTests.swift` | `documentElement`, `childNodes` |
| `Tests/ToyStackTests/Platform/ClassListTests.swift` (new) | `classList` plus the site's theme script, copied unchanged |
| `Tests/ToyStackTests/Platform/URLTests.swift` (new) | `URL` class, including the Turbopack usage |
| `Tests/ToyStackTests/Platform/EmailDecodeTests.swift` (new) | Cloudflare's decoder, copied unchanged, decodes the e-mail link and removes itself |

Line numbers below are from `main` at 0d32d62, **before Step 1**. Later steps add lines
above some of them, so the context lines in each diff are the reliable anchor.

---

## Step 1: data blocks are not run

### 1a. Failing tests

New file `Tests/ToyStackTests/Core/ScriptTypeTests.swift`:

```swift
import Testing

@testable import Engine

@Suite
struct ScriptTypeTests {
    @Test func scriptWithoutTypeOrWithEmptyTypeRuns() {
        #expect(ScriptType.isClassic([:]))
        #expect(ScriptType.isClassic(["type": ""]))
        #expect(ScriptType.isClassic(["language": ""]))
    }

    @Test func javaScriptTypesRunWhateverTheirCaseAndSpacing() {
        #expect(ScriptType.isClassic(["type": "text/javascript"]))
        #expect(ScriptType.isClassic(["type": "  Text/JavaScript\n"]))
        #expect(ScriptType.isClassic(["type": "application/ecmascript"]))
        #expect(ScriptType.isClassic(["language": "JavaScript"]))
    }

    @Test func dataBlocksDoNotRun() {
        #expect(!ScriptType.isClassic(["type": "application/json"]))
        #expect(!ScriptType.isClassic(["type": "application/ld+json"]))
        #expect(!ScriptType.isClassic(["type": "text/plain"]))
        #expect(!ScriptType.isClassic(["language": "vbscript"]))
    }

    // HTML §4.12.1.1: the type string is compared whole, so parameters or a type made
    // only of spaces do not count as JavaScript.
    @Test func typeWithParametersOrOnlySpacesDoesNotRun() {
        #expect(!ScriptType.isClassic(["type": "text/javascript; charset=utf-8"]))
        #expect(!ScriptType.isClassic(["type": "   "]))
    }

    @Test func typeAttributeWinsOverLanguage() {
        #expect(!ScriptType.isClassic(["type": "text/plain", "language": "javascript"]))
    }

    // ToyStack cannot load modules yet; running one as a classic script would only
    // throw on its first `import`.
    @Test func modulesAndImportMapsAreNotRunAsClassicScripts() {
        #expect(!ScriptType.isClassic(["type": "module"]))
        #expect(!ScriptType.isClassic(["type": "importmap"]))
    }
}
```

New file `Tests/ToyStackTests/Core/PageScriptTests.swift`. It loads a whole page through
`PageSourceOverride` (`Tests/ToyStackTests/Core/PageSourceOverride.swift`), because the
filter lives in the page-load code. Step 2 adds a second test to this suite.

```swift
import CoreGraphics
import Foundation
import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PageScriptTests {
    @Test func dataBlocksAreNeitherFetchedNorRun() async throws {
        let host: String = "page-script-\(UUID().uuidString.lowercased()).example"
        let page: String = """
            <html><body>
            <script id="__NEXT_DATA__" type="application/json">{"props":{"page":"/"}}</script>
            <script type="text/plain">window.plainRan = true</script>
            <script type="application/json" src="/data.js"></script>
            <script>window.classicRan = true</script>
            </body></html>
            """
        let result: JSValue? = try await load(host: host, files: [
            "/": page,
            "/data.js": "window.dataSrcRan = true",
        ], evaluate: "[typeof plainRan, typeof dataSrcRan, classicRan].join('|')")
        #expect(result?.toString() == "undefined|undefined|true")
    }

    private func load(host: String, files: [String: String], evaluate code: String) async throws -> JSValue? {
        return try await PageSourceOverride.with({ (scheme: String, path: String) in
            guard let body: String = files[path] else { return nil }
            let type: String = path.hasSuffix(".js") ? "text/javascript" : "text/html"
            return (200, ["content-type": type], body)
        }) {
            let browser: Browser = Browser()
            browser.usesAsyncLayout = false
            browser.resize(to: CGSize(width: 800, height: 600))
            browser.newTab(WebURL("https://\(host)/"))
            browser.pauseAnimationTimer()
            let tab: BrowserTab = try #require(browser.activeTab)
            let deadline: Date = Date().addingTimeInterval(10)
            while !tab.isLoaded, Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            #expect(tab.isLoaded)
            return tab.rootFrame.js.evaluate(code)
        }
    }
}
```

`/data.js` is served as real JavaScript on purpose: if the `type` check is missing, it runs
and the test sees it.

Run `swift test --filter "ScriptTypeTests|PageScriptTests"`.
Expected: `ScriptTypeTests` does not compile (`cannot find 'ScriptType' in scope`).
Observed for the page test (with `ScriptTypeTests.swift` set aside):

```
Expectation failed: (result?.toString() → "boolean|boolean|true") == "undefined|undefined|true"
```

`boolean|boolean` = both the `text/plain` block and the `application/json` file ran.

### 1b. Implementation

`Sources/Engine/Networking/MIMEType.swift:26-28`. `isJavaScript` cuts off `; charset=…`
because it reads `Content-Type` headers. The `type` attribute must match **whole** (MIME
Sniffing §4.6 "JavaScript MIME type essence match": ASCII case-insensitive, nothing else).

```diff
     static func isJavaScript(_ contentType: String?) -> Bool {
         javaScriptTypes.contains(essence(contentType))
     }
 
+    static func isJavaScriptEssenceMatch(_ string: String) -> Bool {
+        javaScriptTypes.contains(string.lowercased())
+    }
+
     static func isCSS(_ contentType: String?) -> Bool {
```

New file `Sources/Engine/Core/ScriptType.swift`:

```swift
import Foundation

// MARK: - ScriptType

enum ScriptType {
    private static let asciiWhitespace: CharacterSet = CharacterSet(charactersIn: "\t\n\u{0C}\r ")

    // HTML §4.12.1.1 "prepare the script element", steps 8–12: only a type string that is a
    // JavaScript MIME type essence match runs as a classic script. Anything else (JSON
    // data blocks, templates, "text/plain") is data the page reads itself, and is not run.
    static func isClassic(_ attributes: [String: String]) -> Bool {
        if let type: String = attributes["type"] {
            if type.isEmpty { return true }
            return MIMEType.isJavaScriptEssenceMatch(type.trimmingCharacters(in: asciiWhitespace))
        }
        if let language: String = attributes["language"] {
            if language.isEmpty { return true }
            return MIMEType.isJavaScriptEssenceMatch("text/" + language)
        }
        return true
    }
}
```

`Sources/Engine/Core/Frame.swift:388-389`. One helper picks the external scripts, so Step 2
can find the same list again by index.

```diff
-                let scripts: [ResourceLoad] = elements
-                    .filter({ $0.tag == "script" && $0.attributes["src"] != nil })
+                let scripts: [ResourceLoad] = Self.externalScripts(in: elements)
                     .enumerated()
                     .map({ (i, node) in
```

`Frame.swift:497-503` (inline scripts) and the new helper right after `execScripts`
(`Frame.swift:510`):

```diff
         for scriptNode in treeToList(nodes).compactMap({ $0.element })
-            .filter({ $0.tag == "script" && $0.attributes["src"] == nil })
+            .filter({ $0.tag == "script" && $0.attributes["src"] == nil && ScriptType.isClassic($0.attributes) })
         {
             let code: String = scriptNode.children.compactMap({ $0.text }).map(\.text).joined()
             if !code.isEmpty { js.run(script: "inline", code: code) }
         }
 
         setNeedsRender()
 
         if let fragment = url.fragment {
             scrollToFragment(fragment)
         }
     }
 
+    private static func externalScripts(in elements: [ElementRef]) -> [ElementRef] {
+        return elements.filter({ $0.tag == "script" && $0.attributes["src"] != nil && ScriptType.isClassic($0.attributes) })
+    }
+
     private func fetchImages(
```

`Frame.swift:771-772` (scripts added by JavaScript):

```diff
             guard let el = node.element, el.tag == "script",
-                let src = el.attributes["src"]
+                let src = el.attributes["src"], ScriptType.isClassic(el.attributes)
             else { continue }
```

Behavior change to be aware of: `<script type="module">` used to be run as a normal script
(and usually crashed on `import`). Now it is skipped. That matches what HTML asks for until
ToyStack can load modules.

Run `swift test --filter "ScriptTypeTests|PageScriptTests"`. Both pass.

---

## Step 2: `document.currentScript` and `document.scripts`

### 2a. Failing tests

`Tests/ToyStackTests/Platform/JSRuntimeTests.swift:44-50`:

```diff
     @Test func topWindowHasNoParent() {
         let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
         let js: JSRuntime = JSRuntime(frame: page.frame)
         let result: JSValue? = js.evaluate("window.parent === undefined")
         #expect(result?.toBool() == true)
     }
+
+    @Test func currentScriptIsTheRunningScriptAndNullAfterward() throws {
+        let page: LayoutTestPage = LayoutTestPage(html: #"<script id="s"></script><p>x</p>"#, rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let script: ElementRef = try #require(page.firstElement(id: "s"))
+        js.run(script: "inline", code: "var seen = document.currentScript.id", element: script.id)
+        js.run(script: "setTimeout", code: "var later = document.currentScript")
+        let result: JSValue? = js.evaluate("[seen, later === null, document.currentScript === null].join('|')")
+        #expect(result?.toString() == "s|true|true")
+    }
+
+    @Test func documentScriptsListsScriptsInTreeOrder() {
+        let page: LayoutTestPage = LayoutTestPage(html: #"<script id="a"></script><p>x</p><script id="b"></script>"#, rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let result: JSValue? = js.evaluate("document.scripts.map(function (s) { return s.id; }).join(',') + '|' + document.scripts.length")
+        #expect(result?.toString() == "a,b|2")
+    }
 }
```

Add to `PageScriptTests` (above `private func load`). The outer script adds a second script,
which ToyStack runs **inside** `appendChild`. After that, `currentScript` must be the outer
script again, not `null`.

```diff
         #expect(result?.toString() == "undefined|undefined|true")
     }
 
+    // A script that adds another script runs that one at once, so currentScript has to
+    // come back to the outer script afterward.
+    @Test func eachScriptSeesItselfAsCurrentScript() async throws {
+        let host: String = "page-script-\(UUID().uuidString.lowercased()).example"
+        let page: String = """
+            <html><body>
+            <div id="host"></div>
+            <script id="outer" src="/outer.js"></script>
+            <script id="inline">window.inlineSaw = document.currentScript.id</script>
+            </body></html>
+            """
+        let outer: String = """
+            var inner = document.createElement('script');
+            inner.setAttribute('src', '/inner.js');
+            document.getElementById('host').appendChild(inner);
+            window.outerSawAfterInner = document.currentScript.id;
+            """
+        let result: JSValue? = try await load(host: host, files: [
+            "/": page,
+            "/outer.js": outer,
+            "/inner.js": "window.innerSaw = document.currentScript.getAttribute('src')",
+        ], evaluate: "[outerSawAfterInner, innerSaw, inlineSaw, document.currentScript === null].join('|')")
+        #expect(result?.toString() == "outer|/inner.js|inline|true")
+    }
+
     private func load(host: String, files: [String: String], evaluate code: String) async throws -> JSValue? {
```

Run `swift test --filter "JSRuntimeTests|PageScriptTests"`.
Expected: `currentScriptIsTheRunningScriptAndNullAfterward` does not compile (`extra argument
'element' in call`). Observed for the others (with that one test set aside):

```
documentScriptsListsScriptsInTreeOrder: (result?.toString() → "undefined") == "a,b|2"
eachScriptSeesItselfAsCurrentScript:    (result?.toString() → "undefined") == "outer|/inner.js|inline|true"
```

### 2b. Implementation

`Sources/Engine/Platform/JSRuntime.swift:9` and `JSRuntime.swift:24-29`:

```diff
     private var intervalTimes: [Int: DispatchSourceTimer] = [:]
     private weak var frame: Frame?
+    private var currentScript: NodeID?
```

```diff
-    func run(script: String, code: String) {
+    // HTML §4.12.1.1 "execute the script element": currentScript is the script element
+    // while it runs, then goes back to its old value, so a script started inside another
+    // one (appendChild of a <script src>) hands it back to the outer script.
+    func run(script: String, code: String, element: NodeID? = nil) {
         jsContext.exceptionHandler = { _, exception in
             print("Script", script, "crashed:", exception?.toString() ?? "unknown error")
         }
+        let outer: NodeID? = currentScript
+        currentScript = element
+        defer { currentScript = outer }
         jsContext.evaluateScript(code)
     }
```

Timers, `requestAnimationFrame`, and event handlers keep calling `run` without `element`,
so `currentScript` is `null` there, like in a browser.

`JSRuntime.swift:164-166`, between `_setCookie` and `registerNodeTraversal()`:

```diff
         } as @convention(block) (String) -> Void, forKeyedSubscript: "_setCookie" as NSString)
 
+        jsContext.setObject({
+            [weak self] () -> Int in
+            guard let self, let frame = self.frame else { return -1 }
+            return MainActor.assumeIsolated {
+                guard let id: NodeID = self.currentScript else { return -1 }
+                return self.getHandle(frame.dom.ref(id))
+            }
+        } as @convention(block) () -> Int, forKeyedSubscript: "_currentScript" as NSString)
+
         registerNodeTraversal()
```

`Sources/Engine/Core/Frame.swift:491-494`. The page has not changed between building the
fetch list and this point (no script has run yet), so `index` from the fetch list points at
the same element in `externalScripts`:

```diff
     ) {
-        for (_, scriptURL, body) in bodies.sorted(by: { $0.index < $1.index }) {
-            js.run(script: scriptURL.toString(), code: body)
+        let externalScripts: [ElementRef] = Self.externalScripts(in: treeToList(nodes).compactMap({ $0.element }))
+        for (index, scriptURL, body) in bodies.sorted(by: { $0.index < $1.index }) {
+            js.run(script: scriptURL.toString(), code: body, element: externalScripts[index].id)
             state.document.resources.loadedScripts.insert(scriptURL.toString())
         }
```

`Frame.swift:502`:

```diff
-            if !code.isEmpty { js.run(script: "inline", code: code) }
+            if !code.isEmpty { js.run(script: "inline", code: code, element: scriptNode.id) }
```

`Frame.swift:784`:

```diff
             state.document.resources.loadedScripts.insert(urlStr)
-            js.run(script: urlStr, code: body)
+            js.run(script: urlStr, code: body, element: el.id)
         }
```

`Sources/Engine/Resources/runtime.js:35`, after the `cookie` property. `document.scripts` is
a fresh array on each read, not a live list. That is enough for reading it.

```diff
   set: function (s) {
     _setCookie(s.toString());
   },
 });
 
+Object.defineProperty(document, "currentScript", {
+  get: function () {
+    return __nodeOrNull(_currentScript());
+  },
+});
+
+Object.defineProperty(document, "scripts", {
+  get: function () {
+    return document.querySelectorAll("script");
+  },
+});
+
 function Node(handle) {
```

(`__nodeOrNull` is defined further down, at `runtime.js:155`. That is fine: the getter only
looks it up when a page reads the property.)

Run `swift test --filter "JSRuntimeTests|PageScriptTests"`. All pass.

---

## Step 3: `document.documentElement`, `hasAttribute`, `classList`

### 3a. Failing tests

`Tests/ToyStackTests/Platform/NodeTraversalTests.swift:76-78`:

```diff
         expectIncrementalMatchesFull(page)
     }
+
+    @Test func documentElementIsTheRootWithNoParent() {
+        let page: LayoutTestPage = makePage(#"<html lang="en"><body><p>x</p></body></html>"#)
+        let result: JSValue? = page.frame.js.evaluate("""
+            var root = document.documentElement;
+            [root.getAttribute('lang'), root.parentNode === null].join('|')
+        """)
+        #expect(result?.toString() == "en|true")
+    }
 }
```

New file `Tests/ToyStackTests/Platform/ClassListTests.swift`:

```swift
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

    // Copied unchanged from theodorusclarence.com (next-themes). It runs before the page
    // paints and puts the saved theme on <html>.
    @Test func themeScriptPutsTheThemeClassOnTheRootElement() {
        let page: LayoutTestPage = makePage(#"<html class="light"><body><p>x</p></body></html>"#)
        page.frame.js.run(script: "inline", code: #"""
            ((e,i,s,u,m,a,l,h)=>{let d=document.documentElement,w=["light","dark"];function p(n){(Array.isArray(e)?e:[e]).forEach(y=>{let k=y==="class",S=k&&a?m.map(f=>a[f]||f):m;k?(d.classList.remove(...S),d.classList.add(a&&a[n]?a[n]:n)):d.setAttribute(y,n)}),R(n)}function R(n){h&&w.includes(n)&&(d.style.colorScheme=n)}function c(){return window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"}if(u)p(u);else try{let n=localStorage.getItem(i)||s,y=l&&n==="system"?c():n;p(y)}catch(n){}})("class","theme","dark","dark",["light","dark"],null,false,true)
            """#)
        #expect(page.frame.dom.attribute("class", of: page.frame.dom.root) == "dark")
    }
}
```

`add('ok', '')` checks every token **before** changing anything, so `keep` must still be
the only class afterward.

Run `swift test --filter "NodeTraversalTests|ClassListTests"`. Observed:

```
documentElementIsTheRootWithNoParent:           (result?.toString() → "undefined") == "en|true"
addAndRemoveRewriteTheClassAttribute:           (result?.toString() → "undefined") == "a c|2|true|false"
toggleFollowsForce:                             (result?.toString() → "undefined") == "false|true|true|false|on"
emptyOrSpacedTokensThrowAndLeaveTheClassAlone:  (result?.toString() → "TypeError|TypeError|keep") == "SyntaxError|InvalidCharacterError|keep"
themeScriptPutsTheThemeClassOnTheRootElement:   (… → "light") == "dark"
```

### 3b. Implementation

`Sources/Engine/Platform/JSRuntime.swift:120`, right after `_getAttribute`:

```diff
         } as @convention(block) (Int, String) -> String, forKeyedSubscript: "_getAttribute" as NSString)
 
+        jsContext.setObject({
+            [weak self] (handle: Int, attr: String) -> Bool in
+            guard let self, let frame = self.frame,
+                let id = self.handleToNode[handle]
+            else { return false }
+            return MainActor.assumeIsolated { frame.dom.attribute(attr, of: id) != nil }
+        } as @convention(block) (Int, String) -> Bool, forKeyedSubscript: "_hasAttribute" as NSString)
+
         jsContext.setObject({
             [weak self] (handle: Int, attr: String, value: String) in
```

`JSRuntime.swift:545`, in `registerNodeTraversal`. The DOM root (`NodeID(raw: 0)`) is
always the `<html>` element (`Sources/Engine/Parsing/DOMTree.swift:19-30`):

```diff
         registerNodeLookup("_nextSibling", { dom, id in dom.nextSibling(of: id) })
 
+        jsContext.setObject({
+            [weak self] () -> Int in
+            guard let self, let frame = self.frame else { return -1 }
+            return MainActor.assumeIsolated { self.getHandle(frame.nodes) }
+        } as @convention(block) () -> Int, forKeyedSubscript: "_documentElement" as NSString)
+
         jsContext.setObject({
             [weak self] (handle: Int) -> Int in
```

`Sources/Engine/Resources/runtime.js`, after the `scripts` getter from Step 2:

```diff
 Object.defineProperty(document, "scripts", {
   get: function () {
     return document.querySelectorAll("script");
   },
 });
 
+Object.defineProperty(document, "documentElement", {
+  get: function () {
+    return __nodeOrNull(_documentElement());
+  },
+});
+
 function Node(handle) {
```

`runtime.js:76-78`:

```diff
 Node.prototype.setAttribute = function (attr, value) {
   _setAttribute(this.handle, attr, value.toString());
 };
 
+Node.prototype.hasAttribute = function (attr) {
+  return _hasAttribute(this.handle, attr);
+};
+
 var LISTENERS = {};
```

`runtime.js:189-196`, after the `data` property. JavaScriptCore has no `DOMException`, so
`__domException` makes a plain `Error` with the `name` the DOM standard uses (that is what
pages check: `e.name === "SyntaxError"`).

```diff
 Object.defineProperty(Node.prototype, "data", {
   get: function () {
     return _getData(this.handle);
   },
   set: function (value) {
     _setData(this.handle, value.toString());
   },
 });
 
+function __domException(name, message) {
+  var error = new Error(message);
+  error.name = name;
+  return error;
+}
+
+function __validToken(token) {
+  token = String(token);
+  if (token === "") throw __domException("SyntaxError", "The token must not be empty.");
+  if (/[\t\n\f\r ]/.test(token)) throw __domException("InvalidCharacterError", "The token must not contain whitespace.");
+  return token;
+}
+
+function DOMTokenList(node) {
+  this._node = node;
+}
+
+DOMTokenList.prototype._tokens = function () {
+  var tokens = [];
+  var parts = this._node.getAttribute("class").split(/[\t\n\f\r ]+/);
+  for (var i = 0; i < parts.length; i++) {
+    if (parts[i] !== "" && tokens.indexOf(parts[i]) === -1) tokens.push(parts[i]);
+  }
+  return tokens;
+};
+
+// DOM §7.1 "update steps": an element with no class attribute and nothing to write
+// keeps having no class attribute.
+DOMTokenList.prototype._update = function (tokens) {
+  if (!this._node.hasAttribute("class") && tokens.length === 0) return;
+  this._node.setAttribute("class", tokens.join(" "));
+};
+
+Object.defineProperty(DOMTokenList.prototype, "length", {
+  get: function () {
+    return this._tokens().length;
+  },
+});
+
+DOMTokenList.prototype.contains = function (token) {
+  return this._tokens().indexOf(String(token)) !== -1;
+};
+
+DOMTokenList.prototype.add = function () {
+  var added = Array.prototype.map.call(arguments, __validToken);
+  var tokens = this._tokens();
+  for (var i = 0; i < added.length; i++) {
+    if (tokens.indexOf(added[i]) === -1) tokens.push(added[i]);
+  }
+  this._update(tokens);
+};
+
+DOMTokenList.prototype.remove = function () {
+  var removed = Array.prototype.map.call(arguments, __validToken);
+  var tokens = this._tokens().filter(function (token) {
+    return removed.indexOf(token) === -1;
+  });
+  this._update(tokens);
+};
+
+DOMTokenList.prototype.toggle = function (token, force) {
+  token = __validToken(token);
+  var tokens = this._tokens();
+  var index = tokens.indexOf(token);
+  if (index !== -1) {
+    if (force === true) return true;
+    tokens.splice(index, 1);
+    this._update(tokens);
+    return false;
+  }
+  if (force === false) return false;
+  tokens.push(token);
+  this._update(tokens);
+  return true;
+};
+
+Object.defineProperty(Node.prototype, "classList", {
+  get: function () {
+    return new DOMTokenList(this);
+  },
+});
+
 function Event(type) {
```

Writes go through `setAttribute`, so the existing `_setAttribute` callback
(`JSRuntime.swift:122-138`) still marks style and layout as changed.

Run `swift test --filter "NodeTraversalTests|ClassListTests"`. All pass.

---

## Step 4: the `URL` class (Option A)

### 4a. Failing tests

New file `Tests/ToyStackTests/Platform/URLTests.swift`:

```swift
import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct URLTests {
    private func makeRuntime() -> JSRuntime {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        return JSRuntime(frame: page.frame)
    }

    @Test func relativeURLResolvesAgainstTheBase() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var u = new URL('../img/a.png?w=2#top', 'https://example.com:8443/blog/post/');
            [u.href, u.protocol, u.host, u.hostname, u.port, u.pathname, u.search, u.hash, u.origin].join('|')
        """)
        #expect(result?.toString() == "https://example.com:8443/blog/img/a.png?w=2#top|https:|example.com:8443|example.com|8443|/blog/img/a.png|?w=2|#top|https://example.com:8443")
    }

    @Test func defaultPortIsLeftOut() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("var u = new URL('https://example.com/'); [u.host, u.port, u.origin, String(u)].join('|')")
        #expect(result?.toString() == "example.com||https://example.com|https://example.com/")
    }

    @Test func absoluteInputIgnoresTheBase() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("new URL('https://cdn.example.net/x.js', 'https://example.com/a/').href")
        #expect(result?.toString() == "https://cdn.example.net/x.js")
    }

    @Test func unparseableInputThrowsTypeError() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var names = [];
            try { new URL('not a url'); } catch (e) { names.push(e instanceof TypeError); }
            try { new URL('/a', 'also not a url'); } catch (e) { names.push(e instanceof TypeError); }
            names.join('|')
        """)
        #expect(result?.toString() == "true|true")
    }

    // Turbopack's runtime reads URL.prototype on its first line and copies a URL's own
    // fields with for...in.
    @Test func turbopackCanSubclassAndCopyAURL() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var R = function () {}; R.prototype = URL.prototype;
            var copied = [];
            for (var key in new URL('https://example.com/a')) copied.push(key);
            [new R() instanceof URL, copied.indexOf('href') !== -1, copied.indexOf('pathname') !== -1].join('|')
        """)
        #expect(result?.toString() == "true|true|true")
    }
}
```

Run `swift test --filter URLTests`. Observed: every test gets `"undefined"` (for example
`(result?.toString() → "undefined") == "https://cdn.example.net/x.js"`), and
`unparseableInputThrowsTypeError` gets `"false|false"` (the error is a `ReferenceError`, not
a `TypeError`).

### 4b. Implementation

New file `Sources/Engine/Platform/URLParts.swift`:

```swift
import Foundation

// MARK: - URLParts

enum URLParts {
    // URL Standard §6.1 "URL class": a URL that cannot be parsed makes the constructor
    // throw, so an unparseable input gives no parts at all.
    static func parse(_ input: String, base: String) -> [String: String] {
        guard let url: WebURL = resolve(input, base: base) else { return [:] }
        let defaultPort: Int = url.scheme == "https" ? 443 : (url.scheme == "http" ? 80 : 0)
        let port: String = url.port == defaultPort ? "" : String(url.port)
        let host: String = port.isEmpty ? url.host : url.host + ":" + port
        let queryStart: String.Index = url.path.firstIndex(of: "?") ?? url.path.endIndex
        let search: String = String(url.path[queryStart...])
        let fragment: String = url.fragment ?? ""
        let isHTTP: Bool = url.scheme == "http" || url.scheme == "https"
        return [
            "href": url.toString(),
            "protocol": url.scheme + ":",
            "host": host,
            "hostname": url.host,
            "port": port,
            "pathname": String(url.path[..<queryStart]),
            "search": search == "?" ? "" : search,
            "hash": fragment.isEmpty ? "" : "#" + fragment,
            "origin": isHTTP ? url.scheme + "://" + host : "null",
        ]
    }

    // URL Standard §4.4 "basic URL parser": an input that starts with its own scheme
    // ("mailto:", "https:") is parsed on its own, and the base is not used.
    private static func resolve(_ input: String, base: String) -> WebURL? {
        if base.isEmpty || hasScheme(input) { return loadable(input) }
        guard let baseURL: WebURL = loadable(base) else { return nil }
        let resolved: WebURL = baseURL.resolve(input)
        return resolved.scheme == "about" ? nil : resolved
    }

    // WebURL turns anything it cannot load into about:blank instead of failing.
    private static func loadable(_ input: String) -> WebURL? {
        let url: WebURL = WebURL(input)
        return url.scheme == "about" && !input.hasPrefix("about:") ? nil : url
    }

    // URL Standard §4.4 "scheme start state" and "scheme state": an ASCII letter, then
    // ASCII letters, digits, "+", "-" or ".", then ":".
    private static func hasScheme(_ input: String) -> Bool {
        guard let colon: String.Index = input.firstIndex(of: ":") else { return false }
        let scheme: Substring = input[input.startIndex..<colon]
        guard let first: Character = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy({ (c: Character) -> Bool in
            c.isASCII && (c.isLetter || c.isNumber || c == "+" || c == "-" || c == ".")
        })
    }
}
```

`hasScheme` matters for Step 5: `WebURL.resolve` (`WebURL.swift:342-375`) only treats
`://` as absolute, so on its own it would turn `mailto:me@x.com` into
`https://site/mailto:me@x.com`.

`Sources/Engine/Platform/JSRuntime.swift:510`, after `_getLocationHref`:

```diff
         } as @convention(block) () -> String, forKeyedSubscript: "_getLocationHref" as NSString)
 
+        jsContext.setObject({
+            (input: String, base: String) -> [String: String] in
+            URLParts.parse(input, base: base)
+        } as @convention(block) (String, String) -> [String: String], forKeyedSubscript: "_parseURL" as NSString)
+
         jsContext.setObject({
             [weak self] (raw: String) in
```

`Sources/Engine/Resources/runtime.js:462-464`, after `location.hash`. The fields are the
object's own properties (so `for…in` copies them, as Turbopack expects). They are filled
in once: changing `u.pathname` later does not update `u.href`.

```diff
     _setLocationHref(hash);
   }
 });
 
+function URL(url, base) {
+  var parts = _parseURL(String(url), base === undefined ? "" : String(base));
+  if (parts.href === undefined) throw new TypeError("Invalid URL: " + url);
+  for (var name in parts) this[name] = parts[name];
+}
+
+URL.prototype.toString = function () {
+  return this.href;
+};
+
+URL.prototype.toJSON = URL.prototype.toString;
+
 var window = __globalThis;
```

Run `swift test --filter URLTests`. All pass.

---

## Step 5: `href` on links and `childNodes` (Cloudflare e-mail links)

### 5a. Failing tests

`Tests/ToyStackTests/Platform/JSRuntimeTests.swift`, after the Step 2 tests:

```diff
         #expect(result?.toString() == "a,b|2")
     }
+
+    @Test func linkHrefIsResolvedAgainstThePage() {
+        let page: LayoutTestPage = LayoutTestPage(
+            html: #"<a id="rel" href="../about">a</a><a id="mail" href="mailto:me@example.com">m</a><a id="none">n</a>"#,
+            rules: ""
+        )
+        page.frame.setURL(WebURL("https://example.com/blog/post"))
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let result: JSValue? = js.evaluate("""
+            ['rel', 'mail', 'none'].map(function (id) { return document.getElementById(id).href; }).join('|')
+        """)
+        #expect(result?.toString() == "https://example.com/about|mailto:me@example.com|")
+    }
+
+    @Test func settingHrefWritesTheAttribute() {
+        let page: LayoutTestPage = LayoutTestPage(html: #"<a id="a" href="/x">a</a>"#, rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let result: JSValue? = js.evaluate("""
+            var a = document.getElementById('a');
+            a.href = 'mailto:me@example.com';
+            [a.getAttribute('href'), a.hasAttribute('href'), a.hasAttribute('title')].join('|')
+        """)
+        #expect(result?.toString() == "mailto:me@example.com|true|false")
+    }
 }
```

`mailto:` covers the "cannot be parsed → return the attribute as written" rule of HTML
§4.6.4. `WebURL` cannot hold `mailto:`, and the getter must not invent
`https://example.com/blog/mailto:…`.

`Tests/ToyStackTests/Platform/NodeTraversalTests.swift`, after the Step 3 test:

```diff
         #expect(result?.toString() == "en|true")
     }
+
+    @Test func childNodesListsTextAndCommentsButChildrenDoesNot() {
+        let page: LayoutTestPage = makePage(#"<div id="box">a<!--m--><p>b</p></div>"#)
+        let result: JSValue? = page.frame.js.evaluate("""
+            var box = document.getElementById('box');
+            [box.childNodes.map(function (n) { return n.nodeType; }).join(''), box.children.length].join('|')
+        """)
+        #expect(result?.toString() == "381|1")
+    }
 }
```

New file `Tests/ToyStackTests/Platform/EmailDecodeTests.swift`. The decoder is the exact
file from `https://theodorusclarence.com/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js`.
`ec81…8381` is the site's real protected address. It decodes to `me@theodorusclarence.com`.

```swift
import Testing

@testable import Engine

// The decoder script is copied unchanged from Cloudflare (served on
// theodorusclarence.com). Cloudflare hides e-mail links behind
// "/cdn-cgi/l/email-protection#<hex>" and this script turns them back into "mailto:".
@Suite(.serialized)
@MainActor
struct EmailDecodeTests {
    private let decoder: String = #"""
        !function(){"use strict";function e(e){try{if("undefined"==typeof console)return;"error"in console?console.error(e):console.log(e)}catch(e){}}function t(e){return d.innerHTML='<a href="'+e.replace(/"/g,"&quot;")+'"></a>',d.childNodes[0].getAttribute("href")||""}function r(e,t){var r=e.substr(t,2);return parseInt(r,16)}function n(n,c){for(var o="",a=r(n,c),i=c+2;i<n.length;i+=2){var l=r(n,i)^a;o+=String.fromCharCode(l)}try{o=decodeURIComponent(escape(o))}catch(u){e(u)}return t(o)}function c(t){for(var r=t.querySelectorAll("a"),c=0;c<r.length;c++)try{var o=r[c],a=o.href.indexOf(l);a>-1&&(o.href="mailto:"+n(o.href,a+l.length))}catch(i){e(i)}}function o(t){for(var r=t.querySelectorAll(u),c=0;c<r.length;c++)try{var o=r[c],a=o.parentNode,i=o.getAttribute(f);if(i){var l=n(i,0),d=document.createTextNode(l);a.replaceChild(d,o)}}catch(h){e(h)}}function a(t){for(var r=t.querySelectorAll("template"),n=0;n<r.length;n++)try{i(r[n].content)}catch(c){e(c)}}function i(t){try{c(t),o(t),a(t)}catch(r){e(r)}}var l="/cdn-cgi/l/email-protection#",u=".__cf_email__",f="data-cfemail",d=document.createElement("div");i(document),function(){var e=document.currentScript||document.scripts[document.scripts.length-1];e.parentNode.removeChild(e)}()}();
        """#

    @Test func protectedLinkBecomesMailtoAndTheDecoderRemovesItself() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><a id="mail" href="/cdn-cgi/l/email-protection#ec8189ac9884898388839e999f8f808d9e89828f89c28f8381">Email</a><a id="blog" href="/blog">Blog</a></p><script id="decoder" src="/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>"#,
            rules: ""
        )
        page.frame.setURL(WebURL("https://theodorusclarence.com/"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        let decoderScript: ElementRef = try #require(page.firstElement(id: "decoder"))

        page.frame.js.run(script: "email-decode", code: decoder, element: decoderScript.id)

        let mail: ElementRef = try #require(page.firstElement(id: "mail"))
        let blog: ElementRef = try #require(page.firstElement(id: "blog"))
        #expect(mail.attributes["href"] == "mailto:me@theodorusclarence.com")
        #expect(blog.attributes["href"] == "/blog")
        #expect(page.firstElement(id: "decoder") == nil)
    }
}
```

Run `swift test --filter "JSRuntimeTests|NodeTraversalTests|EmailDecodeTests"`. Observed:

```
linkHrefIsResolvedAgainstThePage:                 (result?.toString() → "||") == "https://example.com/about|mailto:me@example.com|"
settingHrefWritesTheAttribute:                    (result?.toString() → "undefined") == "mailto:me@example.com|true|false"
childNodesListsTextAndCommentsButChildrenDoesNot: (result?.toString() → "undefined") == "381|1"
```

[INFERENCE] `EmailDecodeTests` fails only on the `mailto:` line at this point; Step 2 already
lets the decoder find and remove its own `<script>`.

### 5b. Implementation

`Sources/Engine/Platform/JSRuntime.swift`, in `registerNodeTraversal` after the
`_documentElement` callback from Step 3. `_children` (`JSRuntime.swift:232-242`) keeps only
elements; `childNodes` (DOM §4.4) keeps text and comments too:

```diff
         } as @convention(block) () -> Int, forKeyedSubscript: "_documentElement" as NSString)
 
+        jsContext.setObject({
+            [weak self] (handle: Int) -> [Int] in
+            guard let self, let frame = self.frame,
+                let id = self.handleToNode[handle]
+            else { return [] }
+            return MainActor.assumeIsolated({
+                frame.dom.children(of: id).map({ self.getHandle(frame.dom.ref($0)) })
+            })
+        } as @convention(block) (Int) -> [Int], forKeyedSubscript: "_childNodes" as NSString)
+
         jsContext.setObject({
             [weak self] (handle: Int) -> Int in
```

`Sources/Engine/Resources/runtime.js:146-153`, after `children`:

```diff
 Object.defineProperty(Node.prototype, "children", {
   get: function () {
     var handles = _children(this.handle);
     return handles.map(function (h) {
       return new Node(h);
     });
   },
 });
 
+Object.defineProperty(Node.prototype, "childNodes", {
+  get: function () {
+    return _childNodes(this.handle).map(function (h) {
+      return new Node(h);
+    });
+  },
+});
+
 function __nodeOrNull(handle) {
```

`runtime.js`, after the `classList` property from Step 3:

```diff
 Object.defineProperty(Node.prototype, "classList", {
   get: function () {
     return new DOMTokenList(this);
   },
 });
 
+// HTML §4.6.4 href getter: no attribute gives "", an address that cannot be parsed
+// is returned as written, anything else is resolved against the page.
+Object.defineProperty(Node.prototype, "href", {
+  get: function () {
+    if (!this.hasAttribute("href")) return "";
+    var raw = this.getAttribute("href");
+    return _parseURL(raw, _getLocationHref()).href || raw;
+  },
+  set: function (value) {
+    this.setAttribute("href", value);
+  },
+});
+
 function Event(type) {
```

ToyStack has one `Node` prototype for every element, so `href` also shows up on a `<div>`
(as `""`), the same way `getContext` already does. That is harmless for real pages.

Run `swift test --filter "JSRuntimeTests|NodeTraversalTests|EmailDecodeTests"`. All pass.

---

## Result

Checked in a throwaway copy of the repo (not `main`) with all five steps applied:

| | Before | After |
|---|---|---|
| Console errors on theodorusclarence.com | 63 | **0** |
| `swift test` | — | 916 tests in 147 suites pass |
| JS run time during load (`BrowserTab.load.exec` in the trace) | 108 ms | 212 ms |

The longer JS time is expected: Turbopack and the decoder used to die on their first line,
and now they run to the end. This is the effect already noted in
`plans/js-load-lag-and-missing-dom-apis.md` ("implement the APIs and more page JS actually
runs").

The screenshot does **not** change. The site still looks unstyled because of CSS and
layout gaps, not JavaScript. The `dark` class now really is on `<html>`, so once ToyStack
matches the site's dark-mode selectors, the theme will follow.

## Limits (on purpose, not in this change)

- `new URL("mailto:…")`, `tel:`, `blob:` throw `TypeError` (Option A trade-off).
- `URL` fields are filled in once. Setters (`u.pathname = …`) do not update `href`.
  `URLSearchParams` does not exist yet.
- `document.scripts` is a new array on each read, not a live list.
- `<script type="module">` no longer runs (see Step 1).
- Not caused by this change, but seen while checking: `MIMEType.javaScriptTypes`
  (`Sources/Engine/Networking/MIMEType.swift:13-24`) lists `application/x-ecmascript`
  twice and is missing `application/x-javascript` and `text/javascript1.0`–`1.5` from
  MIME Sniffing §4.6. Servers that send `application/x-javascript` get their scripts
  refused today. That is worth its own small fix.
