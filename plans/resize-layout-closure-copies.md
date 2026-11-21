# Resize: layout menyalin seluruh pohon layout di setiap blok kode profiler

Prioritas 1 dari analisa `browser.trace` (14-11, 09:13): frame yang lambat karena layout.

Data:
- `browser.trace` (GUI, build `38f55bc`, drag resize 19,6 detik, sekitar 1.060 frame).
- `ToyStackHeadless` (release) di `https://browser.engineering/reflow.html`: 1440×900, 382 resize dengan langkah 6 px per tick (1440 → 300 → 1440).
- Profil CPU dengan `sample` (macOS) selama resize di headless yang sama.

Tidak ada kode di repo yang diubah. Diff di §4 diterapkan **apa adanya** (teks diff dari dokumen ini, dicocokkan persis ke file) di salinan sementara (`/tmp/ts-plan`, hasil `rsync` dari `38f55bc`), langkah demi langkah. Hasilnya ada di §3.

## 1. Ringkasan

| | Angka | Sumber |
|---|---:|---|
| Frame lambat karena mesin, penyebab utamanya layout | 21 dari 34 | kelebihan per tahap dibanding median frame normal |
| … yang terjadi saat window melewati lebar 800 px | 6 | `layout.inputs.decision viewportStyle = 1` |
| … karena banyak baris teks dipotong ulang | 15 | `layout.inline.place.rebuiltLines` 485 vs 131 |
| Frame dengan layout + paint > 16,67 ms | 242 dari 1.015 | `layout.async.document`, `BrowserTab.paint` |
| Waktu layout yang habis untuk **menyalin dan membuang pohon layout** | **16,8 %** | `sample`: `outlined init with copy of LayoutTree` + `outlined destroy of LayoutTree` |
| Layout per resize, headless, sebelum → sesudah perbaikan | median **8,3 → 7,1 ms**, p90 **12,1 → 10,9 ms** | `BrowserTab.layout`, 3 kali jalan, `--no-profile` |

Satu penyebab yang bisa diperbaiki tanpa mengubah cara layout menghitung: **blok kode `{ … }` yang dikirim ke `profiler.measure` membuat Swift menyalin seluruh `LayoutTree` setiap kali kode di dalamnya membaca dari pohon.** Rencana ini menghapus salinan itu dari jalur yang dijalankan untuk setiap blok dan setiap baris.

## 2. Analisa

### 2.1 Frame lambat karena layout

Dari 21 frame yang penyebab utamanya layout:

| Kelompok | Jumlah | Layout | Ciri |
|---|---:|---|---|
| Lewat lebar 800 px | 6 | 27,5–29,8 ms | Ditambah `BrowserTab.style` 8,4–9,2 ms di main thread |
| Banyak baris dipotong ulang | 15 | 11,3–23,7 ms | Lebar sempit (304–653 px) atau langkah lebar besar |

Layout yang lambat (> 14 ms) dibanding yang normal (< 10 ms), median:

| Metrik | Normal | Lambat |
|---|---:|---:|
| `layout.lines.total.count` | 140 | 910 |
| `layout.inline.place.us` | 1.000 | 5.254 |
| `layout.visit.us` | 4.467 | 9.621 |
| `layout.line.children.previous.us` | 304 | 1.998 |
| `layout.visited.count` | 1.587 | 1.587 |

Semua 1.587 blok dikunjungi di setiap layout, karena lebar semua blok berubah (`layout.width.changed.count` = 1.583). Biaya yang naik adalah biaya per baris.

### 2.2 Profil CPU

`sample` selama resize di headless (HEAD, `--no-profile`). Persentase dari waktu di dalam `LayoutTree.layoutDocument`:

| Fungsi | % |
|---|---:|
| `layoutLine` | 32,6 |
| `markDependents` | 18,8 |
| `placeInlineItems` | 15,6 |
| `__RawDictionaryStorage.find` (cari di dictionary) | 13,4 |
| **`outlined init with copy of LayoutTree`** | **9,5** |
| **`outlined destroy of LayoutTree`** | **7,4** |
| `DependencyIndex.replaceDependent` | 4,2 |

Yang memanggil salinan `LayoutTree`:

| Pemanggil | Sampel salinan |
|---|---:|
| blok `layout.visit.geometry` di `layoutBlock` (`BlockLayoutPass.swift:274-343`) | 34 |
| blok `reduce` di `layout.height` (`BlockLayoutPass.swift:438-449`) | 10 |
| blok `layout.mode` / `layout.inline.plan` (`BlockLayoutPass.swift:354`, `393-395`) | 8 |
| blok `previous.map` / `allSatisfy` di `layoutLine` (`LineLayoutPass.swift:102`, `127`) | 7 |

Semuanya blok kode `{ … }` di dalam method `mutating` milik `LayoutTree`.

### 2.3 Kenapa blok kode menyalin pohon

`LayoutTree` adalah struct (`LayoutTree.swift:8-20`). Isinya beberapa array dan dictionary besar (`nodes`, `primaryByNode`, `dependencies`, `source`, `detached`, `textRuns`).

Di dalam method `mutating`, `self` dipinjam untuk diubah. Kalau sebuah blok kode `{ … }` memakai `self`, blok itu memegang `self` lewat pinjaman tadi. Saat kode di dalam blok memanggil fungsi yang **hanya membaca** (`x(parent)`, `width(parent)`, `layoutMode(id)`, `height(childID)`), Swift membuat salinan `LayoutTree` dulu, supaya fungsi itu membaca nilai yang tidak bisa berubah di tengah jalan. Salinan ini tidak menyalin isi array. Tetapi setiap array dan dictionary di dalamnya dihitung "dipakai satu pihak lagi" (`swift_retain`), lalu dilepas lagi setelahnya (`swift_release`). Itu terjadi untuk **setiap** pembacaan, di **setiap** blok, di **setiap** baris.

