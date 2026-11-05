# Layout Reflow Cost — Plan Lanjutan

Tanggal: 2026-11-05
Sumber: `browser.trace` terbaru (10.906 event), `plans/resize-flow-trace-2026-11-05.md`
poin 1, dan `plans/viewport-style-scope-2026-11-05.md`.

## 1. Hubungan dengan poin 1

Plan ini adalah eksekusi poin 1: **turunkan biaya reflow dulu**. Poin 2 (style
pass viewport) sudah selesai. Poin 3 (pindah layout dari main thread) belum
disentuh dan tidak akan membantu selama satu reflow masih 155 ms.

Trace terbaru memakai halaman yang sama dengan laporan lama:

| Klaim poin 1 | Trace terbaru |
|---|---:|
| 1.773 node selalu di-rebuild | `layout.visit` = `layout.rebuilt` = **1.773** |
| `layout.inputs.build` 12–20 ms | **9,3–18,6 ms** |
| `layout.field.mark` puluhan ribu | **11.825–74.708** |
| `layout.field.set` puluhan ribu | **25.540–89.126** |
| 50–70 ms di luar span per-node | `BrowserTab.layout` 155–161 ms vs `layout.visit` 79–85 ms |

Dua rezim yang harus dibedakan:

| Rezim | Frame | `inline.place` | `layout.text` | `measureCalls` | Layout |
|---|---:|---:|---:|---:|---:|
| Width-only reflow | 82, 86, 88 | 30–41 ms | ~0 | 11 | 100–112 ms |
| Breakpoint + `font-size` | 80, 84, 90, 137 | 43–49 ms | 17,7–18,3 ms | 20.672 | 155–161 ms |

## 2. Tujuan dan urutan

Target akhir tetap **layout < 16 ms**. Urutan kerja:

1. **Reuse layout inputs antar-pass** (selesai).
   Target: hilangkan 9–18 ms `layout.inputs.build` pada pass yang DOM dan
   style-nya tidak berubah.
2. **Hentikan penempatan ulang baris yang tidak berubah** (selesai).
   Target: `inline.place` dan `line.children.deps` turun pada width-only reflow.
3. **Cache pengukuran teks per item saat `font-size` berubah** (selesai).
   Target: 20.672 `measureCalls` dan `text.measure` 18 ms turun.
4. **Kurangi churn dependency field** (sebagian).
   `layout.field.mark/set` 11k–89k dan `line.children.deps` 8–14 ms.
5. **Instrumentasi orkestrasi `layoutDocument`** (selesai).
   Selisih `BrowserTab.layout` vs `layout.visit` masih 70–80 ms.

Plan ini mengerjakan langkah 1 dan 2. Langkah 3–5 menjadi plan terpisah agar
setiap langkah bisa diukur sendiri.

## 3. Keputusan desain langkah 1

**Option A — pakai `LayoutInputs` dari layout tree sebelumnya (dipilih).**
Layout tree sudah menyimpan inputs pass terakhir. Builder membandingkan
`ObjectIdentifier(dom)`, `dom.revision`, image revision, dan `style.revision`
per node. Node yang revision-nya sama memakai input lama; node yang berubah
dibangun ulang.

- Keuntungan: tidak menambah salinan `LayoutInputs` yang persisten; array lama
  dipakai sebagai COW source.
- Kekurangan: array baru tetap dibuat saat ada node berubah.

**Option B — cache `LayoutInputs` penuh di `Frame`.**
Lebih sederhana, tetapi menyimpan salinan besar kedua (15 ribu node) di samping
inputs yang sudah dipegang layout tree. Ditolak karena memori dan duplikasi.

Kunci invalidasi:

| Faktor | Sumber |
|---|---|
| DOM berbeda / berubah | `ObjectIdentifier(dom)` + `dom.revision` |
| Gambar berubah | `ImageTable.revision` (baru) |
| Style node berubah | `StyleFields.revision` per node |
| Ada style write apa pun | `StyleRevision.epoch` global |
| Font warisan berubah tanpa revision node | perbandingan `font` dengan style parent untuk text node |

`ImageTable.revision` perlu ada karena gambar dimuat tanpa mengubah DOM revision
maupun style revision (`ElementRef.image` setter). Tanpa revision itu, input
gambar bisa basi.

## 4. File yang berubah

| File | Perubahan |
|---|---|
| `Sources/Engine/Layouts/LayoutInputsKey.swift` (baru) | Kunci revisi untuk reuse. |
| `Sources/Engine/Style/StyleRevision.swift` (baru) | Epoch global untuk setiap perubahan computed style. |
| `Sources/Engine/Layouts/LayoutInputsBuilder.swift` | Reuse node input yang tidak berubah; counter `layout.inputs.reused/rebuilt/style`. |
| `Sources/Engine/Layouts/LayoutTree.swift` | `clearStyleChanges()` untuk membuang perubahan setelah layout selesai. |
| `Sources/Engine/Layouts/DocumentLayoutPass.swift` | Panggil `clearStyleChanges()` di akhir pass. |
| `Sources/Engine/Core/Frame.swift` | Simpan kunci, pakai input tree sebelumnya, build inputs sekali per pass. |
| `Sources/Engine/Parsing/DOMSideTables.swift` | `ImageTable.revision`. |
| `Sources/Engine/Parsing/ElementRef.swift` | Bump revision saat `image` berubah. |
| `Tests/ToyStackTests/LayoutInputsCacheTests.swift` (baru) | Reuse width-only, rebuild style/DOM/gambar. |

