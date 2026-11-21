# Next.js pages (palm-co.de): `self` errors, the 404, and `$RC` crashes

## What the errors are

The ~110 lines in the console come from **three separate problems**. One fix does not
touch the others.

| Error | Count | Cause |
|---|---|---|
| `Refused execute script … %5Blang%5D/page-….js - server replied 404` | 1 | ToyStack escapes the `%` in the address a second time |
| `ReferenceError: Can't find variable: self` | ~97 | `self` does not exist in ToyStack's JavaScript |
| `undefined is not an object (evaluating 'c.parentNode.removeChild')` | 4–9 | React's "swap in streamed content" script needs DOM features ToyStack lacks |

### 1. The 404: `%5B` is sent as `%255B`

The page asks for `/_next/static/chunks/app/%5Blang%5D/page-df785624a37a2726.js`
(`[lang]` is a Next.js route folder; `%5B`/`%5D` are the escaped `[`/`]`).

`WebURL.makeHTTPRequest` (`Sources/Engine/Networking/WebURL.swift:202`) copies the path
into `URLComponents.path` (`WebURL.swift:209`, `WebURL.swift:212`). That property takes
**unescaped** text, so Foundation escapes every `%` into `%25`:

```
/app/%5Blang%5D/page.js  ->  https://palm-co.de/app/%255Blang%255D/page.js
```

Checked against the real server:

| Address sent | Status |
|---|---|
| `…/app/%5Blang%5D/page-df785624a37a2726.js` | 200 |
| `…/app/[lang]/page-df785624a37a2726.js` | 200 |
| `…/app/%255Blang%255D/page-df785624a37a2726.js` | **404** |

The same function builds image requests (`WebURL.swift:311`), so any image address with
`%` in its path is broken the same way.

The naive fix, `components.percentEncodedPath = path`, is not enough: Foundation
**crashes** (`Fatal error: Attempting to set percentEncodedPath with invalid characters`)
on paths like `/100%` or `/[lang]`. The path must first be cleaned up: keep `%XX` escapes
that are already valid, escape everything else.

### 2. `self` is missing because `window` is not the global object

Every Next.js chunk starts with

```js
(self.webpackChunk_N_E = self.webpackChunk_N_E || []).push(...)
```

and every inline script on the page is `self.__next_f.push([...])`.