Fungsi yang **mengubah** pohon (`setFrame`, `markField`) tidak kena, karena pinjamannya diteruskan tanpa salinan. Karena itu blok yang hanya memanggil fungsi `mutating` tidak muncul di tabel §2.2.

Kode yang sama di luar blok, langsung di badan method `mutating`, tidak menyalin. Jadi perbaikannya: jangan bungkus kode jalur panas dengan blok `{ … }`.

### 2.4 Lebar 800 px (bukan bagian rencana ini)

`book.css` di halaman ini punya `@media (max-width: 800px) { html { font-size: 18px; } }`. Saat drag melewati 800 px, ukuran font semua teks berubah, jadi semua kata harus diukur ulang dan semua baris disusun ulang (613–845 baris). Rinciannya: `layout.inline.refresh` 7,0 ms, `text.font` 2,5 ms (3.457 panggilan), dan style 8,7 ms di main thread. Browser lain juga melakukan layout penuh di titik ini. Mempercepatnya berarti mempercepat penyusunan ulang item teks setelah font berubah, dan itu butuh analisa sendiri.

## 3. Verifikasi di salinan sementara

Diff dari §4 diterapkan apa adanya di `/tmp/ts-plan`, dengan urutan langkah yang sama:

| Cek | Hasil |
|---|---|
| Sesudah Langkah 1a saja: `swift build --build-tests` | **gagal compile**: `cannot find type 'ProfileSpan' in scope`, `value of type 'Profiler' has no member 'end'` |
| Sesudah Langkah 1b: `swift test --filter ProfilerTests` | 5 tes lolos |
| Sesudah Langkah 2: `swift test` | 420 tes lolos |
| Sesudah Langkah 3–4: `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` | 420 tes lolos |
| Sesudah Langkah 3–4: `swift test` (paralel), 6 kali | `syncLayoutResizeWaitsForTheTick` kadang gagal. **HEAD tanpa perubahan juga gagal 4 dari 6 kali** dengan tes yang sama, jadi ini bukan dari rencana ini |
| Screenshot headless di t = 4,2 s dan di akhir drag | sama persis dengan HEAD (`cmp`) |

Layout per resize di headless (`BrowserTab.layout`, 380 resize per jalan, release build). HEAD dan hasil rencana dijalankan bergantian, supaya kondisi mesin sama:

| Metrik | HEAD | Sesudah Langkah 1–4 |
|---|---:|---:|
| Median, `--no-profile`, 3 jalan | 8,35 / 8,35 / 8,33 ms | **7,06 / 7,05 / 7,13 ms** |
| p90, `--no-profile`, 3 jalan | 12,10 / 12,13 / 11,97 ms | **10,81 / 10,71 / 11,12 ms** |
| Rata-rata, `--no-profile`, 3 jalan | 9,09 / 9,06 / 8,99 ms | **7,71 / 7,73 / 7,88 ms** |
| Median / p90 dengan profiler (seperti GUI), 1 jalan | 9,46 / 13,68 ms | **8,26 / 12,24 ms** |

`sample` dengan cara yang sama seperti §2.2: salinan dan pembuangan `LayoutTree` turun dari **16,8 %** (HEAD, 112 dari 666 sampel) ke **0,1 %** (1 dari 1.993 sampel).

### Perkiraan efek di GUI [INFERENCE]

Kalau layout di GUI turun 15 % seperti di headless:
- Frame dengan layout + paint > 16,67 ms: 242 → sekitar 159 dari 1.015.
- Dari 34 frame lambat karena mesin, 27 → 22 masih lewat batas. Sisanya adalah frame lebar 800 px (§2.4), frame lambat di raster, dan layout dengan potong ulang baris yang sangat banyak.

Jadi langkah ini **tidak cukup sendirian** untuk mencapai 60 fps. Tetapi ini perbaikan yang paling murah dan tidak mengubah hasil layout. Kandidat berikutnya ada di §6.

## 4. Rencana

### File yang berubah

| File | Langkah | Kenapa |
|---|---|---|
| `Tests/ToyStackTests/Diagnostic/ProfilerTests.swift` | 1a | Tes untuk cara ukur baru |
| `Sources/Engine/Diagnostic/Profiler.swift` | 1b | `ProfileSpan`, `begin`, `end`: mengukur tanpa blok kode |
| `Sources/Engine/Layouts/BlockLayoutPass.swift` | 2 | `layoutBlock` tanpa blok kode; isi geometry dan tinggi pindah ke fungsi sendiri |
| `Sources/Engine/Layouts/LineLayoutPass.swift` | 3 | `layoutLine` tanpa blok kode |
| `profiling.md` | 4 | Aturan: di `LayoutTree`, pakai `begin`/`end` |

### Keputusan desain

**Cara mengukur waktu tanpa blok kode**

- **Option A (rekomendasi)**: `profiler.begin("nama")` mengembalikan `ProfileSpan`, lalu `profiler.end(span)` mencatat waktunya. Kode yang diukur tetap di tempatnya, di badan method `mutating`, jadi tidak ada salinan. Nama metrik di trace tidak berubah. Trade-off: kalau `end` lupa dipanggil, metrik itu hilang diam-diam (tidak crash). Karena itu `begin`/`end` hanya dipakai di jalur panas `LayoutTree`, dan selalu berpasangan dalam satu blok yang terlihat.
- **Option B**: `profiler.measure("nama", &self) { tree in … }`, yaitu blok kode menerima pohon sebagai parameter, bukan memegang `self`. Hasilnya sama-sama tanpa salinan, tetapi setiap baris di dalam blok harus ditulis ulang dengan `tree.` di depannya (sekitar 200 baris berubah), dan `measure` butuh versi khusus untuk `LayoutTree`.
- **Option C**: pindahkan isi setiap blok ke fungsi `mutating` sendiri. Ini cocok untuk geometry (yang memang mengubah pohon), tetapi tidak cocok untuk `layoutMode(id)`, yang hanya membaca. Fungsi itu harus dibuat `mutating` tanpa alasan. Isi blok `layout.visit` (150 baris) juga butuh lebih dari 4 parameter.