## 5. Perubahan kode

### 5.1 `Sources/Engine/Layouts/LayoutInputsKey.swift` (baru)

```swift
import Foundation

/// Revision key for reusing the previous layout inputs.
struct LayoutInputsKey {
    let dom: ObjectIdentifier
    let domRevision: UInt64
    let imageRevision: UInt64
    let styleRevision: UInt64
}
```

### 5.1b `Sources/Engine/Style/StyleRevision.swift` (baru)

```swift
import Foundation

/// Monotonic epoch for computed-style writes.
@MainActor
enum StyleRevision {
    private(set) static var epoch: UInt64 = 0

    static func bump() {
        epoch &+= 1
    }
}
```

`StyleFields` memanggil `StyleRevision.bump()` di setiap tempat yang menaikkan
`revision`: `applyValues`, `reapplyInherited`, `set`, dan `mutate`. Epoch ini
membuat fast path aman untuk mutasi style langsung (animasi, tool, tes) yang
tidak melalui style pass.

### 5.2 `Sources/Engine/Layouts/LayoutInputsBuilder.swift`

```diff
 @MainActor
 enum LayoutInputsBuilder {
     static func build(dom: DOMTree) -> LayoutInputs {
-        var nodes: [LayoutInput?] = []
+        return build(dom: dom, previous: nil, key: nil)
+    }
+
+    static func build(
+        dom: DOMTree,
+        previous: LayoutInputs?,
+        key: LayoutInputsKey?
+    ) -> LayoutInputs {
+        let reusable: LayoutInputs?
+        if let key: LayoutInputsKey = key,
+            key.dom == ObjectIdentifier(dom),
+            key.domRevision == dom.revision,
+            key.imageRevision == dom.side.images.revision
+        {
+            reusable = previous
+        } else {
+            reusable = nil
+        }
+        var nodes: [LayoutInput?] = reusable?.nodes ?? []
         var styleChanges: [NodeID: Set<StyleProperty>] = [:]
         dom.forEachNode { id in
             guard let node: DOMNode = dom.node(id) else { return }
             while nodes.count <= Int(id.raw) { nodes.append(nil) }
+            let revision: UInt64 = node.base.style.revision
+            let old: LayoutInput? = reusable?.input(id)
+            if let old, old.style.revision == revision {
+                if node.text == nil {
+                    profiler.count("layout.inputs.reused")
+                    return
+                }
+                if let parent: NodeID = node.base.parent,
+                    let parentNode: DOMNode = dom.node(parent),
+                    old.style.font == parentNode.base.style.computed.text.font
+                {
+                    profiler.count("layout.inputs.reused")
+                    return
+                }
+            }
+            let changes: Set<StyleProperty> = node.base.style.takeLayoutChanges()
+            if !changes.isEmpty { styleChanges[id] = changes }
+            let font: TextStyle.Font
+            if node.text != nil, let parent: NodeID = node.base.parent,
+                let parentNode: DOMNode = dom.node(parent)
+            {
+                font = parentNode.base.style.computed.text.font
+            } else {
+                font = node.base.style.computed.text.font
+            }
+            if let old {
+                var updated: LayoutInput = old
+                updated.style = LayoutInputStyle(
+                    computed: node.base.style.computed,
+                    font: font,
+                    revision: revision
+                )
+                nodes[Int(id.raw)] = updated
+                profiler.count("layout.inputs.style")
+                return
+            }
+            profiler.count("layout.inputs.rebuilt")
             let element: ElementData? = node.element
             let ref: DOMRef = dom.ref(id)
             let elementRef: ElementRef? = ref.element
-            let changes: Set<StyleProperty> = node.base.style.takeLayoutChanges()
-            if !changes.isEmpty { styleChanges[id] = changes }
             nodes[Int(id.raw)] = LayoutInput(
@@
                 style: LayoutInputStyle(
                     computed: node.base.style.computed,
-                    font: ref.inheritedStyleOwner.style.computed.text.font,
+                    font: font,
                     revision: node.base.style.revision
                 ),
```

Saat kunci cocok, `node`, `content`, dan `media` tidak mungkin berubah karena
DOM revision dan image revision sama. Jadi node dengan style berubah hanya
mengganti `style` field; atribut, children, dan gambar tidak disalin ulang.
`layout.inputs.style` mencatat jalur ini.

### 5.3 `LayoutTree.swift` + `DocumentLayoutPass.swift` — clear setelah layout

