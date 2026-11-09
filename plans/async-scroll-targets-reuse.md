# Pakai ulang daftar target scroll saat layout latar dipasang

Tanggal: 2026-11-09
Dasar: `browser.trace` (GUI, `layout.html`, 482 blok, 932 resize) dan kode di
`Sources/Engine/Core/Frame.swift`.

## Masalah

Daftar target scroll adalah iframe dan block `overflow: scroll` yang bisa
menerima scroll sendiri. Dua jalan pemasangan layout memperlakukannya berbeda:

| Jalan | Kode | Perilaku |
|---|---|---|
| Layout sinkron (`render`) | `Frame.swift:1040-1062` | Menelusuri seluruh tree hanya kalau tree baru, struktur berubah, atau node target dibuang. Kalau tidak, hanya posisi target yang diperbarui (`refreshScrollTargetRects`). |
| Layout latar (GUI) | `Frame.swift:1443-1447` | **Selalu** menelusuri seluruh tree (`rebuildScrollTargets` → `treeToList`), juga saat drag yang hanya mengubah lebar. |

Baris di jalan latar itu masuk di commit `fe876e2` ("lay out pages off the
main thread"). Pesan commit tidak menjelaskan kenapa harus selalu menelusuri.
Dugaan saya, ini pilihan aman: tanda `needsRebuild` bisa diubah main thread
saat job sedang berjalan, dan tanda boolean tidak bisa membedakan "berubah
sebelum job mulai" dari "berubah saat job berjalan". Desain di bawah menutup
masalah itu.

Akibatnya sekarang:

- Setiap pemasangan, main thread menelusuri semua node. Di `embeds.html`
  ±0,65 ms per pemasangan (`plans/issues/layout-visit-cost.md:493-495`). Di
  trace ini seluruh `layout.async.finish` median 0,20 ms (p95 0,33). Trace
  tidak punya span untuk penelusuran itu sendiri.
- Jalan latar tidak punya counter, jadi `scrollTargets.*` tidak pernah muncul
  di trace GUI (0 dari 115.526 event). `profiler.count` juga tidak bisa
  dipakai di sini: setelah pemasangan, `continueAfterInstall` menjalankan
  paint, dan window paint mengosongkan hitungan main thread
  (`Frame.swift:1110`).

Manfaatnya kecil (paling banyak ~0,65 ms main thread per pemasangan di halaman
panjang) tapi pasti.

## File yang berubah

| File | Alasan |
|---|---|
| `Tests/ToyStackTests/AsyncResizeRestartTests.swift` | 3 tes baru lewat jalan latar. `makeAsyncPage` menerima `html`/`rules`. |
| `Sources/Engine/Core/ScrollTargetState.swift` | `isValid` + `needsRebuild` diganti `revision` + `builtRevision`. |
| `Sources/Engine/Core/LayoutJobKey.swift` | Mencatat `targetsRevision` saat job dimulai. |
| `Tests/ToyStackTests/LayoutJobKeyTests.swift` | Init `LayoutJobKey` mendapat argumen baru. |
| `Sources/Engine/Core/Frame.swift` | Helper `updateScrollTargets` dipakai kedua jalan. Jalan latar mendapat counter. |
| `profiling.md` | Counter baru; `scrollTargets.*` hanya untuk layout sinkron. |
| `plans/issues/layout-visit-cost.md` | Bagian yang sudah tidak cocok dengan kode. |

## Keputusan desain

### 1. Cara mencatat di jalan latar

- **Opsi A (disarankan):**
  `browser?.measure.counter("layout.async.scrollTargets", ["rebuilt": 0/1])`.
  Polanya sama dengan `layout.async.superseded` (`Frame.swift:1433`). Counter
  ini langsung masuk ke trace, jadi bisa dibaca di GUI dan di tes.
- **Opsi B:** `profiler.count("scrollTargets.rebuilt")`. Hitungannya
  dikosongkan oleh window paint sebelum sempat ditulis, jadi tidak pernah
  sampai ke trace.

### 2. Perubahan struktur saat job masih berjalan

Tree milik job dibuat sebelum perubahan itu. Pemasangan job ini tidak boleh
menganggap daftar target sudah "terbaru". Kalau tidak, job berikutnya (yang
memuat perubahan) akan memakai ulang daftar tanpa target baru.

- **Opsi A (disarankan): nomor revisi.** Setiap kejadian yang bisa mengubah
  daftar menaikkan `revision` (`&+=`; nomor ini hanya dibandingkan sama atau
  tidak). Job mencatat `revision` saat mulai. Setelah daftar dibangun dari tree
  job, `builtRevision` diisi revisi **milik job**. Perubahan saat job berjalan
  otomatis tetap tertunda, termasuk kalau job dibatalkan.
- **Opsi B: pakai `layoutInFlightDirty`.** Tidak cukup. Edit DOM dari JS saat
  job berjalan hanya menandai tree yang terpasang
  (`LayoutInvalidation.swift:6-9`, `blockMarkChildrenDirty`), bukan
  `markDocumentDirty`. Kalau job selesai sebelum tick berikutnya menjalankan
  style, `layoutInFlightDirty` masih salah dan perubahan struktur hilang.

`ScrollTargetState` tetap 4 field (`iframes`, `blocks`, `revision`,
`builtRevision`), karena `isValid` dan `needsRebuild` selalu dibaca bersama
(`needsRebuild || !isValid`). Keduanya digabung menjadi satu revisi.

## Langkah

Setiap langkah tetap bisa di-build.

### Langkah 1 — tes (gagal dulu)

Ketiga tes melewati `startAsyncLayout` → `finishAsyncLayout`. Tes di
`LayoutInvalidationTests.swift:104-148` hanya menguji jalan sinkron.

`Tests/ToyStackTests/AsyncResizeRestartTests.swift`, bagian helper
(`:163-181`):

```diff
     // MARK: - Helpers
 
     private static let paragraphs: String = (0..<40).map { index in
         "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
     }.joined()
+
+    private static let blockRules: String = "body { display: block; } p { display: block; }"
+
+    /// A `div` is a scroll target whose width follows the viewport.
+    private static let scrollRules: String = blockRules
+        + " section { display: block; }"
+        + " div { display: block; height: 20px; overflow: scroll; }"
 
     /// The tab keeps a weak reference to the browser; the caller holds it.
-    private static func makeAsyncPage(tracePath: String? = nil) -> (LayoutTestPage, Browser) {
-        let page: LayoutTestPage = LayoutTestPage(
-            html: paragraphs,
-            rules: "body { display: block; } p { display: block; }"
-        )
+    private static func makeAsyncPage(
+        html: String = paragraphs,
+        rules: String = blockRules,
+        tracePath: String? = nil
+    ) -> (LayoutTestPage, Browser) {
+        let page: LayoutTestPage = LayoutTestPage(html: html, rules: rules)
         let browser: Browser = Browser(tracePath: tracePath)
```

Helper pembaca counter, di bawah `traceEvents` (`:191-197`):

```diff
         return try #require(root["traceEvents"] as? [[String: Any]])
     }
+
+    /// `rebuilt` of every `layout.async.scrollTargets` sample, in order.
+    private static func scrollTargetSamples(_ path: String) throws -> [Int] {
+        return try traceEvents(path)
+            .filter({ $0["name"] as? String == "layout.async.scrollTargets" })
+            .compactMap({ ($0["args"] as? [String: Any])?["rebuilt"] as? Int })
+    }
+
+    /// The only scroll block target, checked against the installed tree.
+    private static func onlyScrollBlock(_ page: LayoutTestPage) throws -> ScrollBlockTarget {
+        let tree: LayoutTree = try #require(page.frame.document)
+        let blocks: [ScrollBlockTarget] = page.frame.state.layout.targets.blocks
+        #expect(blocks.count == 1, "expected one scroll block target, got \(blocks.count)")
+        let target: ScrollBlockTarget = try #require(blocks.first)
+        #expect(target.rect == tree.selfRect(target.layout), "the target rect is stale")
+        return target
+    }
 }
```

Tiga tes, sebelum `// MARK: - Helpers` (`:163`):

```diff
+    /// A pass that only changes the width keeps the same scroll targets.
+    /// Installing it refreshes their rects instead of walking the whole tree,
+    /// and the refreshed rects follow the new layout.
+    @Test(
+        .enabled(
+            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
+        )
+    )
+    func widthOnlyInstallReusesScrollTargets() async throws {
+        let path: String = NSTemporaryDirectory() + "scroll-reuse-\(UUID().uuidString).trace"
+        defer { try? FileManager.default.removeItem(atPath: path) }
+        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
+            html: "<div></div>" + Self.paragraphs,
+            rules: Self.scrollRules,
+            tracePath: path
+        )
+        var widths: [CGFloat] = []
+        for width in [400, 300] {
+            page.tab.resize(width: CGFloat(width), height: 600)
+            page.frame.runAnimationFrame()
+            try await Self.settle(page)
+            let target: ScrollBlockTarget = try Self.onlyScrollBlock(page)
+            widths.append(target.rect.right - target.rect.left)
+        }
+        #expect(widths[0] > widths[1], "the scroll box rect did not follow the viewport: \(widths)")
+
+        browser.measure.close()
+        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
+        try #require(rebuilt.count == 2, "expected one sample per install, got \(rebuilt)")
+        #expect(rebuilt == [0, 0], "a width-only install walked the whole tree: \(rebuilt)")
+    }
+
+    /// A scroll box added while a pass runs is not in that pass's tree. That
+    /// install must leave the change pending, so the pass that lays the box
+    /// out walks the tree and finds it.
+    @Test(
+        .enabled(
+            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
+        )
+    )
+    func scrollBoxAddedDuringAPassBecomesATarget() async throws {
+        let path: String = NSTemporaryDirectory() + "scroll-added-\(UUID().uuidString).trace"
+        defer { try? FileManager.default.removeItem(atPath: path) }
+        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
+            html: #"<section id="box"></section>"# + Self.paragraphs,
+            rules: Self.scrollRules,
+            tracePath: path
+        )
+        page.tab.resize(width: 400, height: 600)
+        page.frame.runAnimationFrame()
+        #expect(page.frame.isLayoutInFlight)
+        page.frame.js.run(
+            script: "appendChild",
+            code: "document.getElementById('box').appendChild(document.createElement('div'));"
+        )
+        // The running pass is installed before style sees the new node.
+        try await Self.settle(page)
+        page.tab.runAnimationFrame()
+        try await Self.settle(page)
+
+        _ = try Self.onlyScrollBlock(page)
+        browser.measure.close()
+        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
+        #expect(rebuilt.last == 1, "the pass with the new box reused the old list: \(rebuilt)")
+    }
+
+    /// A removed scroll box must leave the target list.
+    @Test(
+        .enabled(
+            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
+        )
+    )
+    func removedScrollBoxLeavesTheTargets() async throws {
+        let path: String = NSTemporaryDirectory() + "scroll-removed-\(UUID().uuidString).trace"
+        defer { try? FileManager.default.removeItem(atPath: path) }
+        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
+            html: #"<section id="box"><div></div></section>"# + Self.paragraphs,
+            rules: Self.scrollRules,
+            tracePath: path
+        )
+        page.tab.resize(width: 400, height: 600)
+        page.frame.runAnimationFrame()
+        try await Self.settle(page)
+        _ = try Self.onlyScrollBlock(page)
+
+        page.frame.js.run(
+            script: "removeChild",
+            code: """
+                var box = document.getElementById('box');
+                box.removeChild(box.children[0]);
+            """
+        )
+        page.tab.runAnimationFrame()
+        try await Self.settle(page)
+
+        let blocks: [ScrollBlockTarget] = page.frame.state.layout.targets.blocks
+        #expect(blocks.isEmpty, "a removed scroll box is still a target")
+        browser.measure.close()
+        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
+        #expect(rebuilt.last == 1, "the install after the removal reused the old list: \(rebuilt)")
+    }
+
     // MARK: - Helpers
```

Jalankan:

```sh
TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel --filter AsyncResizeRestartTests
```

Hasil yang diharapkan sebelum perubahan:

- Ketiga tes **gagal** di `#require` / `rebuilt.last`, karena counter belum
  ada (`rebuilt == []`).
- Pemeriksaan perilaku (posisi target sama dengan tree, target baru ditemukan,
  target yang dibuang hilang) **lulus**, karena kode sekarang selalu
  menelusuri ulang.

Kalau pemeriksaan perilaku di `scrollBoxAddedDuringAPassBecomesATarget` sudah
gagal di sini (misalnya `div` tidak punya node layout sama sekali), berhenti.
Itu bug lain: edit DOM saat job berjalan hilang dari layout. Bug ini perlu
ditangani sendiri dulu.

Catatan tentang cabang "node target dibuang" (`removed`): setiap cara membuang
node target dari halaman juga menaikkan revisi. Edit DOM lewat
`markStructureChanged` (`JSRuntime.swift:264-396`), perubahan `display` atau
`overflow` lewat `Frame.swift:897-901`. Jadi `removedScrollBoxLeavesTheTargets`
menguji perilakunya (target hilang, tree ditelusuri ulang), tapi tidak bisa
memisahkan cabang `removed` dari kenaikan revisi. Cabang itu jaring kedua,
sama seperti di jalan sinkron sekarang.

### Langkah 2 — counter di jalan latar (tes gagal karena alasan yang benar)

`Sources/Engine/Core/Frame.swift:1443-1447`:

```diff
         state.layout.targets.isValid = false
         state.layout.targets.needsRebuild = true
         rebuildScrollTargets(box.tree)
         state.layout.targets.isValid = true
         state.layout.targets.needsRebuild = false
+        browser?.measure.counter("layout.async.scrollTargets", ["rebuilt": 1])
         tab?.needsAccessibility = true
```

Sekarang hanya `widthOnlyInstallReusesScrollTargets` yang gagal, dengan
`rebuilt == [1, 1]`: setiap pemasangan menelusuri seluruh tree. Ini masalah
yang mau dibuktikan. Dua tes lain lulus.

### Langkah 3a — revisi menggantikan dua tanda (perilaku sama)

`Sources/Engine/Core/ScrollTargetState.swift:3-16`:

```diff
 /// Cached hit regions for iframes and independently scrollable blocks.
 struct ScrollTargetState {
     var iframes: [IframeTarget]
     var blocks: [ScrollBlockTarget]
-    var isValid: Bool
-    var needsRebuild: Bool
+    /// Bumped whenever the lists may be wrong: a new tree, a structure change,
+    /// or a change to display or overflow. Only compared for equality.
+    private(set) var revision: UInt64
+    /// The `revision` the lists were last built for.
+    var builtRevision: UInt64
 
     init() {
         self.iframes = []
         self.blocks = []
-        self.isValid = false
-        self.needsRebuild = false
+        self.revision = 1
+        self.builtRevision = 0
+    }
+
+    mutating func invalidate() {
+        revision &+= 1
+    }
+
+    /// Drops every target. The revision keeps counting up, so a pass recorded
+    /// before the clear can never look current.
+    mutating func clear() {
+        iframes = []
+        blocks = []
+        invalidate()
     }
 }
```

`Sources/Engine/Core/Frame.swift`:

```diff
@@ Frame.swift:63 (replaceDOM)
-        state.layout.targets = ScrollTargetState()
+        state.layout.targets.clear()
@@ Frame.swift:177-179
     func markStructureChanged() {
-        state.layout.targets.needsRebuild = true
+        state.layout.targets.invalidate()
     }
@@ Frame.swift:1001
-                    state.layout.targets.isValid = false
+                    state.layout.targets.invalidate()
@@ Frame.swift:1040-1045
-            if state.layout.targets.iframes.contains(where: { removed.contains($0.layout) })
-                || state.layout.targets.blocks.contains(where: { removed.contains($0.layout) })
-            {
-                state.layout.targets.isValid = false
-                state.layout.targets.needsRebuild = true
-            }
             state.layout.tree.isDirty = false
@@ Frame.swift:1053-1063
             browser?.measure.start("BrowserTab.rebuildScrollTargets")
-            if state.layout.targets.needsRebuild || !state.layout.targets.isValid {
-                rebuildScrollTargets(box.tree)
-                state.layout.targets.isValid = true
-                state.layout.targets.needsRebuild = false
-                profiler.count("scrollTargets.rebuilt")
-            } else {
-                refreshScrollTargetRects()
-                profiler.count("scrollTargets.reused")
-            }
+            let revision: UInt64 = state.layout.targets.revision
+            if updateScrollTargets(box.tree, removed: removed, revision: revision) {
+                profiler.count("scrollTargets.rebuilt")
+            } else {
+                profiler.count("scrollTargets.reused")
+            }
             browser?.measure.stop("BrowserTab.rebuildScrollTargets")
@@ Frame.swift:1343
-            state.layout.targets.isValid = false
+            state.layout.targets.invalidate()
@@ Frame.swift:1443-1448 (behavior unchanged in this step: always rebuild)
-        state.layout.targets.isValid = false
-        state.layout.targets.needsRebuild = true
         rebuildScrollTargets(box.tree)
-        state.layout.targets.isValid = true
-        state.layout.targets.needsRebuild = false
+        state.layout.targets.builtRevision = state.layout.targets.revision
         browser?.measure.counter("layout.async.scrollTargets", ["rebuilt": 1])
```

Helper baru di bawah `rebuildScrollTargets` (`Frame.swift:1560`):

```diff
         state.layout.targets.iframes = iframes
         state.layout.targets.blocks = blocks
     }
+
+    /// Walks the tree for scroll targets when the lists were built for another
+    /// `revision` or the pass removed a target's node; otherwise refreshes the
+    /// rects of the known targets. `revision` is the one the tree was laid out
+    /// for: the current one for a synchronous pass, the one recorded at job
+    /// start for a background pass, so a change made while the job ran stays
+    /// pending. Returns true when the tree was walked.
+    private func updateScrollTargets(
+        _ doc: LayoutTree,
+        removed: Set<LayoutID>,
+        revision: UInt64
+    ) -> Bool {
+        let lostTarget: Bool =
+            state.layout.targets.iframes.contains(where: { removed.contains($0.layout) })
+            || state.layout.targets.blocks.contains(where: { removed.contains($0.layout) })
+        guard lostTarget || state.layout.targets.builtRevision != revision else {
+            refreshScrollTargetRects()
+            return false
+        }
+        rebuildScrollTargets(doc)
+        state.layout.targets.builtRevision = revision
+        return true
+    }
```

Cek: `swift test --filter LayoutInvalidationTests` lulus (tiga tes
`scrollTargets.*` menjaga jalan sinkron). Tes async sama seperti di langkah 2.

### Langkah 3b — jalan latar memakai aturan yang sama

`Sources/Engine/Core/LayoutJobKey.swift:4-7`:

```diff
-/// The viewport a background layout was started for.
+/// What a background layout was started for: the viewport, and the scroll
+/// target revision its tree reflects.
 struct LayoutJobKey: Equatable, Sendable {
     let size: CGSize
     let zoom: CGFloat
+    let targetsRevision: UInt64
```

`Tests/ToyStackTests/LayoutJobKeyTests.swift:8-11`:

```diff
     private static let key: LayoutJobKey = LayoutJobKey(
         size: CGSize(width: 800, height: 600),
-        zoom: 1
+        zoom: 1,
+        targetsRevision: 1
     )
```

`Sources/Engine/Core/Frame.swift:1366-1369`. Ini dicatat setelah langkah tree
(`:1338-1344`), jadi tree baru sudah menaikkan revisi:

```diff
         layoutJobKey = LayoutJobKey(
             size: CGSize(width: width, height: frameHeight),
-            zoom: pageZoom
+            zoom: pageZoom,
+            targetsRevision: state.layout.targets.revision
         )
```

`Sources/Engine/Core/Frame.swift:1443-1446` (setelah langkah 3a):

```diff
-        rebuildScrollTargets(box.tree)
-        state.layout.targets.builtRevision = state.layout.targets.revision
-        browser?.measure.counter("layout.async.scrollTargets", ["rebuilt": 1])
+        let rebuilt: Bool = updateScrollTargets(
+            box.tree,
+            removed: removed,
+            revision: job.targetsRevision
+        )
+        browser?.measure.counter("layout.async.scrollTargets", ["rebuilt": rebuilt ? 1 : 0])
         tab?.needsAccessibility = true
```

Cek: ketiga tes async lulus.

### Langkah 4 — buktikan tes menangkap kesalahan yang paling mungkin

Kesalahan yang paling mungkin: memakai revisi sekarang, bukan revisi job.
Untuk sementara, ganti `revision: job.targetsRevision` di langkah 3b dengan
`revision: state.layout.targets.revision`. `scrollBoxAddedDuringAPassBecomesATarget`
harus gagal (`blocks.count == 0`): pemasangan job pertama membangun daftar dari
tree tanpa `div` lalu menandainya terbaru, sehingga job kedua memakai ulang
daftar kosong. Kembalikan setelah terbukti.

### Langkah 5 — jalankan tes

```sh
TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel --filter AsyncResizeRestartTests
swift test --filter "LayoutInvalidationTests|LayoutJobKeyTests"
swift test
```

### Langkah 6 — dokumen

`profiling.md:233`:

```diff
-| `profile.layout` | `Frame.render`, layout block (`Frame.swift:817-856`); with async layout (the GUI), the background job in `Frame.startAsyncLayout` instead | `layout.*`, `text.*`; the main-thread window also has `scrollTargets.reused`, `scrollTargets.rebuilt` |
+| `profile.layout` | `Frame.render`, layout block (`Frame.swift:817-856`); with async layout (the GUI), the background job in `Frame.startAsyncLayout` instead | `layout.*`, `text.*`; the synchronous (main-thread) window also has `scrollTargets.reused`, `scrollTargets.rebuilt`. The async install reports `layout.async.scrollTargets` instead |
```

`profiling.md:329-330`:

```diff
-| `scrollTargets.rebuilt` | count | layout pass that rescanned the tree for scrollable blocks and iframes |
-| `scrollTargets.reused` | count | layout pass that reused the target list and only refreshed rects |
+| `scrollTargets.rebuilt` | count | synchronous layout pass that rescanned the tree for scrollable blocks and iframes |
+| `scrollTargets.reused` | count | synchronous layout pass that reused the target list and only refreshed rects |
```

`profiling.md`, setelah paragraf `layout.async.superseded` (`:414-417`):

```diff
 finished pass used. During a drag, expect roughly one sample per pass.
+
+`layout.async.scrollTargets` (`rebuilt`): one sample per installed background
+layout. `rebuilt` = 1 when the install walked the whole tree for scroll targets
+(new tree, structure or display/overflow change before the pass started, or a
+target's node removed); 0 when it only refreshed the rects of the known
+targets. A change made while the pass ran is picked up by the next pass.
+During a width-only drag, expect 0.
```

`plans/issues/layout-visit-cost.md:4-6`:

```diff
-Dasar: pengukuran di `plans/issues/resize-flow-roadmap.md` ("Layout cost
-measured") dan satu CPU sample. Dokumen ini hanya usulan; belum ada perubahan
-kode.
+Dasar: pengukuran di `plans/issues/resize-flow-roadmap.md` ("Layout cost
+measured") dan satu CPU sample. Opsi A, Opsi B, dan langkah-langkah di bawahnya
+sudah diterapkan; nomor baris di bagian "Temuan" merujuk ke kode sebelum Opsi A.
```

`plans/issues/layout-visit-cost.md:147`:

```diff
-`inlineTextLinePlan` (`BlockLayoutPass.swift:383`) dihitung ulang untuk setiap
+`inlineTextLinePlan` (sekarang `BlockLayoutPass.swift:129`) dihitung ulang untuk setiap
```

`plans/issues/layout-visit-cost.md:486`. Baris ini membalik nama lama dan
nama baru; kode memakai `LayoutTreeHandoff`
(`Sources/Engine/Core/LayoutTreeHandoff.swift:9`):

```diff
-`LayoutTreeHandoff` (nama baru `LayoutJobHandoff`, karena dipakai untuk dua arah)
+`LayoutTreeHandoff` (nama lama `LayoutJobHandoff`; diganti karena dipakai untuk dua arah)
```

`plans/issues/layout-visit-cost.md:493-495`:

```diff
 Sisa finish di main thread hampir semuanya `rebuildScrollTargets` (±0,65 ms):
 menelusuri seluruh tree untuk daftar target scroll setiap install. Bisa dihitung
 di job latar.
+
+Diperbaiki di `plans/async-scroll-targets-reuse.md`: pemasangan latar memakai
+aturan yang sama dengan layout sinkron, jadi drag yang hanya mengubah lebar
+tidak lagi menelusuri seluruh tree.
```

## Bukti di GUI setelah perubahan

Rekam satu `browser.trace` drag di `embeds.html` (build release), lalu cek:

- `layout.async.scrollTargets` `rebuilt` = 0 di hampir semua pemasangan selama
  drag;
- `layout.async.finish` median turun (sebelumnya ±0,76–0,80 ms di halaman
  itu, `layout-visit-cost.md:490`).

## Usulan commit

Satu ide per commit, jadi langkah 3a dan 3b sebaiknya dua commit.

```
refactor: track when the scroll target list goes stale with a revision

The list of scroll boxes and iframes had two flags, isValid and
needsRebuild, that were always read together and could not tell a change
made before a background layout started from one made while it ran.
Replace them with a revision that every structure change bumps and the
revision the list was built for. No behavior changes.
```

```
perf: stop rescanning the page for scroll boxes on every resize step

Every background layout install walked the whole layout tree on the main
thread to find iframes and overflow:scroll blocks, even when a drag only
changed the width. The synchronous path already skipped that walk.

The background job now records the scroll target revision it started
from, and its install walks the tree only when the list is older than
that revision or a target's node was removed. A change made while the job
ran stays pending for the next pass. The install reports
layout.async.scrollTargets.
```

## Sudah dikerjakan (2026-11-09)

Kode mengikuti langkah 1–6 di atas. Ada tiga hal yang berbeda dari rencana.

1. **Tes kedua diganti.** `scrollBoxAddedDuringAPassBecomesATarget` (DOM
   ditambah saat job berjalan) gagal **sebelum perubahan apa pun**. Penyebabnya
   `div` yang ditambah tidak pernah mendapat node layout
   (`div.ref.layoutID == nil`). Kontrolnya, yaitu penambahan yang sama setelah
   job selesai, berhasil (`LayoutID(raw: 164)`). Ini bug terpisah: edit DOM
   saat layout latar berjalan hilang dari layout. Dugaan saya,
   `LayoutInvalidation.childrenChanged` (`LayoutInvalidation.swift:6-9`)
   menandai tree yang sedang terpasang, lalu tree itu diganti tree job saat
   pemasangan. Bug ini sudah diperbaiki di `plans/async-dom-edit-lost.md`
   (tes `AsyncResizeRestartTests.domEditDuringAPassReachesTheLayout`).
   Penggantinya `boxMadeScrollableDuringAPassBecomesATarget`: `overflow`
   diubah menjadi `scroll` saat job berjalan. Tes ini menguji hal yang sama,
   yaitu revisi naik setelah job mencatat revisinya, dan target tetap muncul
   setelah pass berikutnya. `display: none` tidak bisa dipakai, karena block
   dengan `display: none` tetap mendapat node layout.
2. **`page.tab.runAnimationFrame()` diganti `page.frame.runAnimationFrame()`.**
   `BrowserTab.runAnimationFrame` melewati frame yang `loaded` = false
   (`BrowserTab.swift:205`), dan `LayoutTestPage` tidak pernah memuat lewat
   jaringan, jadi panggilan lewat tab tidak menjalankan apa-apa. Tes lama
   `contentChangeDuringAPassHoldsPaintBack` (`AsyncResizeRestartTests.swift:89`)
   memakai pola ini dan mungkin lulus tanpa menguji apa pun. Belum diubah.
3. **Uji mutasi (langkah 4)** memakai revisi sekarang, bukan revisi job, di
   pemasangan latar. Hasilnya, `boxMadeScrollableDuringAPassBecomesATarget`
   gagal di `rebuilt.last` (0, bukan 1). Pemeriksaan perilakunya tetap lulus,
   karena `rebuildScrollTargets` membaca `overflow` langsung dari DOM. Jadi
   kesalahan itu hanya tertangkap lewat counter. Tes yang menangkapnya lewat
   perilaku butuh perubahan struktur saat job berjalan, dan itu terhalang bug
   di poin 1.

Hasil tes:

| Langkah | Hasil |
|---|---|
| 1 (tes saja) | 3 tes baru gagal hanya di counter (`rebuilt.count → 0`, `rebuilt.last → nil`); pemeriksaan perilaku lulus |
| 2 (counter = 1) | Hanya `widthOnlyInstallReusesScrollTargets` gagal: `[1, 1] == [0, 0]` |
| 3a (revisi, perilaku sama) | `LayoutInvalidationTests` 12 lulus; tes async sama dengan langkah 2 |
| 3b | `AsyncResizeRestartTests` + `LayoutJobKeyTests` 12 lulus |
| 5 | `swift test` 347 tes / 67 suite lulus; `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` 347 lulus |

Belum: trace GUI `embeds.html` untuk mengukur `layout.async.finish` dan
`layout.async.scrollTargets` selama drag.

## Bukan bagian dari perbaikan ini: jeda dari resize sampai layout mulai

Perlu diukur dulu; belum jadi usulan. Jeda median 10,7 ms memang disengaja:

1. `BrowserTab.resize` (`BrowserTab.swift:255-275`) memanggil
   `setNeedsViewportResize`.
2. `setNeedsViewportResize` (`Frame.swift:2176-2177`) memanggil
   `setNeedsLayout`.
3. `setNeedsLayout` meminta frame berikutnya lewat `requestAnimationFrame`
   (`Frame.swift:2164`, `:215-217`).
4. Layout baru dimulai di `Browser.animationTick` (`Browser.swift:255-290`).

Menunggu paling lama satu frame membuat beberapa resize digabung menjadi satu
layout. Memulai layout lebih awal hanya berguna kalau gambar dengan lebar itu
tampil satu frame lebih cepat. Ukurannya: resize → present pertama dengan
`preview` = 0 dan `viewWidth` = lebar itu. Di trace ini, setelah tangan
berhenti (15 kali), angkanya median 52,2 ms (p10–p90: 29,6–63,4 ms). Jeda
11,3 ms sebelum layout ada di dalam angka itu.