Rencana ini memakai **A**, ditambah dua fungsi dari C (`placeBlockFrame`, `placeLineChildren`) untuk isi blok yang memang mengubah pohon dan punya `return` di tengah.

**Apa yang tidak diubah**: 19 `profiler.measure` lain di `LayoutTree.swift` (misalnya `layout.line.children.*`). Isinya memanggil fungsi `mutating` milik `dependencies` dan tidak muncul sebagai salinan di `sample` (paling banyak 2 sampel). `measure` tetap dipakai di tempat lain di luar `LayoutTree`.

---

### Langkah 1: cara ukur tanpa blok kode

#### 1a. Tes

`Tests/ToyStackTests/Diagnostic/ProfilerTests.swift:42-50`:

```diff
     @Test func literalAndRuntimeNamesMergeInTheSnapshot() {
         let profiler: Profiler = Profiler(enabled: true)
         profiler.reset()
         profiler.count("test.merged", by: 2)
         let suffix: String = "merged"
         profiler.count(named: "test.\(suffix)", by: 5)
 
         #expect(profiler.snapshot()["test.merged"]?.count == 7)
     }
+
+    @Test func spanRecordsTheTimeBetweenBeginAndEnd() {
+        let profiler: Profiler = Profiler(enabled: true)
+        profiler.reset()
+
+        let span: ProfileSpan = profiler.begin("test.span")
+        Thread.sleep(forTimeInterval: 0.002)
+        profiler.end(span)
+
+        let metric: ProfileMetric? = profiler.snapshot()["test.span"]
+        #expect(metric?.count == 1)
+        #expect((metric?.nanos ?? 0) >= 2_000_000, "the span lost the time it covered")
+    }
+
+    @Test func disabledProfilerRecordsNoSpan() {
+        let profiler: Profiler = Profiler(enabled: false)
+
+        let span: ProfileSpan = profiler.begin("test.span")
+        profiler.end(span)
+
+        #expect(profiler.snapshot()["test.span"] == nil)
+    }
```

Jalankan `swift test --filter ProfilerTests`. Hasil yang diharapkan: **gagal compile**, karena `ProfileSpan` dan `begin` belum ada.

`spanRecordsTheTimeBetweenBeginAndEnd` menangkap `end` yang mencatat ke nama lain, mencatat 0 ns, atau lupa menambah hitungan. `disabledProfilerRecordsNoSpan` menangkap `--no-profile` yang masih mencatat.

#### 1b. `ProfileSpan`, `begin`, `end`

`Sources/Engine/Diagnostic/Profiler.swift:43-50`:

```diff
     @discardableResult
     func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
         guard enabled else { return body() }
         let start: UInt64 = DispatchTime.now().uptimeNanoseconds
         let result: T = body()
         record(name, nanos: DispatchTime.now().uptimeNanoseconds - start)
         return result
     }
+
+    /// A closure handed to `measure` from a mutating `LayoutTree` method
+    /// captures the tree; each read-only call inside it copies the whole tree
+    /// (a retain and release per stored array). During a resize that was 17%
+    /// of layout. A span keeps the measured code inline instead.
+    func begin(_ name: StaticString) -> ProfileSpan {
+        guard enabled else { return ProfileSpan(name: name, start: 0) }
+        return ProfileSpan(name: name, start: DispatchTime.now().uptimeNanoseconds)
+    }
+
+    func end(_ span: ProfileSpan) {
+        guard enabled else { return }
+        record(span.name, nanos: DispatchTime.now().uptimeNanoseconds - span.start)
+    }
```

Akhir file `Profiler.swift`, setelah `let profiler` (`Profiler.swift:90-92`):

```diff
 let profiler: Profiler = Profiler(
     enabled: !ProcessInfo.processInfo.arguments.contains("--no-profile")
 )
+
+// MARK: - ProfileSpan
+
+struct ProfileSpan {
+    let name: StaticString
+    let start: UInt64
+}
 
 // MARK: - ProfileWindow
```

Jalankan `swift test --filter ProfilerTests`: 5 tes lolos.

---

### Langkah 2: `layoutBlock` tanpa blok kode

Tidak ada tes baru di langkah ini. Hasil layout tidak berubah; yang berubah hanya ada atau tidaknya salinan, dan itu tidak bisa dilihat dari tes tanpa mengukur waktu (tes yang mengukur waktu mudah gagal sendiri). Pengamannya adalah tes layout yang sudah ada (`LayoutOracleTests`, `LayoutIdempotenceTests`, `BlockWidthChangeMetricTests`, `GeometryInvalidationTests`, `InlineTextLayoutTests`) ditambah pengukuran di §5.

#### 2a. Geometry pindah ke `placeBlockFrame`

`Sources/Engine/Layouts/BlockLayoutPass.swift:271-344`:

```diff
-        profiler.measure("layout.visit") {
+        let visitSpan: ProfileSpan = profiler.begin("layout.visit")
+        do {
             profiler.count("layout.rebuilt")
             if geometryDirty {
-            profiler.measure("layout.visit.geometry", {
-            let zoomValue: CGFloat = resolvedZoom(id)
-            let isAbsolute: Bool = style.position == .absolute
-            let parent: LayoutID = parentID(of: id)!
-
-            let parentX: CGFloat = x(parent)
-            let padLeft: CGFloat = !hasExtraNodes(id)
-                ? style.box.padding.left * zoomValue
-                : 0
-            var frameX: CGFloat
-            if isAbsolute, let l = style.flags.left {
-                frameX = l * zoomValue + padLeft
-            } else {
-                frameX = parentX + padLeft
-            }
-
-            let parentWidth: CGFloat = width(parent)
-            let padHorizontal: CGFloat = !hasExtraNodes(id)
-                ? (style.box.padding.left + style.box.padding.right) * zoomValue
-                : 0
-            var frameWidth: CGFloat
-            if let w = style.box.width {
-                frameWidth = w * zoomValue
-            } else {
-                frameWidth = max(0, parentWidth - padHorizontal)
-            }
-
-            let element = domView(id).element
-            if element?.tag == "li" {
-                frameX += liIndent
-                frameWidth -= liIndent
-            }
-
-            var frameY: CGFloat
-            if isAbsolute, let t = style.flags.top {
-                let padTop: CGFloat = !hasExtraNodes(id)
-                    ? style.box.padding.left * zoomValue
-                    : 0
-                frameY = t * zoomValue + padTop
-            } else {
-                let ownTop: CGFloat = style.box.margin.top * zoomValue
-                let padTop: CGFloat = style.box.padding.top * zoomValue
-                if let previous: LayoutID = blockPrevious(id) {
-                    let prevY: CGFloat = y(previous)
-                    let prevHeight: CGFloat = height(previous)
-                    let prevPadBottom: CGFloat = isBlock(previous)
-                        ? padding(previous, .paddingBottom)
-                        : 0
-                    let prevMarginBottom: CGFloat = isBlock(previous)
-                        ? blockStyle(previous).box.margin.bottom
-                        : 0
-                    frameY = prevY + prevHeight + prevPadBottom
-                        + prevMarginBottom * zoomValue + ownTop + padTop
-                } else {
-                    frameY = y(parent) + ownTop + padTop
-                }
-            }
-
-            if element?.attributes["id"] == "toc" {
-                frameY += VSTEP
-            }
-
-            let oldGeometry: GeometryFields = self[node: id].state.fields.geometry
-            let widthWasUsed: Bool = isUsed(.width, at: id)
-            setFrame(
-                (zoom: zoomValue, x: frameX, y: frameY, width: frameWidth),
-                for: id
-            )
-            countWidthChange(from: oldGeometry, widthWasUsed: widthWasUsed, at: id)
-            })
+                let geometrySpan: ProfileSpan = profiler.begin("layout.visit.geometry")
+                placeBlockFrame(id, style: style)
+                profiler.end(geometrySpan)
             }
```

`do { … }` menggantikan blok `{ … }` milik `measure` dengan cakupan yang sama, jadi 80 baris di dalamnya tidak perlu digeser.

Fungsi baru, setelah `countWidthChange` (`BlockLayoutPass.swift:476-487`):

```diff
     private func countWidthChange(from old: GeometryFields, widthWasUsed: Bool, at id: LayoutID) {
         let new: GeometryFields = self[node: id].state.fields.geometry
         if !widthWasUsed || old.size.width != new.size.width {
             profiler.count("layout.width.changed")
         } else if old.origin.x != new.origin.x {
             profiler.count("layout.width.same.xMoved")
         } else if old.origin.y != new.origin.y {
             profiler.count("layout.width.same.yMoved")
         } else {
             profiler.count("layout.width.same.unmoved")
         }
     }
+
+    mutating private func placeBlockFrame(_ id: LayoutID, style: BlockStyle) {
+        let zoomValue: CGFloat = resolvedZoom(id)
+        let isAbsolute: Bool = style.position == .absolute
+        let parent: LayoutID = parentID(of: id)!
+
+        let parentX: CGFloat = x(parent)
+        let padLeft: CGFloat = !hasExtraNodes(id)
+            ? style.box.padding.left * zoomValue
+            : 0
+        var frameX: CGFloat
+        if isAbsolute, let l = style.flags.left {
+            frameX = l * zoomValue + padLeft
+        } else {
+            frameX = parentX + padLeft
+        }
+
+        let parentWidth: CGFloat = width(parent)
+        let padHorizontal: CGFloat = !hasExtraNodes(id)
+            ? (style.box.padding.left + style.box.padding.right) * zoomValue
+            : 0
+        var frameWidth: CGFloat
+        if let w = style.box.width {
+            frameWidth = w * zoomValue
+        } else {
+            frameWidth = max(0, parentWidth - padHorizontal)
+        }
+
+        let element = domView(id).element
+        if element?.tag == "li" {
+            frameX += liIndent
+            frameWidth -= liIndent
+        }
+
+        var frameY: CGFloat
+        if isAbsolute, let t = style.flags.top {
+            let padTop: CGFloat = !hasExtraNodes(id)
+                ? style.box.padding.left * zoomValue
+                : 0
+            frameY = t * zoomValue + padTop
+        } else {
+            let ownTop: CGFloat = style.box.margin.top * zoomValue
+            let padTop: CGFloat = style.box.padding.top * zoomValue
+            if let previous: LayoutID = blockPrevious(id) {
+                let prevY: CGFloat = y(previous)
+                let prevHeight: CGFloat = height(previous)
+                let prevPadBottom: CGFloat = isBlock(previous)
+                    ? padding(previous, .paddingBottom)
+                    : 0
+                let prevMarginBottom: CGFloat = isBlock(previous)
+                    ? blockStyle(previous).box.margin.bottom
+                    : 0
+                frameY = prevY + prevHeight + prevPadBottom
+                    + prevMarginBottom * zoomValue + ownTop + padTop
+            } else {
+                frameY = y(parent) + ownTop + padTop
+            }
+        }
+
+        if element?.attributes["id"] == "toc" {
+            frameY += VSTEP
+        }
+
+        let oldGeometry: GeometryFields = self[node: id].state.fields.geometry
+        let widthWasUsed: Bool = isUsed(.width, at: id)
+        setFrame(
+            (zoom: zoomValue, x: frameX, y: frameY, width: frameWidth),
+            for: id
+        )
+        countWidthChange(from: oldGeometry, widthWasUsed: widthWasUsed, at: id)
+    }
```

Isinya sama persis dengan blok lama; hanya geser 4 spasi ke kiri.

#### 2b. `layout.mode`

`BlockLayoutPass.swift:354`:

```diff
-            let mode: LayoutMode = profiler.measure("layout.mode", { layoutMode(id) })
+            let modeSpan: ProfileSpan = profiler.begin("layout.mode")
+            let mode: LayoutMode = layoutMode(id)
+            profiler.end(modeSpan)
```