```diff
@@ Sources/Engine/Layouts/LayoutTree.swift
     /// Marks the layout fields that read one DOM node's changed style properties.
     mutating func consumeStyleChanges(for node: NodeID) {
         for property in inputs.styleChanges(node) {
             markDependents(of: .style(node, property))
         }
     }
+
+    mutating func clearStyleChanges() {
+        source.inputs.styleChanges.removeAll(keepingCapacity: true)
+    }
```

```diff
@@ Sources/Engine/Layouts/DocumentLayoutPass.swift
         profiler.measure("layout.dependencies.consumeStyleChanges", {
             consumeStyleChanges()
         })
+        defer {
+            clearStyleChanges()
+        }
         guard documentLayoutNeeded(root) else { return }
```

`styleChanges` tidak boleh dibuang di `consumeStyleChanges()`. Layout masih
membacanya setelah itu, terutama `canRefreshFontsOnly` untuk memilih reuse
inline item. Kalau dibuang terlalu awal, semua inline item dibangun ulang;
trace GUI menunjukkan `inline.place` melonjak dari 43–49 ms ke 133–142 ms.
Clear dilakukan di akhir `layoutDocument`, setelah semua pembaca selesai.
Ini juga mencegah layout redundan memutar perubahan yang sama
(`LayoutIdempotenceTests`).

### 5.4 `Sources/Engine/Core/Frame.swift` — build sekali per pass

```diff
     private var styleSnapshotCache: StyleSnapshot?
     private var styleSnapshotRevision: UInt64 = .max
+    private var layoutInputsKey: LayoutInputsKey?
@@
         state.document.dom = newDOM
         styleSnapshotCache = nil
         styleSnapshotRevision = .max
+        layoutInputsKey = nil
@@
         if state.layout.tree.isDirty {
             browser?.measure.start("BrowserTab.layout")
             profiler.reset()
             defer { profiler.emitProfile(into: browser?.measure, named: "profile.layout") }
             defer { browser?.measure.stop("BrowserTab.layout") }
+            let previousInputs: LayoutInputs? = state.layout.tree.box?.tree.inputs
+            let canReuseInputs: Bool
+            if !stylesDirty, !viewportStyle,
+                let previousInputs,
+                previousInputs.styleChanges.isEmpty,
+                let key: LayoutInputsKey = layoutInputsKey,
+                key.dom == ObjectIdentifier(dom),
+                key.domRevision == dom.revision,
+                key.imageRevision == dom.side.images.revision,
+                key.styleRevision == StyleRevision.epoch
+            {
+                canReuseInputs = true
+                profiler.count("layout.inputs.reused", by: previousInputs.nodes.count)
+            } else {
+                canReuseInputs = false
+            }
+            let inputs: LayoutInputs = profiler.measure("layout.inputs.build", {
+                if canReuseInputs, let previousInputs {
+                    return previousInputs
+                }
+                return LayoutInputsBuilder.build(
+                    dom: dom,
+                    previous: previousInputs,
+                    key: layoutInputsKey
+                )
+            })
+            layoutInputsKey = LayoutInputsKey(
+                dom: ObjectIdentifier(dom),
+                domRevision: dom.revision,
+                imageRevision: dom.side.images.revision,
+                styleRevision: StyleRevision.epoch
+            )
             let box: LayoutBox
             if let existing = state.layout.tree.box, existing.tree.dom === dom,
                 browser?.forceFullLayout != true
             {
                 box = existing
             } else {
                 box = LayoutBox(LayoutTree(
                     dom: dom,
                     root: dom.root,
-                    inputs: LayoutInputsBuilder.build(dom: dom)
+                    inputs: inputs
                 ))
                 state.layout.targets.isValid = false
             }
             state.layout.tree.box = box
             dom.layoutBox = box
-            let inputs: LayoutInputs = profiler.measure("layout.inputs.build", {
-                LayoutInputsBuilder.build(dom: dom)
-            })
             box.tree.refreshInputs(inputs)
```

Efek tambahan: layout pertama tidak lagi membangun inputs dua kali
(`LayoutTree.init` dulu membangun sendiri, lalu `Frame` membangun lagi).

### 5.5 `Sources/Engine/Parsing/DOMSideTables.swift`

```diff
 struct ImageTable {
     var images: [NodeID: CGImage]
     var backgrounds: [NodeID: CGImage]
     var backgroundSources: [NodeID: String]
+    var revision: UInt64
 }
@@
     init() {
         self.images = [:]
         self.backgrounds = [:]
         self.backgroundSources = [:]
+        self.revision = 0
     }
 }
```

### 5.6 `Sources/Engine/Parsing/ElementRef.swift`

```diff
     var image: CGImage? {
         get { dom.side.images.images[id] }
-        nonmutating set { dom.side.images.images[id] = newValue }
+        nonmutating set {
+            dom.side.images.images[id] = newValue
+            dom.side.images.revision &+= 1
+        }
     }
```

Hanya `images` yang menaikkan revision. Background image tidak dibaca oleh
`LayoutInputs`, jadi tidak perlu membatalkan cache layout.

## 6. Tes

File baru `Tests/ToyStackTests/LayoutInputsCacheTests.swift`.