In a real browser, the global object **is** the window, and `self`, `window`,
`globalThis` and `window.window` are all that same object (HTML Standard, "The Window
object"). In ToyStack, `runtime.js` creates a separate object instead:

- `Sources/Engine/Resources/runtime.js:421` — `window = new Window(_getWindowID());`
- `runtime.js:424-430` — then copies a few globals onto it by hand
  (`window.console = console`, `window.document = document`, …)
- `runtime.js:482` — same for `requestAnimationFrame`

`self` is never defined, so every Next.js script dies on its first line. That is 13
chunks plus ~80 inline scripts.

Just adding `var self = window` would hide the error but keep the wrong shape: a value
set through `self.x` would not be a global `x`, and a polyfill that installs `fetch` on
`globalThis` would not show up on `window.fetch`. See the design decision below.

### 3. `$RC` and `c.parentNode.removeChild`

Next.js (React) streams the page. It first sends a loading placeholder, then the real
section later inside a hidden `div`, followed by a tiny script that swaps them:

```html
<!--$?--><template id="B:0"></template> …loading placeholder… <!--/$-->
…
<div hidden id="S:0"> …real section… </div>
<script>$RC("B:0","S:0")</script>
```

`$RC` is plain DOM code: `getElementById`, `parentNode`, `previousSibling`,
`nextSibling`, `firstChild`, `nodeType`, comment `data`, `removeChild`, `insertBefore`.
ToyStack's `Node` (`runtime.js:37-153`) has none of the walking properties, and
`HTMLParser` throws comments away (`Sources/Engine/Parsing/HTMLParser.swift:58-64`,
`HTMLParser.swift:92-98`), so `<!--$?-->` and `<!--/$-->` markers never reach the DOM.
Fixing `$RC` means **comment nodes in the DOM**. That is a bigger feature and gets its
own plan (see "Later" below).

## What happens after fixes 1 and 2

Tried in a throwaway copy of the repo (not in `main`), running `ToyStackHeadless` on
`https://palm-co.de/`:

| | Before | After fixes 1 + 2 |
|---|---|---|
| 404 | 1 | 0 |
| `self` errors | ~97 | 0 |
| `$RC` errors | 4 | 4 (expected, problem 3) |
| New error | — | `webpack-….js`: `Can't find variable: TextEncoder` |

After adding a quick `TextEncoder` and `parentNode` in the same copy, the next one was
`document.documentElement.id`. That is React starting to *hydrate* the page (attach its
event handlers to the server HTML). Hydration needs a long list of browser features;
chasing it error by error is not worth it here. The page content is already in the
HTML, so the `$RC` swap is what matters for what you see.

Separate thing, not caused by JavaScript: the screenshot shows the text of `<style>` and
`<script>` blocks drawn on the page. palm-co.de puts a `<style>` and all its `<script>`s
inside `<body>`, next to `div`s. `BlockLayoutPass` skips hidden tags when it builds
anonymous blocks (`Sources/Engine/Layouts/BlockLayoutPass.swift:775`). [INFERENCE] The
inline item walk (`BlockLayoutPass.swift:1175`, `BlockLayoutPass.swift:1194`) does not
skip them, which is probably how they leak. That needs its own investigation.

## Design decision: how to give scripts `self`

**Option A — alias:** add `var self = window;`. One line.
Downside: `window` is still not the global object. `self.foo = 1` does not create a
global `foo`. Anything installed on `globalThis` (polyfills) is missing from
`window`/`self`. The hand-copied list at `runtime.js:424-430` keeps growing.

**Option B — make the global object the window (recommended):**
`window` and `self` both point at the global object. The `Window.prototype` members
(`addEventListener`, `dispatchEvent`, `postMessage`, `parent`) get copied onto it.
JavaScriptCore does not let us change the global object's prototype
(`Reflect.setPrototypeOf(globalThis, Window.prototype)` returns `false`), so copying is
the only way. The hand-copied list and `window.requestAnimationFrame = …` go away,
because every global function is already a property of the window.
Downside: the window's internal `_id` and the runtime's helpers (`WINDOWS`,
`LISTENERS`, …) are now visible as globals that page code could overwrite. That is
already true of the helpers today.

`new Window(id)` stays for the *other* frames' windows (`parent`, `runtime.js:460-469`).

The tests below pin Option B: `self.__next_f` set in one script must be readable as
`__next_f` in the next.

## Files that change

| File | Why |
|---|---|
| `Tests/ToyStackTests/Networking/WebURLTests.swift` | Failing test: the request address keeps `%5B` |
| `Tests/ToyStackTests/Networking/PathPercentEncodingTests.swift` (new) | Cleanup rules, incl. paths that would crash Foundation |
| `Sources/Engine/Networking/PathPercentEncoding.swift` (new) | Escapes a path for `URLComponents.percentEncodedPath` |
| `Sources/Engine/Networking/WebURL.swift` | Use it; open `makeHTTPRequest` to tests |
| `Tests/ToyStackTests/Platform/JSRuntimeTests.swift` | Failing tests: `self`/`window`/global are one object |
| `Sources/Engine/Resources/runtime.js` | Option B |

---

## Step 1 — failing test for the 404

`makeHTTPRequest` is `private`; open it to `@testable` tests so the test checks the exact
address that goes on the wire.

`Sources/Engine/Networking/WebURL.swift:202`

```diff
-    private func makeHTTPRequest(method: String, referrer: WebURL?, payload: String?, extraHeaders: [String: String]) async -> URLRequest {
+    func makeHTTPRequest(method: String, referrer: WebURL?, payload: String?, extraHeaders: [String: String]) async -> URLRequest {
```

`Tests/ToyStackTests/Networking/WebURLTests.swift:1` and the end of the suite
(`WebURLTests.swift:143-149`):

```diff
+import Foundation
 import Testing
 
 @testable import Engine
```

```diff
     @Test func aboutURLWithoutPageNameHasEmptyPath() {
         let url: WebURL = WebURL("about:")
         #expect(url.scheme == "about")
         #expect(url.path == "")
     }
+
+    // MARK: - request URL
+    @Test func requestKeepsPercentEscapesInPath() async {
+        let url: WebURL = WebURL("https://example.com/_next/static/chunks/app/%5Blang%5D/page.js")
+        let request: URLRequest = await url.makeHTTPRequest(method: "GET", referrer: nil, payload: nil, extraHeaders: [:])
+        #expect(request.url?.absoluteString == "https://example.com/_next/static/chunks/app/%5Blang%5D/page.js")
+    }
+
+    @Test func requestWithStrayPercentInPathDoesNotTrap() async {
+        let url: WebURL = WebURL("https://example.com/100%?q=1")
+        let request: URLRequest = await url.makeHTTPRequest(method: "GET", referrer: nil, payload: nil, extraHeaders: [:])
+        #expect(request.url?.absoluteString == "https://example.com/100%25?q=1")
+    }
 }
```

Run `swift test --filter WebURLTests`. Expected failure (observed):

```
Expectation failed: (request.url?.absoluteString → "https://example.com/_next/static/chunks/app/%255Blang%255D/page.js") == "…/%5Blang%5D/page.js"
```

`requestWithStrayPercentInPathDoesNotTrap` passes today. It is there so Step 2 cannot
swap the 404 for a crash.

## Step 2 — escape the path once

New file `Sources/Engine/Networking/PathPercentEncoding.swift`. It works on bytes, so
there is no `String(format:)` per character:

```diff
+import Foundation
+
+// MARK: - PathPercentEncoding
+enum PathPercentEncoding {
+    private static let percentSign: UInt8 = UInt8(ascii: "%")
+    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)
+    private static let allowed: CharacterSet = .urlPathAllowed
+
+    static func encode(_ path: String) -> String {
+        let bytes: [UInt8] = Array(path.utf8)
+        var output: [UInt8] = []
+        output.reserveCapacity(bytes.count)
+        var index: Int = 0
+        while index < bytes.count {
+            let byte: UInt8 = bytes[index]
+            if byte == percentSign, isEscape(bytes, at: index) {
+                output.append(contentsOf: bytes[index..<index + 3])
+                index += 3
+                continue
+            }
+            // URL Standard §4.4 path state keeps a stray "%" as-is, but Foundation's
+            // percentEncodedPath traps on it, so it is written as "%25" instead.
+            if byte < 0x80, byte != percentSign, allowed.contains(Unicode.Scalar(byte)) {
+                output.append(byte)
+            } else {
+                output.append(percentSign)
+                output.append(hexDigits[Int(byte >> 4)])
+                output.append(hexDigits[Int(byte & 0x0F)])
+            }
+            index += 1
+        }
+        return String(decoding: output, as: UTF8.self)
+    }
+
+    private static func isEscape(_ bytes: [UInt8], at index: Int) -> Bool {
+        guard index + 2 < bytes.count else { return false }
+        return isHexDigit(bytes[index + 1]) && isHexDigit(bytes[index + 2])
+    }
+
+    private static func isHexDigit(_ byte: UInt8) -> Bool {
+        switch byte {
+        case UInt8(ascii: "0")...UInt8(ascii: "9"),
+            UInt8(ascii: "a")...UInt8(ascii: "f"),
+            UInt8(ascii: "A")...UInt8(ascii: "F"):
+            return true
+        default:
+            return false
+        }
+    }
+}
```

The spec comment was checked against https://url.spec.whatwg.org/ §4.4 "path state":
a `%` not followed by two hex digits is only a validation error, and the code point is
then percent-encoded with the *path percent-encode set* (§1.3), which does not contain `%`.

New file `Tests/ToyStackTests/Networking/PathPercentEncodingTests.swift`. Covers paths
that are already escaped, raw characters, non-ASCII, and three broken escapes that would
crash Foundation:

```diff
+import Testing
+
+@testable import Engine
+
+@Suite struct PathPercentEncodingTests {
+    @Test(arguments: [
+        ("/plain/page.js", "/plain/page.js"),
+        ("/app/%5Blang%5D/page.js", "/app/%5Blang%5D/page.js"),
+        ("/app/%5blang%5d/page.js", "/app/%5blang%5d/page.js"),
+        ("/app/[lang]/page.js", "/app/%5Blang%5D/page.js"),
+        ("/a b/c.js", "/a%20b/c.js"),
+        ("/caf\u{E9}", "/caf%C3%A9"),
+        ("/100%", "/100%25"),
+        ("/a%zz/b", "/a%25zz/b"),
+        ("/cut%4", "/cut%254"),
+    ])
+    func encodesPathForTheRequest(input: String, expected: String) {
+        #expect(PathPercentEncoding.encode(input) == expected)
+    }
+}
```

`Sources/Engine/Networking/WebURL.swift:208-213`

```diff
         if let questionIdx = path.firstIndex(of: "?") {
-            components.path = String(path[path.startIndex..<questionIdx])
+            components.percentEncodedPath = PathPercentEncoding.encode(String(path[path.startIndex..<questionIdx]))
             components.percentEncodedQuery = String(path[path.index(after: questionIdx)...])
         } else {
-            components.path = path
+            components.percentEncodedPath = PathPercentEncoding.encode(path)
         }
```

Run `swift test --filter "WebURLTests|PathPercentEncodingTests"` → all pass.

Commit:

```
fix: load scripts and images whose address has escaped characters

Next.js pages asked for /app/%5Blang%5D/page.js and got a 404. The
request builder put the path into URLComponents.path, which treats it as
unescaped text and turns every "%" into "%25", so the server saw
%255Blang%255D. Escape the path once with PathPercentEncoding and hand it
to percentEncodedPath, keeping valid %XX escapes and encoding stray "%"
so Foundation does not trap.
```

## Step 3 — failing tests for `self`

`Tests/ToyStackTests/Platform/JSRuntimeTests.swift:17-18` (the work happens in
`runtime.js`, which `JSRuntime` loads, so the tests go in `Platform/`):

```diff
         let result: JSValue? = js.evaluate("window.location === location")
         #expect(result?.toBool() == true)
     }
+
+    @Test func selfAndWindowAreTheGlobalObject() {
+        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let result: JSValue? = js.evaluate("self === window && window === globalThis && window.window === window")
+        #expect(result?.toBool() == true)
+    }
+
+    @Test func propertySetThroughSelfIsSeenByLaterScripts() {
+        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        js.run(script: "bootstrap", code: "(self.__next_f = self.__next_f || []).push([0])")
+        js.run(script: "inline", code: "self.__next_f.push([1, \"chunk\"])")
+        let result: JSValue? = js.evaluate("__next_f.length")
+        #expect(result?.toInt32() == 2)
+    }
+
+    @Test func windowStillReceivesPostedMessages() {
+        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        js.run(script: "listener", code: "var got = null; window.addEventListener('message', function (e) { got = e.data; })")
+        js.dispatchPostMessage(message: "hello")
+        let result: JSValue? = js.evaluate("got")
+        #expect(result?.toString() == "hello")
+    }
+
+    @Test func topWindowHasNoParent() {
+        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
+        let js: JSRuntime = JSRuntime(frame: page.frame)
+        let result: JSValue? = js.evaluate("window.parent === undefined")
+        #expect(result?.toBool() == true)
+    }
 }
```

Run `swift test --filter JSRuntimeTests`. Expected failures (observed):

```
selfAndWindowAreTheGlobalObject:        (result?.toBool() → false) == true
propertySetThroughSelfIsSeenByLaterScripts: (result?.toInt32() → 0) == 2
```

The last two pass today. They protect the `Window.prototype` members that Step 4 moves
onto the global object: message events (used by iframes) and `parent`.

## Step 4 — make the global object the window

`Sources/Engine/Resources/runtime.js:421-430`

```diff
-window = new Window(_getWindowID());
+var window = __globalThis;
+var self = __globalThis;
+window._id = _getWindowID();
 WINDOWS[window._id] = window;
 
-window.console = console;
-window.document = document;
-window.location = location;
-window.Node = Node;
-window.Event = Event;
-window.XMLHttpRequest = XMLHttpRequest;
-window.MessageEvent = MessageEvent;
-
 Object.defineProperty(window, "origin", {
```

`runtime.js:460-471` — after `Window.prototype.parent` is defined, copy the members
onto the global window (they are not defined yet at line 421):

```diff
     return parent;
   },
 });
 
+Object.getOwnPropertyNames(Window.prototype).forEach(function (name) {
+  if (name === "constructor") return;
+  Object.defineProperty(window, name, Object.getOwnPropertyDescriptor(Window.prototype, name));
+});
+
 function MessageEvent(data) {
```

`runtime.js:481-483`

```diff
   _requestAnimationFrame();
 }
 
-window.requestAnimationFrame = requestAnimationFrame;
-
 SET_TIMEOUT_REQUESTS = {};
```

Run `swift test --filter JSRuntimeTests` → pass. Then the whole suite once:
`swift test` (observed in the throwaway copy: **720 tests in 122 suites passed**).

Commit:

```
fix: let Next.js scripts find the window through self

Every Next.js chunk and inline script starts with self.…, and all of
them crashed with "Can't find variable: self". The runtime built window
as a separate object and copied a few globals onto it by hand, so self
never existed and window was not the global object. Point window and
self at the global object and copy the Window.prototype members onto it.
JavaScriptCore does not allow changing the global object's prototype.
```

## Manual check

```
swift run ToyStackHeadless https://palm-co.de/ --frame-limit 3
```

Expect no 404 and no `self` lines. What is left: the 4 `$RC` errors and
`webpack-….js … Can't find variable: TextEncoder`. Both are expected (problem 3 and
hydration). The page will **look the same**. The visible problem is the script and
style text being drawn (see above), not these errors.

## Later (separate plans)

1. **Streamed sections (`$RC` / `$RS`): done.** What landed:
   - `DOMKind.comment(DOMCommentData)`, new file `Sources/Engine/Parsing/DOMCommentData.swift`.
     `DOMTree` gains `createComment`, `isComment`, `comment(_:)`, `setCommentData`,
     `previousSibling(of:)` and `nextSibling(of:)`. `cloneSubtree` and `DOMRef.description`
     handle comments.
   - `HTMLParser` keeps comments as nodes. A comment before any tag is still dropped
     (HTML §13.2.6.4.1-2: it belongs to the Document, which ToyStack does not model).
     A comment with no closing `-->` runs to the end of the input.
   - Layout never sees comments: `LayoutInputsBuilder.renderedChildren` filters them out.
     `LayoutInvalidation.childrenAppend/childrenInsert` ignore a comment child. Without
     that guard, the step-by-step layout path built a box for the comment and no longer
     matched a full layout (caught by `LayoutInvalidationTests`).
   - JS: `parentNode`, `firstChild`, `previousSibling`, `nextSibling`, `nodeType`, `data`
     (get/set for text and comments). `innerHTML`/`outerHTML` print comments.
   - Tests: `HTMLParserTests`, `DOMTreeTests`, `DOMDataTests`, `CommentLayoutTests`,
     `LayoutInvalidationTests`, `NodeTraversalTests`, `StreamedSectionSwapTests`. The last
     one runs palm-co.de's `$RC`/`$RS` scripts copied unchanged.
   - `[hidden]` and `template` were added later with real `display: none` (item 4).
     No `www/` fixture: the test fixtures cover the same shape.
2. **Script and style text drawn in `<body>`: done (fixed by 4).** Cause: ToyStack had no
   `display: none` and hid `head/title/script/style` with a hard-coded tag list. Only the
   block path checked that list (`consumeBlockChildren`). When no child of a parent was
   `display: block` (palm-co.de's Tailwind `flex` divs count as "not block"), the inline
   walks (`collectLeaves`, `appendItems`) drew the script and style text. Smallest repro:
   `<style>…</style><div style="display:flex">x</div><script>…</script>`.
3. **Hydration** (`TextEncoder`, `document.documentElement`, …): not recommended. A
   scratch run with `TextEncoder` added stops at React error #405. Behind it, every
   `parentNode`/`getElementById` call makes a new JS wrapper object, so
   `a.parentNode === b.parentNode` is false, and React keeps its data on node objects.
   Hydration needs one wrapper per node first.
4. **`display: none`: done.**
   - `browser.css` starts with HTML §15.3.1's hidden-elements rule (`area, base, …, script,
     style, template, title`) plus `[hidden] { display: none; }`. The spec's
     `:not([hidden=until-found i]):not(embed)` part is left out: ToyStack has no `:not()`.
   - `LayoutInputs.children` returns only rendered children. `allChildren` keeps the
     `display: none` ones so `blockChildrenInputs` / `inlineContentInputs` still record their
     `display`. Without that, showing a hidden element would never relay out its parent.
     `collectInline` reports the hidden elements its walk skips for the same reason.
   - `LayoutTree.hiddenElements` is gone. `consumeBlockChildren` / `firstVisibleChild` check
     `display == .none` instead, because the incremental append path passes children
     that were not filtered.
   - Tests: `DisplayNoneLayoutTests`.
5. **Cascade origin: done** (needed by 4). `[hidden]` (an attribute selector) beat a page's
   `div { display: block }` because rules were sorted by specificity only.
   `ImportantSelector` became `OriginSelector(base, origin, isImportant)`, and its priority
   follows CSS Cascade 4 §6.1: normal browser < normal author < important author <
   important browser. `CSSParser(_, origin: .userAgent)` builds `defaultStyleSheet`.
   Tests: `CascadeOriginTests`.
6. **Still open:** accessibility and focus walk the DOM, not layout. A `display: none`
   element (for example a `[hidden]` section) can still be read aloud or reached with Tab.
   `head`/`script`/`style` are already skipped there by tag.

## Risks

- `percentEncodedQuery` (`WebURL.swift:210`) has the same crash risk for a query with a
  raw space or `[`. Not reached on palm-co.de, so it stays out of this change.
- `__defineIDs` (`runtime.js:181-186`) writes every element `id` onto the global object.
  With Option B, an element with `id="self"` or `id="window"` replaces those names.
  That was already true for `document`, `location`, etc. before this change.