#### 2c. `layout.inline.refresh`, `layout.inline.plan`, `layout.inline.place`

`BlockLayoutPass.swift:386-419`:

```diff
                 if inlineContentChanged {
                     let preserveObjects: Bool = canRefreshFontsOnly(id)
-                    profiler.measure("layout.inline.refresh", {
-                        preservedItems = refreshInlineItems(id, preservingObjects: preserveObjects)
-                    })
+                    let refreshSpan: ProfileSpan = profiler.begin("layout.inline.refresh")
+                    preservedItems = refreshInlineItems(id, preservingObjects: preserveObjects)
+                    profiler.end(refreshSpan)
                 }
                 let oldPlan: InlineLinePlan? = self[block: id].content.inlineLinePlan
-                let plan: InlineLinePlan? = profiler.measure("layout.inline.plan", {
-                    inlineTextLinePlan(id)
-                })
+                let planSpan: ProfileSpan = profiler.begin("layout.inline.plan")
+                let plan: InlineLinePlan? = inlineTextLinePlan(id)
+                profiler.end(planSpan)
                 let shouldPlace: Bool = inlineContentChanged
                     || plan == nil
                     || plan?.lines != oldPlan?.lines
                 let canReusePlan: Bool = !inlineContentChanged || preservedItems
                 if !shouldPlace, widthChanged, !frameMoved,
                     !isDirty(.height, at: id),
                     canSkipInlineChildren(id)
                 {
                     updateInlineLineFrames(id)
                     skipInlineChildren = true
                 }
                 if shouldPlace {
+                    let placeSpan: ProfileSpan = profiler.begin("layout.inline.place")
                     if canReusePlan, let plan, let oldPlan {
-                        profiler.measure("layout.inline.place", {
-                            placeInlineItems(
-                                id,
-                                plan: plan.lines,
-                                oldPlan: oldPlan.lines,
-                                refreshMetrics: preservedItems
-                            )
-                        })
+                        placeInlineItems(
+                            id,
+                            plan: plan.lines,
+                            oldPlan: oldPlan.lines,
+                            refreshMetrics: preservedItems
+                        )
                     } else {
-                        profiler.measure("layout.inline.place", { placeInlineItems(id) })
+                        placeInlineItems(id)
                     }
+                    profiler.end(placeSpan)
                 } else {
```

#### 2d. Akhir `layout.visit`, `layout.visit.children`, `layout.height`

`BlockLayoutPass.swift:426-453`:

```diff
             }
         }
+        profiler.end(visitSpan)
 
         var measuredHeight: CGFloat? = nil
         if !skipInlineChildren {
-            profiler.measure("layout.visit.children", {
-                for child in childrenIDs(of: id) { layout(child) }
-            })
+            let childrenSpan: ProfileSpan = profiler.begin("layout.visit.children")
+            for child in childrenIDs(of: id) { layout(child) }
+            profiler.end(childrenSpan)
 
             setHeightInputs(id)
             let heightChildren: [LayoutID] = childrenIDs(of: id)
-            measuredHeight = profiler.measure("layout.height", {
-                heightChildren.reduce(0) { total, childID in
-                    let position: LayoutStyle.Position = domView(childID).style.computed.layout.position.kind
-                    if position == .absolute { return total }
-                    var h: CGFloat = height(childID)
-                    if isBlock(childID) {
-                        let childStyle: BlockStyle = blockStyle(childID)
-                        let childZoom: CGFloat = zoom(childID)
-                        h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
-                        h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
-                    }
-                    return total + h
-                }
-            })
+            let heightSpan: ProfileSpan = profiler.begin("layout.height")
+            measuredHeight = flowHeight(of: heightChildren)
+            profiler.end(heightSpan)
         } else {
```

Fungsi baru, setelah `placeBlockFrame`:

```diff
+
+    mutating private func flowHeight(of children: [LayoutID]) -> CGFloat {
+        var total: CGFloat = 0
+        for childID in children {
+            let position: LayoutStyle.Position = domView(childID).style.computed.layout.position.kind
+            if position == .absolute { continue }
+            var h: CGFloat = height(childID)
+            if isBlock(childID) {
+                let childStyle: BlockStyle = blockStyle(childID)
+                let childZoom: CGFloat = zoom(childID)
+                h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
+                h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
+            }
+            total += h
+        }
+        return total
+    }
```

`flowHeight` harus `mutating` karena `blockStyle(_:)` menyimpan cache style (`BlockLayoutPass.swift:1612`).

Jalankan `swift build` lalu `swift test`: semua lolos.

---

### Langkah 3: `layoutLine` tanpa blok kode

`Sources/Engine/Layouts/LineLayoutPass.swift:100-102`:

```diff
         let parent: LayoutID = parentID(of: id)!
         let previous: LayoutID? = previousID(of: id)
-        let lineY: CGFloat = previous.map({ y($0) + height($0) }) ?? y(parent)
+        var lineY: CGFloat = y(parent)
+        if let previous {
+            lineY = y(previous) + height(previous)
+        }
```

`LineLayoutPass.swift:127`:

```diff
-        let textOnly: Bool = children.allSatisfy({ isText($0) })
+        var textOnly: Bool = true
+        for child in children where !isText(child) {
+            textOnly = false
+            break
+        }
```

`LineLayoutPass.swift:141-146`:

```diff
         if verticalOnly, let childOriginY: CGFloat = self[line: id].placement.childOriginY {
             profiler.count("layout.line.place.verticalOnly")
-            profiler.measure("layout.line.place.vertical", {
-                let offset: CGFloat = y(id) - childOriginY
-                self[line: id].placement.inlineYOffset = offset
-            })
+            let verticalSpan: ProfileSpan = profiler.begin("layout.line.place.vertical")
+            self[line: id].placement.inlineYOffset = y(id) - childOriginY
+            profiler.end(verticalSpan)
```