### 6.1 Width-only resize memakai input lama

1. Render halaman tanpa media query.
2. `setViewport(width: 500)` + `setNeedsViewportResize()`.
3. Render, periksa counter:
   - `layout.inputs.reused` > 0
   - `layout.inputs.rebuilt` tidak ada
   - geometri sama dengan hasil sebelum perubahan.

### 6.2 Style satu node hanya memperbarui field style

1. Ubah satu field style node secara langsung, lalu `setNeedsLayout`.
2. Render.
3. `layout.inputs.style` > 0, `layout.inputs.reused` > 0, dan
   `layout.inputs.rebuilt` tidak ada.
4. Warna elemen berubah.

### 6.3 Mutasi teks dan gambar membatalkan cache

1. `text.append(" more")` → DOM revision berubah → `layout.inputs.reused`
   tidak ada.
2. Set `img.image`, panggil `LayoutInvalidation.imageChanged`, render →
   `layout.inputs.reused` tidak ada.

### 6.4 Regresi perilaku

`swift test` penuh harus tetap lulus, termasuk `ViewportResizeTests`,
`LayoutOracleTests`, dan `LayoutDependencyTests`.

## 7. Verifikasi performa

Baseline headless debug, 15.005 node DOM, lebar 800 → 700 (tanpa media flip)
dan 800 → 400 (dengan `font-size` flip):

| Metrik | Sebelum | Sesudah | Perubahan |
|---|---:|---:|---:|
| `layout.inputs.build` width-only | 36,5 ms | **0 ms** (fast path) | −100% |
| `layout.inputs.build` breakpoint | 40,7 ms | **32,6 ms** | −20% |
| `layout.inputs.reused` width-only | — | 15.005 node | semua node |
| `layout.inputs.style` breakpoint | — | 15.001 node | hanya style field |

Fast path melewati builder sepenuhnya bila DOM, gambar, dan style tidak
berubah. Build tetap berjalan untuk style flip, mutasi DOM, gambar, dan
animasi.

Angka absolut ini dari build **debug**. Angka GUI dari trace terakhir:

| Rezim | `layout.inputs.build` sebelum fast path |
|---|---:|
| Width-only | 12,7–25,0 ms |
| Breakpoint | 13,4–15,7 ms |

| Rezim | `layout.inputs.build` setelah fast path (GUI) |
|---|---:|
| Width-only | **0 ms** |
| Breakpoint | 11,1–14,3 ms |

Fast path baru ditambahkan setelah trace itu. Trace GUI berikutnya
mengonfirmasi `layout.inputs.build` width-only = **0 ms** dengan
`layout.inputs.reused` = 14.995. Breakpoint tetap membayar builder
11,1–14,3 ms karena 5.501 node berubah style.

## 8. Risiko

- Cache salah invalidasi membuat teks, gambar, atau style basi. Kunci harus
  mencakup DOM identity+revision, image revision, dan style revision per node.
- Reuse melewati `takeLayoutChanges()` untuk node yang revision-nya sama.
  Itu aman karena setiap penulisan style yang mengisi `layoutChanges` juga
  menaikkan `StyleFields.revision`. Invariant ini harus dipertahankan.
- Font text node tidak mengikuti `StyleFields.revision` saat parent dianimasikan
  langsung; karena itu `font` parent tetap dibandingkan sebelum reuse.
- Node yang berubah style tetapi nilai computed-nya sama tetap memperbarui
  `style` field. Itu aman, hanya sedikit lebih mahal.
- Langkah ini tidak menyentuh `inline.place` 43–49 ms. Itu tetap target
  berikutnya.

## 9. Trace GUI setelah input reuse

Trace: 20.972 event, 14 layout pass, 1.773 layout node per reflow.

| Rezim | Frame | `inputs.build` | `reused` | `style` |
|---|---:|---:|---:|---:|
| Width-only | 73, 75, 77, 81, 85, 87, 89 | 8,3–20,4 ms | 14.995 | — |
| Style-only | 69, 71, 79, 83 | 12,7–14,5 ms | 9.494 | 5.501 |

Jadi reuse bekerja di GUI: node yang tidak berubah tidak membangun ulang
`LayoutInput`.

### Regresi yang ditemukan

Frame style-only menunjukkan `layout.inline.items.rebuilt` = **10.343** dan
`layout.inline.place` **133–142 ms**, padahal trace sebelumnya 43–49 ms.
Penyebabnya: `styleChanges` dibuang di `consumeStyleChanges()`, padahal
`canRefreshFontsOnly` membacanya setelah itu. Akibatnya semua inline item
dibangun ulang, bukan dipakai ulang.

Perbaikan: `clearStyleChanges()` dipindah ke akhir `layoutDocument`, setelah
semua pembaca selesai. Smoke test headless setelah perbaikan:

| Metrik | Sebelum perbaikan | Sesudah perbaikan |
|---|---:|---:|
| `inline.items.reused` pada font flip | — | 30.000 |
| `inline.place` (debug) | 480 ms | 490 ms |

