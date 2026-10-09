# Note — initial load lag + missing DOM APIs (revisit later)

Status: **deferred / not planned**. Captured after `plans/scroll-long-page-slowdown.md`
landed. Revisit when the load-time freeze or the script crashes become painful.

## Observation

After the scroll fix, scrolling is smooth. Remaining caveat on heavy pages
(e.g. Substack): the browser is **laggy/hung for a while right after load**, then
recovers. Console shows scripts dying on missing browser APIs:

```
6c2ff3e…min.js  TypeError: undefined is not an object (evaluating 'document.scripts.length')
reactMain…js    TypeError: undefined is not an object (evaluating 'document.documentElement.getAttribute')
beacon.min.js   ReferenceError: Can't find variable: crypto
inline          TypeError: undefined is not an object (evaluating 'document.body.prepend')
inline          TypeError: o.getElementsByTagName is not a function
```

## Root cause of the lag

`Frame.load` (`Sources/Engine/Core/Frame.swift:99`) is a single `Task` on the main
actor. `Frame.execScripts` (`Frame.swift:334`) then runs **every downloaded script and
then every inline script synchronously** through JavaScriptCore in one loop:

```swift
for (_, scriptURL, body) in bodies.sorted(by: { $0.index < $1.index }) {
    js.run(script: scriptURL.toString(), code: body)
    loadedScriptURLs.insert(scriptURL.toString())
}
js.defineIDs()
for scriptNode in treeToList(nodes)… { js.run(script: "inline", code: code) }
```

While that loop runs, the main run loop gets no turns: no input is drained, no frame
is presented. That blocking stretch is the "laggy at first" — the same
`install → then` wait described in `scroll-long-page-slowdown.md`, but sustained.

The crashes are **separate**: ToyStack's `runtime.js` (`Sources/Engine/Resources/runtime.js`)
simply does not implement those globals.

## Two independent fixes

### Option 1 — add the missing DOM APIs
Implement, in `runtime.js` + `JSRuntime.swift` bindings:

- `document.scripts` (a list/collection with `.length`)
- `document.documentElement` and `document.body`
- global `crypto` (at least the property access the beacon touches)
- `Element.prototype.getElementsByTagName`
- `Node.prototype.prepend`

Trade-off: cheap and self-contained, but note it can make the lag **worse** — today those
scripts die early and stop; implement the APIs and more page JS actually runs.

### Option 2 — cooperative script execution (stopgap, NOT long-term)
Schedule each top-level script as its own low-priority `BrowserTask` on the tab's
`TaskRunner` (`Sources/Engine/Scheduling/TaskRunner.swift:11`) instead of one loop.
`TaskRunner.runNext` runs one task per main-queue turn, so the run loop gets a turn
between scripts.

Benefits: UI stays responsive during load; progressive paint; reuses existing infra.

Why it is not the long-term design:

- Only yields **between** scripts; one big bundle (`reactMain…js`) still blocks its
  whole duration. Real browsers share this limit (JS can't be preempted mid-script),
  which is why chunking is a mitigation, not a fix.
- Changes execution semantics: timers/rAF/input/DOM events can interleave between
  scripts. Adds reentrancy without owning the event loop.
- `loaded = true` becomes asynchronous — anything assuming a synchronous load
  (including tests) needs review.
- Leptop / structural gap remains: in ToyStack the app UI thread **is** the engine JS
  thread, so long JS freezes the window.

## Long-term direction (when revisited)

1. **Make the bindings efficient first** — highest value, no threading required.
   Every DOM query walks the whole tree today:
   - `_getIDs` (`JSRuntime.swift:86`) rebuilds a full-tree id map on **every**
     `getElementById`.
   - `_querySelectorAll` (`JSRuntime.swift:73`) does a full `treeToList` + filter per call.
   A React page hammers these, so much of the "JS execution" seconds is probably our
   bridge, not JSC.
2. **Own the event loop** — explicit macro/microtask queue, timers, rAF, rendering
   steps, via `TaskRunner`.
3. **Separate the renderer thread from the UI thread** — the real long-term fix, so a
   long script can never freeze the window. Requires the `JSRuntime` callbacks
   (`MainActor.assumeIsolated` throughout) to stop touching `Frame`/`Element` directly.

## Recommendation

Defer. When revisited: do step 1 (binding efficiency) first — it likely removes most of
the lag and is a prerequisite for a sane renderer thread. Option 1 can be done any time
in parallel; option 2 only as an interim if the freeze is painful.