`LineLayoutPass.swift:163-228`. Isi blok `layout.line.place` pindah ke `placeLineChildren`, karena isinya punya `return` di tengah:

```diff
         for child in children { layout(child) }
 
         profiler.count("layout.line.place.placed")
-        profiler.measure("layout.line.place", {
-            if hasBoxes, children.isEmpty {
-                layoutLineBoxes(id)
-                return
-            }
-            guard !children.isEmpty else {
-                setField(.ascent, 0, for: id)
-                setField(.descent, 0, for: id)
-                setField(.height, 0, for: id)
-                return
-            }
-
-            let inlineChildren: [LayoutID] = children.filter({ isText($0) || isEmbed($0) })
-            guard !inlineChildren.isEmpty else {
-                setField(.height, 0, for: id)
-                return
-            }
-
-            var maxAscent: CGFloat = 0
-            var maxDescent: CGFloat = 0
-            for child in inlineChildren {
-                maxAscent = max(maxAscent, ascent(child))
-                maxDescent = max(maxDescent, descent(child))
-            }
-            setField(.ascent, maxAscent, for: id)
-            setField(.descent, maxDescent, for: id)
-
-            var nextX: CGFloat = x(id)
-            var previousFont: BrowserFont? = nil
-            let baseline: CGFloat = y(id) + ascent(id)
-            for (index, child) in inlineChildren.enumerated() {
-                if let previousFont, isEmbed(child) {
-                    nextX += previousFont.spaceWidth
-                }
-                let childY: CGFloat = inputs.tag(domID(of: child)) == "sup"
-                    ? baseline - maxAscent
-                    : baseline - ascent(child)
-                setPosition(x: nextX, y: childY, for: child)
-                nextX += inlineWidth(id, index: index, child: child)
-                previousFont = font(child)
-            }
-
-            for child in children where !isText(child) && !childrenIDs(of: child).isEmpty {
-                layout(child)
-            }
-
-            if inputs.style(domID(of: id)).text.direction == .rtl {
-                let usedWidth: CGFloat = contentWidth(id)
-                shiftChildren(id, by: width(id) - usedWidth)
-            }
-
-            if self[line: id].content.centered {
-                let usedWidth: CGFloat = contentWidth(id)
-                shiftChildren(id, by: (width(id) - usedWidth) / 2)
-            }
-
-            setField(.height, ascent(id) + descent(id), for: id)
-            let originY: CGFloat = y(id)
-            self[line: id].placement.childOriginY = originY
-            self[line: id].placement.inlineYOffset = 0
-            syncInlineBoxes(id)
-        })
+        let placeSpan: ProfileSpan = profiler.begin("layout.line.place")
+        placeLineChildren(id, children: children, hasBoxes: hasBoxes)
+        profiler.end(placeSpan)
+    }
+
+    mutating private func placeLineChildren(_ id: LayoutID, children: [LayoutID], hasBoxes: Bool) {
+        if hasBoxes, children.isEmpty {
+            layoutLineBoxes(id)
+            return
+        }
+        guard !children.isEmpty else {
+            setField(.ascent, 0, for: id)
+            setField(.descent, 0, for: id)
+            setField(.height, 0, for: id)
+            return
+        }
+
+        let inlineChildren: [LayoutID] = children.filter({ isText($0) || isEmbed($0) })
+        guard !inlineChildren.isEmpty else {
+            setField(.height, 0, for: id)
+            return
+        }
+
+        var maxAscent: CGFloat = 0
+        var maxDescent: CGFloat = 0
+        for child in inlineChildren {
+            maxAscent = max(maxAscent, ascent(child))
+            maxDescent = max(maxDescent, descent(child))
+        }
+        setField(.ascent, maxAscent, for: id)
+        setField(.descent, maxDescent, for: id)
+
+        var nextX: CGFloat = x(id)
+        var previousFont: BrowserFont? = nil
+        let baseline: CGFloat = y(id) + ascent(id)
+        for (index, child) in inlineChildren.enumerated() {
+            if let previousFont, isEmbed(child) {
+                nextX += previousFont.spaceWidth
+            }
+            let childY: CGFloat = inputs.tag(domID(of: child)) == "sup"
+                ? baseline - maxAscent
+                : baseline - ascent(child)
+            setPosition(x: nextX, y: childY, for: child)
+            nextX += inlineWidth(id, index: index, child: child)
+            previousFont = font(child)
+        }
+
+        for child in children where !isText(child) && !childrenIDs(of: child).isEmpty {
+            layout(child)
+        }
+
+        if inputs.style(domID(of: id)).text.direction == .rtl {
+            let usedWidth: CGFloat = contentWidth(id)
+            shiftChildren(id, by: width(id) - usedWidth)
+        }
+
+        if self[line: id].content.centered {
+            let usedWidth: CGFloat = contentWidth(id)
+            shiftChildren(id, by: (width(id) - usedWidth) / 2)
+        }
+
+        setField(.height, ascent(id) + descent(id), for: id)
+        let originY: CGFloat = y(id)
+        self[line: id].placement.childOriginY = originY
+        self[line: id].placement.inlineYOffset = 0
+        syncInlineBoxes(id)
     }
```

`return` di dalam blok lama keluar dari blok; sekarang keluar dari `placeLineChildren`. Setelah itu `layoutLine` tetap memanggil `profiler.end(placeSpan)`, jadi artinya sama. Blok `filter` yang tersisa di `placeLineChildren` sengaja tidak diubah: blok itu tidak muncul di `sample`.

Jalankan `swift build` lalu `swift test`: semua lolos.

---

### Langkah 4: dokumentasi

`profiling.md:545-547`:

```diff
 - `profiler.measure` / `profiler.count` inside recursion only.
+- Inside a mutating `LayoutTree` method, use `profiler.begin` / `profiler.end`
+  instead of `profiler.measure`. A closure there captures the tree, and every
+  read-only call inside it copies the whole tree; during a resize that was 17%
+  of layout time.
 - Do not `measure` inside a per-item loop. Accumulate and call `count(name, by:)`
   once, as `style.matchesTrue` does.
```