Jadi jalur reuse inline kembali seperti baseline, bukan regresi. Trace GUI
berikutnya harus menunjukkan `inline.items.reused` > 0 dan `inline.place`
kembali ke kisaran 43–49 ms.

### Trace GUI ketiga (setelah clear dipindah)

Trace: 9.439 event, 11 layout pass, 1.773 layout node per reflow.

| Rezim | Frame | `inputs.build` | `reused` | `style` | `inline.items.reused` | `inline.place` |
|---|---:|---:|---:|---:|---:|---:|
| Width-only | 89, 95, 97, 103, 105 | 12,7–25,0 ms | 14.995 | — | — | 0,5–52 ms |
| Style-only | 91, 93, 99, 101 | 13,4–15,7 ms | 9.494 | 5.501 | 10.343 | 51–60 ms |

Regresi inline sudah hilang: `inline.items.rebuilt` tidak ada, `inline.items.reused`
10.343, dan `inline.place` kembali ke 51–60 ms (sebelumnya 133–142 ms).

`inputs.build` width-only masih 12,7–25,0 ms karena fast path belum ada pada
trace ini. Fast path kemudian ditambahkan dan diukur headless: 0 ms untuk
width-only, 32,6 ms untuk breakpoint (debug). Perlu satu trace GUI lagi untuk
mengonfirmasi angka release.

### Trace GUI keempat (fast path aktif)

Trace: 12.679 event, 19 layout pass, 1.773 layout node per reflow.

| Rezim | Frame | `inputs.build` | `reused` | `style` | `inline.items.reused` | `inline.place` |
|---|---:|---:|---:|---:|---:|---:|
| Width-only | 84, 86, 90, 94, 96, 100, 104, 108 | **0 ms** | 14.995 | — | — | 1,9–58,2 ms |
| Style-only | 80, 88, 98, 102, 106, 110, 112, 114 | 11,1–14,3 ms | 9.494 | 5.501 | 10.343 | 35,6–57,7 ms |

Fast path bekerja di GUI. Width-only tidak lagi membangun input sama sekali.
Style-only tetap membangun 5.501 field style; ini yang tersisa dari langkah 1.

Biaya frame setelah langkah 1:

| Rezim | Layout | Style | AnimFrame |
|---|---:|---:|---:|
| Width-only | 44–122 ms | 0 ms | 44–122 ms |
| Style-only | 141–171 ms | 29,6–44,9 ms | 182–215 ms |

Inline item tidak dibangun ulang, tetapi `inline.place` masih 35–58 ms dan
`layout.visit` 60–93 ms. Bottleneck berikutnya tetap inline placement, bukan
input building.

## 10. Langkah 2 — reuse baris

Implementasi ada di `BlockLayoutPass.swift`.

### 10.1 Desain

Saat width berubah dan line plan berubah, `inlineTextLinePlan` sudah tahu
rentang item untuk setiap baris. `placeInlineItems(id, plan:oldPlan:)` memakai
rentang itu:

1. Setiap baris lama dipetakan dari rentang item ke `LayoutID`.
2. Baris baru dengan rentang item yang sama memakai baris lama apa adanya:
   `resetLine` menandai field, `setLineChildrenField` mempertahankan children
   dan dependency `previous`.
3. Baris yang rentangnya berubah dibangun ulang dari rentang baru.
   `appendToLine` dipanggil langsung; line breaking tidak dihitung ulang
   karena plan sudah menentukannya.
4. Baris lama yang tidak dipakai masuk pool untuk baris baru.

Jalur ini hanya dipakai bila `inlineContentChanged == false`. Saat font atau
item berubah, jalur lama tetap dipakai karena text object harus diperbarui.

### 10.2 Counter dan tes

Counter baru: `layout.inline.place.reusedLines` dan
`layout.inline.place.rebuiltLines`.

Tes baru: `ViewportResizeTests.widthResizeReusesUnchangedLinePrefix`.
Halaman memakai `<br>` sehingga baris pertama tidak berubah saat lebar turun;
tes memastikan line ID pertama tetap, reusedLines > 0, rebuiltLines > 0, dan
hasil incremental sama dengan full layout.

### 10.3 Hasil

Benchmark headless debug: satu paragraf 3.000 kata, lebar 800 → 760.

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `inline.place` | 52,9 ms | **46,9 ms** |
| `reusedLines` | — | 1 |
| `rebuiltLines` | — | 187 |
| `text.append` | 5,4 ms | tidak ada (langsung append) |

Pada perubahan lebar kecil ini line break bergeser di hampir semua baris,
jadi hanya 1 baris yang benar-benar dipakai ulang. Keuntungan utama datang
dari tidak menghitung ulang line breaking: `placeText` dilewati untuk baris
yang dibangun ulang. Pada halaman dengan prefix baris stabil, `reusedLines`
akan lebih besar.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 2

Trace: 12.911 event, 15 layout pass.

