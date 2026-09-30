# Browser Resource-Loading Model — Real Browser vs ToyStack

This is a conceptual reference (no source changes). It records how a real browser
decides what blocks what while loading a page, how ToyStack models the same thing, and
the benefits and costs of each.

Naming note: this is *not* "rendering". Rendering is the layout+paint step that produces
pixels (`BrowserTab.render()` at `BrowserTab.swift:500`). This document is about the
loading / blocking model — which resources gate parsing, first paint, and script
execution.

---

## 1. Blocking categories

- **Parser-blocking** — the HTML parser stops fetching/processing the document until the
  resource (or script) completes.
- **Render-blocking** — the first paint is postponed until the resource completes.
- **Script-blocking** — a script may not execute until the resource completes.

---

## 2. Real-world browser model

| Resource | Parser-blocking | Render-blocking | Blocks scripts |
| --- | --- | --- | --- |
| HTML document | (is the parser input) | yes | yes |
| `<link rel=stylesheet>` (CSS) | no | yes | yes — scripts wait for pending CSS |
| `<script src>` (sync, no attrs) | yes | yes | yes — later scripts wait |
| inline `<script>` | yes (runs at that point) | yes | yes — later scripts wait |
| `<script async>` | no | no | no — runs on arrival, order not guaranteed |
| `<script defer>` | no | no | no — runs after parse, in order |
| `<img>` | no | no | no — but triggers reflow when it loads if size was not reserved |

Key property: blocking is **declarative** (tag/attribute semantics) and enforced by a
**streaming parser** that can pause mid-document.

---

## 3. ToyStack model

ToyStack does not stream-parse. `HTMLParser(body: body).parse()` runs to completion first
(`BrowserTab.swift:193-195`), then the load `Task` fetches resources in a fixed order
(`BrowserTab.swift:111-158`):

1. `fetchPage` — HTML bytes (gates everything)
2. `parseHTML` — synchronous, no awaits
3. `fetchStyles` → `applyStyles` — awaited before scripts (`BrowserTab.swift:132-140`)
4. `fetchScripts` — awaits all script bodies (`BrowserTab.swift:142-146`)
5. `fetchImages` → `applyImages` — awaited before scripts *execute*
   (`BrowserTab.swift:148-153`)
6. `execScripts` — runs the fetched scripts, then schedules the frame via
   `setNeedsRender()` (`BrowserTab.swift:155-157`, `:356`)

| Resource | Parser-blocking | Render-blocking | Blocks scripts |
| --- | --- | --- | --- |
| HTML document | gates everything (single `fetchPage` await) | yes | yes |
| stylesheet (`<link>`) | no (already parsed) | yes — `applyStyles` runs before the frame is scheduled | yes — `applyStyles` runs before `execScripts` |
| `<script src>` (sync) | no (already parsed) | yes — `execScripts` calls `setNeedsRender()` | yes — all bodies awaited in `fetchScripts`, then run in index order |
| inline `<script>` | no | yes | yes — run after external scripts, in tree order (`BrowserTab.swift:349-354`) |
| `async` / `defer` | no | no | not distinguished — attributes ignored, behaves like defer |
| `<img>` | no | yes — `applyImages` runs before the frame is scheduled | yes — `execScripts` runs after `applyImages` |

Note: because Step 5 sits between `fetchScripts` (Step 4) and `execScripts` (Step 6),
images now also delay *script execution*. That is a side effect of the simple reorder; a
real browser never lets an image block a script. If you want images render-blocking but
not script-execution-blocking, run `execScripts` before the image fetch and schedule the
frame only afterwards.

Key property: blocking is **imperative** — it is determined by the position of the
`await` in `performLoad`, not by tag semantics.

---

## 4. Where the two diverge

| Aspect | Real browser | ToyStack |
| --- | --- | --- |
| Parsing | streaming; parser can pause for sync scripts/CSS | parse-then-load; parser never pauses |
| Sync `<script>` | parser-blocking | not parser-blocking; runs at end-of-document like `defer` |
| `async` / `defer` | honored | ignored (no distinction) |
| CSS | blocks render and blocks scripts | blocks render and scripts — same observable outcome |
| Images | never block; reflow if unsized | render-blocking, and delays script execution (eager, like styles) |
| What decides blocking | tag semantics + parser state | position of the `await` in `performLoad` |

---

## 5. Benefits and costs

### Real-browser approach

Benefits:
- **Progressive rendering**: paints before the whole document arrives; short
  time-to-first-content on slow/large pages.
- **Speculative parsing / preload scanner**: discovers and warms up subresources while a
  sync script or CSS blocks the parser, hiding latency.
- **Author control and prioritization**: `async`/`defer`/`preload`/priority hints let a
  page tune the critical path.
- **Incremental DOM and reflow**: late/dynamic changes update only what is affected.
- **Correctness on arbitrary real pages** (`document.write`, mid-parse DOM mutation,
  huge documents, etc.).

Costs:
- A **re-entrant parser**, a preload scanner, a resource-priority scheduler, and an
  incremental layout/paint/invalidation engine.
- Ordering becomes timing-dependent and subtle; easy to get wrong.

### ToyStack approach

Benefits:
- **Dead-simple mental model**: one deterministic pipeline, page → styles → scripts →
  images; no re-entrancy, no mid-parse DOM mutation.
- **Scripts always see a complete DOM** (free `defer`-like semantics).
- **Stable layout input**: the tree is frozen before layout, so there are far fewer
  invalidation cases.
- **Easy to debug and teach**: "what blocks what" is answered by reading one function.

Costs:
- **No progressive rendering**: first paint waits for all awaited resources before the
  frame is scheduled.
- **Whole document buffered** and fetched before meaningful work begins.
- **Limited parallelism/priority**: styles fully awaited before scripts; no preload
  scanner.
- **Blocking is implicit in code order**, so it can drift from what tags suggest; and
  `async`/`defer` cannot be expressed.