Tidak ada nama metrik yang berubah, jadi tabel metrik di `profiling.md` tetap sama.

## 5. Cara mengukur ulang

Build release:

```bash
swift build -c release --product ToyStackHeadless
```

Buat daftar resize (1440 → 300 → 1440, 6 px per tick 60 Hz):

```bash
args=""; t=1.0
for w in $(seq 1440 -6 300) $(seq 300 6 1440); do
  args="$args --resize-at $(printf %.4f $t):$w:900"
  t=$(echo "$t + 0.016667" | bc -l)
done
```

Jalankan 3 kali sebelum dan 3 kali sesudah perubahan:

```bash
.build/release/ToyStackHeadless https://browser.engineering/reflow.html \
  --width 1440 --height 900 --run-for 8.8 --no-profile \
  --trace /tmp/resize.trace $args
```

Bandingkan median dan p90 durasi `BrowserTab.layout` (abaikan layout pertama setelah load). Target sesuai §3: median sekitar 7,0 ms, p90 sekitar 10,8 ms. Lalu rekam ulang `browser.trace` di GUI dengan drag yang mirip dan cek:
- `layout.async.document` p50 dan p90 selama resize,
- jumlah frame dengan layout + paint > 16,67 ms (sekarang 242 dari 1.015).

## 6. Yang belum masuk rencana ini

Dari `sample` sesudah Langkah 1–4 (1.993 sampel; persentase dari waktu layout):

| Bagian | % | Catatan |
|---|---:|---|
| `markDependents` (dari `setFrame` dan `layoutLine`) | 18,9 | Setiap field yang berubah mencari pembacanya di `DependencyIndex` (dictionary berisi `Set`) |
| `__RawDictionaryStorage.find` | 14,3 | Sebagian besar dari `markDependents` |
| `DependencyIndex.replaceDependent` | 9,2 | Hampir semuanya dari `setLineChildrenField`: setiap baris yang disusun ulang menulis ulang edge `ascent`/`descent` |
| `layoutMode` | 6,1 | Membuat array anak DOM baru di setiap kunjungan (`LayoutDOMView.children.getter`) |

Ketiga bagian pertama naik seiring jumlah baris yang disusun ulang, jadi merekalah yang paling berpengaruh pada 15 frame "banyak baris dipotong ulang". Mengubahnya berarti mengubah bentuk `DependencyIndex`, dan perlu diukur dulu sendiri sebelum dibuat rencananya.

Lebar 800 px (§2.4) dan raster (12 frame) juga di luar rencana ini.

## 7. Temuan setelah diterapkan (`browser.trace` 14-11, 22:21)

### 7.1 Tiga perbedaan dari rencana

| # | Di mana | Masalah | Akibat |
|---|---|---|---|
| 1 | `Profiler.swift:59` | `end` mencatat `uptimeNanoseconds` tanpa dikurangi `span.start` | Semua `profile.layout` dari `begin`/`end` berisi waktu sejak Mac menyala, misalnya `layout.visit.us` = 881.470.740.335.896. Penjumlahan `metric.nanos +=` akan crash (overflow) setelah sekitar 33.000 span dalam satu jendela profiler |
| 2 | `LineLayoutPass.swift:169` | Nama span `"layout.place"`, seharusnya `"layout.line.place"` | `layout.line.place.us` hilang dari trace; `profiling.md:318` masih menyebut nama lama |
| 3 | `LineLayoutPass.swift:152-153` | Komentar "Boxes store y relative to the line…" ikut terhapus | Hilang penjelasan *kenapa* jalur `verticalOnly` boleh memakai box lama |

Tes `spanRecordsTheTimeBetweenBeginAndEnd` dari Langkah 1a tetap lolos dengan bug #1, karena hanya memeriksa batas bawah (≥ 2 ms), dan waktu sejak Mac menyala selalu lebih besar. Itu kelemahan tes di rencana ini.

#### 7.1a Tes: span tidak boleh mencatat lebih dari waktu yang dicakupnya

`Tests/ToyStackTests/Diagnostic/ProfilerTests.swift:60-63`:

```diff
         let metric: ProfileMetric? = profiler.snapshot()["test.span"]
         #expect(metric?.count == 1)
         #expect((metric?.nanos ?? 0) >= 2_000_000, "the span lost the time it covered")
+        #expect((metric?.nanos ?? .max) < 1_000_000_000, "the span recorded more than the time it covered")
     }
```

Jalankan `swift test --filter ProfilerTests`. Hasil yang diharapkan: **gagal** di baris baru, karena `nanos` berisi waktu sejak Mac menyala.

#### 7.1b Perbaikan `end`

`Sources/Engine/Diagnostic/Profiler.swift:57-60`:

```diff
     func end(_ span: ProfileSpan) {
         guard enabled else { return }
-        record(span.name, nanos: DispatchTime.now().uptimeNanoseconds)
+        record(span.name, nanos: DispatchTime.now().uptimeNanoseconds - span.start)
     }
```

#### 7.1c Nama span dan komentar

`Sources/Engine/Layouts/LineLayoutPass.swift:150-154`:

```diff
             let verticalSpan: ProfileSpan = profiler.begin("layout.line.place.vertical")
             self[line: id].placement.inlineYOffset = y(id) - childOriginY
             profiler.end(verticalSpan)
+            // Boxes store y relative to the line (`y(child) - childOriginY`),
+            // and this path keeps x, widths, and children, so a line that only
+            // moved still has the right boxes. Only build them if it has none.
             if self[line: id].content.boxes.isEmpty {
```

`Sources/Engine/Layouts/LineLayoutPass.swift:169`:

```diff
-        let placeSpan: ProfileSpan = profiler.begin("layout.place")
+        let placeSpan: ProfileSpan = profiler.begin("layout.line.place")
```