| Rezim | Frame | `inputs.build` | `reusedLines` | `rebuiltLines` | `inline.place` |
|---|---:|---:|---:|---:|---:|
| Width-only | 98, 104, 106, 124, 134 | 0 ms (kecuali 98) | 2–17 | 34–852 | 27–49 ms |
| Style-only | 100, 102, 120, 122, 126, 128, 130, 132 | 8,2–15,3 ms | — | — | 48–65 ms |

Pada width-only, reuse baris aktif. Jumlahnya kecil karena line break bergeser
di banyak baris. Pada style-only, jalur lama tetap dipakai (`inlineContentChanged`),
jadi `reusedLines` tidak muncul dan inline item tetap reuse 10.343.

Biaya frame:

| Rezim | Layout | Style | AnimFrame |
|---|---:|---:|---:|
| Width-only | 56–133 ms | 0 ms | 56–133 ms |
| Style-only | 148–176 ms | 17–46 ms | 166–219 ms |

Kesimpulan: langkah 2 mengurangi pekerjaan line placement pada width-only,
tetapi belum mengubah gambaran besar. Bottleneck berikutnya adalah style pass
saat font flip dan `layout.visit`/inline placement pada blok besar.

## 11. Langkah 3 — ukuran teks tidak diukur dua kali

Saat `font-size` berubah, `inlineTextLinePlan` sudah mengukur setiap word untuk
memutuskan line break. `TextLayoutPass` lalu mengukur word yang sama lagi untuk
mengisi metrics text node. Itu sebabnya `text.measureCalls` = 20.672
(10.336 word × 2).

Perubahan:

- `TextMetrics` mendapat flag `measured`.
- `appendToLine` menyalin `InlineTextItem.measuredWidth` ke `TextData.metrics`
  saat text node dibuat atau dipakai ulang.
- `TextLayoutPass.layoutText` memakai `metrics.width` bila `measured`, dan hanya
  memanggil `BrowserFont.measure` bila belum ada.
- Counter baru `text.measureReused`.

### Hasil headless debug

Halaman 5.000 blok, breakpoint mengubah `body font-size`:

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `text.measureCalls` | 60.000 | **30.000** |
| `text.measureReused` | — | 30.000 |
| `text.measure` (miss) | 27,8 ms | 23,5 ms |
| `layout.text` | 215,4 ms | **191,9 ms** |

Panggilan ukur turun setengah dan `layout.text` turun sekitar 11%.
`text.measure` hanya menghitung cache miss; sisa biaya ada di set metrics dan
field update, bukan pengukuran font.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 3

Trace: 14.910 event.

| Rezim | Frame | `text.measureCalls` | `text.measureReused` | `text.measure` | `layout.text` |
|---|---:|---:|---:|---:|---:|
| Style-only | 86, 93, 99, 103, 105, 107, 109, 113, 119, 123 | 10.336 | 10.336 | 0–9,1 ms | 13,4–14,8 ms |
| Width-only | 82, 84, 91, 95, 97, 101, 111, 115, 117, 121 | 11 | — | — | — |

Panggilan ukur teks turun dari 20.672 menjadi 10.336 pada setiap font flip.
`text.measureReused` = 10.336. Hanya frame pertama yang membayar miss
(9,1 ms); frame berikutnya memakai cache font.

`layout.text` turun dari 16,4–16,8 ms ke 13,4–14,8 ms.

Biaya frame setelah langkah 3:

| Rezim | Style | Layout | AnimFrame |
|---|---:|---:|---:|
| Width-only | 0 ms | 50–110 ms | 51–115 ms |
| Style-only | 23,2–30,0 ms | 140,8–179,4 ms | 170,4–205,3 ms |

Sisa bottleneck: `inline.place` 38–70 ms pada style-only dan 4–52 ms pada
width-only, plus dependency/field updates.

## 12. Langkah 4 — churn field dan dependency

Perubahan yang dipakai:

- `consumeStyleChanges` tidak lagi memindai semua `inputs.nodes`. Kunci
  `inputs.styleChanges` langsung dipakai karena dictionary itu sudah hanya
  berisi node yang berubah.

Perubahan yang dicoba lalu dicabut:

- `markUsed`, `markClean`, `markField`, `markAncestorsDirty`, dan
  `setDirtyDescendants` sempat diubah untuk memutasi `nodes[id]` langsung.
  Di build debug ini terlihat jauh lebih cepat, tetapi trace GUI release
  menunjukkan regresi:
  `styleChanges.mark` 6,2–6,8 ms → 9,0–9,4 ms dan `consumeStyleChanges`
  7,5–8,4 ms → 9,4–9,8 ms. Salinan `LayoutNode` dioptimalkan compiler release,
  sementara optional chaining berulang menambah biaya. Perubahan itu dicabut.

### Hasil GUI

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `layout.styleChanges.scan` | 1,26 ms | **0,01 ms** |

Sisa biaya langkah 4 kecil: sekitar 1,25 ms per style flip. `field.mark/set`
tidak berubah dan `line.children.deps` masih 13–16 ms pada font flip.

`swift test`: **234 tes / 39 suite lulus**.