### 7.2 Hasil di GUI tertutup oleh raster

Rekaman baru tidak sebanding dengan rekaman 09:13:

| | 09:13 (sebelum) | 22:21 (sesudah) |
|---|---:|---:|
| Posisi scroll saat resize (`tiles.scroll`) | 371 px | 1.191 px |
| Perubahan lebar per frame p50 / p95 | 4 / 19 px | 8 / 24 px |
| Tile dipakai ulang / digambar ulang per frame (p50) | 42 / 35 | **0 / 70** |
| Potongan raster per frame | 5,5 | 8,9 |
| Thread raster yang jalan bersamaan dengan layout (rata-rata) | 0,79 | **2,08** |
| `composite_raster_and_draw` p50 / p90 | 4,8 / 7,8 ms | 6,8 / 14,6 ms |
| FPS (tanpa jeda input) | 59,1 | 58,9 |

Saat halaman di-scroll ke bawah, reflow menggeser semua isi di bawah titik itu, jadi hampir tidak ada tile yang sama dengan sebelumnya. Raster bekerja dua kali lebih banyak dan memakai core CPU yang sama dengan layout.

Layout dengan jumlah baris yang disusun ulang setara (200–500 baris), dikelompokkan menurut jumlah thread raster yang jalan bersamaan:

| Thread raster bersamaan | 09:13 | 22:21 |
|---|---:|---:|
| < 0,5 | 9,69 ms (n = 119) | **8,67 ms** (n = 46) |
| 0,5–1,5 | 10,22 ms (n = 204) | 9,64 ms (n = 94) |
| ≥ 1,5 | 10,97 ms (n = 71) | 11,08 ms (n = 309) |

Saat CPU tidak direbut raster, layout ~10 % lebih cepat, searah dengan headless. Di rekaman baru, 69 % job di kelompok 200–500 baris berjalan bersama ≥ 1,5 thread raster (sebelumnya 18 %), jadi keuntungannya hilang. Untuk membandingkan, rekam ulang dengan posisi scroll dan kecepatan drag seperti rekaman 09:13 (scroll dekat atas, ~4 px per frame).

### 7.3 Rekaman 22:28 (sesudah perbaikan §7.1)

Nilai `profile.layout` sudah wajar lagi (misalnya `layout.visit.us` median 5.507), dan `layout.line.place` muncul kembali. Komentar "Boxes store y relative to the line…" (§7.1c) belum dikembalikan.

Rekaman ini masih tidak sebanding untuk raster: scroll di **1.731 px** (09:13: 371 px), tile dipakai ulang 0 dan digambar ulang 77 per frame (09:13: 42 dan 35), dan paint mengerjakan 377 operasi per frame (09:13: 182).

Layout, dikelompokkan menurut jumlah baris yang disusun ulang (tanpa 6 job lebar 800 px):

| Baris disusun ulang | 09:13 p50 | 22:28 p50 |
|---|---:|---:|
| 0–100 | 7,60 ms | 6,94 ms |
| 100–200 | 8,58 ms | 8,29 ms |
| 200–400 | 9,95 ms | 9,63 ms |
| 400–700 | 11,45 ms | 10,82 ms |
| 700+ | 15,10 ms | 13,07 ms |

Layout dengan 200–500 baris disusun ulang, menurut jumlah thread raster yang jalan bersamaan: < 0,5 → 9,69 vs **8,85 ms** (−9 %); 0,5–1,5 → 10,22 vs 9,69 ms; ≥ 1,5 → 10,97 vs 10,94 ms.

| | 09:13 | 22:28 |
|---|---:|---:|
| FPS dari jarak antar frame (tanpa jeda input) | 59,1 | 60,8 |
| FPS dihitung per pergantian layar 60 Hz | 53,7 | 53,8 |
| Layout > 13,2 ms | 12,7 % | **6,8 %** |
| Paint p50 | 3,45 ms | 4,02 ms |
| Layout + paint > 16,67 ms | 22,3 % | 26,4 % |
| Frame lambat karena mesin (layout / raster) | 34 (21 / 12) | 38 (19 / 19) |

Layout lebih cepat 3–13 % per kelompok, tetapi paint di posisi scroll ini 0,6 ms lebih lambat (dua kali lebih banyak operasi), jadi layout + paint secara total tidak membaik.

### 7.4 Rekaman 22:46 (sebanding dengan 09:13)

Posisi scroll 567 px (sebagian 311 px), tile dipakai ulang / digambar ulang 35 / 32 per frame, 206 operasi paint, rata-rata 0,89 thread raster bersamaan dengan layout, perubahan lebar p50 5 px. Semua dekat dengan rekaman 09:13 (371 px, 42 / 35, 182, 0,79, 4 px).

| | 09:13 | 22:46 |
|---|---:|---:|
| Layout p50 / p90 | 9,66 / 13,85 ms | **8,73 / 11,94 ms** |
| Layout + paint > 16,67 ms | 22,3 % | **15,7 %** |
| Frame lambat karena mesin (layout / raster / paint) | 34 (21 / 12 / 1) | **26 (14 / 11 / 1)** |
| Frame lambat karena menunggu event resize | 105 | 140 |
| Jarak antar event resize > 20 ms | 20,1 % | 25,5 % |
| FPS dari jarak antar frame (tanpa jeda input) | 59,1 | 57,7 |
| FPS dihitung per pergantian layar 60 Hz | 53,7 | 50,1 |

Per kelompok baris yang disusun ulang, layout 6–20 % lebih cepat (0–100: 7,60 → 6,69 ms; 200–400: 9,95 → 8,81 ms; 700+: 15,10 → 12,13 ms).

FPS turun karena input, bukan mesin: dari 140 frame yang menunggu event resize, main thread hanya menjalankan `BrowserTab.animFrame` (median 0,08 ms) sebelum 32 event, dan diam sebelum sisanya. Lewat lebar 800 px masih 26,3–28,9 ms (7 kali).