## 13. Langkah 5 — instrumentasi orkestrasi layout

Span baru:

| Span | Cakupan |
|---|---|
| `layout.prepare` | pilih/buat box, set `dom.layoutBox`, `refreshInputs` |
| `layout.document` | seluruh `layoutDocument` |
| `layout.document.needed` | `documentLayoutNeeded(root)` |
| `layout.document.root` | field root, child root, tinggi root |
| `layout.document.child` | panggilan `layout(child)` |
| `layout.visit.children` | loop child di dalam block |

### Hasil headless debug

Halaman 5.000 blok, resize 800 → 700 → 400:

| Metrik | Frame 3 (width-only) | Frame 5 (font flip) |
|---|---:|---:|
| `layout.inputs.build` | 0 ms | 33,4 ms |
| `layout.prepare` | 0 ms | 0 ms |
| `layout.document` | 610,2 ms | 2.136,1 ms |
| `layout.document.child` | 610,2 ms | 2.062,3 ms |
| `layout.visit` (jumlah) | 288,9 ms | 1.190,4 ms |
| `layout.height` | 50,7 ms | 53,4 ms |
| `layout.sweep` | 41,6 ms | 41,3 ms |
| `consumeStyleChanges` | 0 ms | 73,8 ms |

`layout.visit.children` bernilai lebih besar dari `layout.document` karena span
itu bersarang: parent mencakup child. Jangan menjumlahkannya. Di trace viewer,
bandingkan `layout.document.child` dengan `layout.visit` pada level yang sama.

Sisa selisih `layout.document.child` vs `layout.visit` adalah pemanggilan
rekursif, dispatch `layout(id)`, guard per node, dan `layout.height`. Instrumentasi
ini membuat bagian itu terlihat, tetapi belum menghilangkannya.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 5

Trace: 11.300 event.

| Metrik | Width-only (74) | Font flip (78) |
|---|---:|---:|
| `layout.inputs.build` | 17,2 ms | 10,9 ms |
| `layout.prepare` | 0,1 ms | 0,8 ms |
| `layout.document` | 92,1 ms | 168,2 ms |
| `layout.document.child` | 92,1 ms | 160,8 ms |
| `layout.visit` (jumlah span) | 57,7 ms | 108,1 ms |
| `layout.height` | 1,1 ms | 1,0 ms |
| `layout.sweep` | 2,7 ms | 2,6 ms |
| `consumeStyleChanges` | 0 ms | 7,3 ms |
| `BrowserTab.layout` | 112,1 ms | 182,6 ms |

Selisih `layout.document.child` − `layout.visit`:

- Width-only: **34,4 ms**
- Font flip: **52,7 ms**

Setelah dikurangi `layout.height` (~1 ms), `layout.sweep` (~2,6 ms), dan
`consumeStyleChanges` (7,3 ms pada font flip), sisa 30–45 ms adalah biaya
rekursi `layout(id)`, dispatch `kind(id)`, dan guard per node. Bukan
orkestrasi `layoutDocument` yang belum terukur.

Jadi langkah 5 selesai: gap 70–80 ms sekarang bisa dipecah. Optimasi berikutnya
harus menyasar biaya per-node/recursion, atau memindahkan layout dari main
thread.

## 14. Percobaan dispatch ringan (ditolak)

Dicoba:

- `LayoutKindTag` untuk menghindari `switch kind(id)` yang menyalin node.
- Akses langsung `nodes[id]?.state.fields` dan `nodes[id]?.links` untuk
  mengurangi salinan `LayoutNode` di guard dan traversal.
- Guard per kind memakai `fields(id)`.

Hasil release headless, halaman 5.000 blok:

| Metrik | Baseline | Percobaan |
|---|---:|---:|
| `layout.document` width-only | 114,6 ms | **124,1 ms** |
| `layout.visit` width-only | 61,5 ms | **67,5 ms** |
| `layout.document` font flip | 459,6 ms | **494,5 ms** |
| `layout.visit` font flip | 267,9 ms | **290,1 ms** |

Perubahan ini konsisten lebih lambat sekitar 7–8%. Method accessor tambahan
tidak inline di build release, sementara salinan `LayoutNode` sudah dioptimalkan
compiler. Semua perubahan dicabut.

Kesimpulan: biaya dispatch tidak bisa diturunkan hanya dengan membungkus akses
node. Perlu perubahan struktur traversal (misalnya batch per kind atau skip
subtree bersih), atau memindahkan layout dari main thread.

## 15. Langkah 6 — dependency baris saat inline placement

Target: `inline.place.lineChildren` dan `line.children.deps`.

Perubahan di `setLineChildrenField`:

- `setChildren` tidak ditulis ulang bila children sama dan tidak ada
  reparent.
- Edge ascent/descent diganti dengan satu `replaceDependent` per field,
  bukan loop `removeEdge`/`add` per child.
- Pemeriksaan `contains` O(n²) hilang.

Hasil release headless, halaman 5.000 blok:

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `inline.place` frame load | 515,0 ms | **477,0 ms** |
| `inline.place` font flip | 125,8 ms | **118,7 ms** |
| `inline.place.lineChildren` load | 43,9 ms | **36,8 ms** |
| `inline.place.lineChildren` font flip | 11,6 ms | **3,0 ms** |
| `line.children.write` load | 7,4 ms | **4,8 ms** |

Width-only tidak berubah berarti (114,6 → 113,5 ms). Dokumen font flip
459,6 → 467,5 ms pada satu run; inline.place turun 7,1 ms, sisanya variasi
antarbagian.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 6

Trace: 12.485 event.

| Rezim | Frame | `inline.place` | `lineChildren` | `line.children.deps` | `write` | `reindex` |
|---|---:|---:|---:|---:|---:|---:|
| Style-only | 54, 58, 80, 82 | 55–65 ms | 19,8–25,1 ms | 10,2–13,6 ms | 1,7–2,1 ms | 5,7–6,3 ms |
| Width-only | 50, 60, 62, 84 | 34–43 ms | 25,9–30,8 ms | 12,2–16,2 ms | 2,2–2,5 ms | 7,6–9,4 ms |

Perubahan memberi efek kecil tetapi konsisten pada `line.children.write`
(sebelumnya 2,4–2,9 ms). `line.children.deps` dan `inline.place` hampir sama
karena jumlah baris dan line break di halaman GUI berbeda dari benchmark
headless.

`layout.line.place` tetap 14–16 ms. Ini kandidat berikutnya, bersama
posisi child per baris.

## 16. Langkah 7 — tulis frame baris sekali

`layoutLine` menulis zoom, width, x, dan y lewat empat `setField`, masing-masing
menyalin node dan menandai field. Diganti dengan satu `setFrame` yang menulis
keempat field dalam satu salinan node; `setBlockFrame` digeneralisasi menjadi
`setFrame` karena bentuknya sama.

Hasil release headless:

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `layout.document` width-only | 113,5 ms | **97,5 ms** |
| `layout.document` font flip | 467,5 ms | **437,7 ms** |
| `layout.line.place` width-only | — | — |
| `layout.line.place` font flip | 52,4 ms | 52,6 ms |
| `field.set` count | 274.998 | 274.998 |

`line.place` sendiri tidak berubah; keuntungannya ada di biaya penulisan field
per baris. `field.set` count tetap sama karena jumlah field yang berubah sama.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 7

Trace: 7.892 event.

| Rezim | Frame | `document` | `visit` | `line.place` | `inline.place` |
|---|---:|---:|---:|---:|---:|
| Style-only | 73, 75, 83, 85 | 135–157 ms | 85–104 ms | 14,2–17,5 ms | 55–71 ms |
| Width-only | 71, 77, 81 | 83–90 ms | 25–60 ms | 14,5–15,2 ms | 37–40 ms |

Perubahan `setFrame` memberi dokumen sekitar 5% lebih rendah pada style-only
dibanding trace sebelumnya (142–164 ms), tetapi `line.place` dan jumlah
`field.set/mark` tidak berubah. Efeknya kecil dan bercampur dengan variasi
antarbagian.

Tidak ada regresi yang terlihat. Langkah ini tetap disimpan karena mengurangi
penulisan node per baris, tetapi bukan pengungkit besar.

## 17. Langkah 8 — satu tulisan untuk font dan metrics teks

Saat text object dipakai ulang, `appendToLine` memanggil `setFontAndPrevious`
lalu `setTextMeasuredWidth`. Keduanya menyalin `LayoutNode` dan menulis node
yang sama. Digabung menjadi satu `setFontAndPrevious` dengan parameter
`measuredWidth`; metrics diubah dalam salinan node yang sama.

Hasil release headless:

| Metrik | Sebelum | Sesudah |
|---|---:|---:|
| `document` frame load | 1.084,9 ms | **1.053,2 ms** |
| `inline.place` font flip | 118,8 ms | **110,1 ms** |
| `text.append` font flip | 63,9 ms | **55,5 ms** |
| `layout.text` font flip | 44,4 ms | **41,9 ms** |
| `field.set` count | 274.998 | 274.998 |

Width-only tidak berubah berarti karena tidak ada penempatan teks.

`swift test`: **234 tes / 39 suite lulus**.

### Trace GUI langkah 8

Trace: 15.838 event.

| Rezim | Frame | `inline.place` | `text.append` | `layout.text` | `document` |
|---|---:|---:|---:|---:|---:|
| Style-only | 87, 89, 97, 99, 107, 109, 115 | 53–69 ms | 19,5–19,9 ms (10.336 panggilan) | 14,0–14,6 ms | 135–156 ms |
| Width-only | 85, 91, 93, 95, 101, 103, 105, 111, 113 | 26–42 ms | ~0,02 ms | — | 73–91 ms |

`text.append` turun dari sekitar 22,6 ms menjadi **19,5–19,9 ms** pada font flip.
`inline.place` sedikit turun; `layout.text` dan `document` hampir sama.
Width-only tidak berubah karena tidak menempatkan text.

Tidak ada regresi.
