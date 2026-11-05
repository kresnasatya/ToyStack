# Batasi Style Pass Viewport

Tanggal: 2026-11-05
Sumber: `plans/resize-flow-trace-2026-11-05.md`, `browser.trace` di HEAD, dan kode
`Sources/Engine/Core/Frame.swift`.

## 1. Temuan ulang: scope sudah ada, tapi masih ada jalan keluar ke seluruh dokumen

Klaim "media query flip menandai seluruh dokumen" tidak lagi benar untuk kasus
normal di HEAD. Kode sudah punya `scopedStyleScope` (`Frame.swift:1964`):
hanya rule di balik query yang berubah yang dicocokkan, node yang cocok ditandai,
lalu `applyStyle` hanya meneruskan subtree selama ada nilai inherited yang berubah.

Trace `browser.trace` di HEAD membuktikannya pada frame viewport:

| Frame | `style.scope.used` | `style.scope.rules` | `style.scope.direct` | `style.applied` | Style |
|---:|---:|---:|---:|---:|---:|
| 115 | 1 | 1 | 1 | 5.501 | 31,5 ms |
| 117 | 1 | 1 | 1 | 5.501 | 30,4 ms |
| 123 | 1 | 1 | 1 | 5.501 | 34,0 ms |
| 125 | 1 | 1 | 1 | 5.501 | 29,8 ms |

Jadi 30 ms itu **bukan** cascade seluruh dokumen. Satu node langsung berubah
`font-size`, lalu 5.501 descendant benar-benar mewarisi nilai baru. Itu pekerjaan
yang memang dibutuhkan.

Yang masih bocor ke seluruh dokumen adalah **fallback**:

1. `guard rules.count <= 64 else { return (nil, nil) }` (`Frame.swift:1975`).
   Begitu satu breakpoint berisi lebih dari 64 rule, scope dibuang dan
   `render` memanggil `StyleInvalidation.markDocument(nodes)` (`Frame.swift:826`).
   Ini yang perlu dihilangkan: batas 64 bukan aturan CSS, hanya batas biaya
   pencocokan linear.
2. `hasBaseline == false` juga menghasilkan `scope == nil`. Baseline hilang hanya
   bila belum pernah ada style pass, tetapi tetap lebih aman tidak pernah
   menandai dokumen dari jalur viewport.
3. Bug campuran: bila pass viewport berjalan bersama invalidasi lain dan scope
   kosong, `if scope?.isEmpty != true` melewati `applyStyle` seluruhnya. Node yang
   kotor karena invalidasi lain jadi tidak pernah di-restyle.

## 2. Definisi "subtree yang benar-benar terpengaruh"

Untuk satu viewport pass:

1. Rule yang media query-nya berubah adalah satu-satunya rule yang perlu diuji.
2. Node yang selector-nya cocok dengan rule itu adalah **direct**.
3. Descendant hanya ikut bila nilai inherited benar-benar berubah. Ini sudah
   ditangani `applyStyle` lewat `reapplyInherited` (`ApplyStyle.swift:43`).

Jadi target perubahan hanya menyentuh jalur 1–2: cari direct match tanpa
menguji semua rule pada semua node, dan jangan pernah jatuh ke "tandai semua".

## 3. Keputusan desain

**Option A — index rule berdasarkan `SelectorKey` (direkomendasikan).**
Rule di balik query yang berubah dikelompokkan per tag/class/id/universal.
Setiap node hanya menguji rule yang mungkin cocok. Batas 64 hilang, dan biaya
tetap sebanding dengan jumlah rule × kandidat, bukan rule × seluruh dokumen.
Untuk <=8 rule, pencocokan linear lebih murah daripada biaya hash bucket, jadi
jalur itu dipertahankan. Bucket dipakai begitu jumlah rule melewati 8.

- Trade-off: satu tipe baru (`ScopedStyleMatcher`), satu file baru, dan dua
  jalur pencocokan dengan ambang tetap.
- Keuntungan: menghapus fallback penuh, tetap sederhana, tidak menambah cache
  yang harus diinvalidate.

**Option B — cache `Set<NodeID>` per media query.**
Pass viewport pertama tetap memindai dokumen, pass berikutnya memakai cache.
Lebih cepat untuk drag bolak-balik melewati breakpoint yang sama, tetapi
menambah state, invalidasi DOM/rules, dan memori.

Rekomendasi: **A**. Cache (B) hanya masuk akal kalau trace berikutnya masih
menunjukkan `style.scope.walk` dominan. Di trace sekarang walk 3,7 ms dari
31,5 ms style; apply 23 ms berasal dari inheritance yang nyata.

## 4. File yang berubah

| File | Perubahan |
|---|---|
| `Sources/Engine/Style/ScopedStyleMatcher.swift` (baru) | Bucket rule per `SelectorKey`, cari direct match. |
| `Sources/Engine/Core/Frame.swift` | Selalu pakai scope pada viewport pass; hapus `hasBaseline` dan `markDocument` fallback; jangan lewati node kotor lain. |
| `Tests/ToyStackTests/MediaStyleScopeTests.swift` (baru) | Regresi untuk 65 rule dalam satu breakpoint dan untuk pass campuran. |

## 5. Perubahan kode

### 5.1 `Sources/Engine/Style/ScopedStyleMatcher.swift` (baru)

```swift
import Foundation

/// Finds the nodes a viewport style pass must restyle.
///
/// A viewport pass only re-evaluates rules whose media query flipped. Matching
/// every rule against every node is quadratic, so rules are bucketed by the key
/// their selector ends with; a node tests only rules for its own tag, id,
/// classes, and the universal bucket.
struct ScopedStyleMatcher {
    private static let indexedThreshold: Int = 8

    private let selectors: [any CSSSelector]
    private let buckets: Buckets?

    init(selectors: [any CSSSelector]) {
        self.selectors = selectors
        guard selectors.count > Self.indexedThreshold else {
            self.buckets = nil
            return
        }
        var universal: [Int] = []
        var byTag: [String: [Int]] = [:]
        var byClass: [String: [Int]] = [:]
        var byID: [String: [Int]] = [:]
        for (index, selector) in selectors.enumerated() {
            switch selector.key {
            case .tag(let tag):
                byTag[tag, default: []].append(index)
            case .className(let name):
                byClass[name, default: []].append(index)
            case .id(let id):
                byID[id, default: []].append(index)
            case .universal:
                universal.append(index)
            }
        }
        self.buckets = Buckets(
            universal: universal,
            byTag: byTag,
            byClass: byClass,
            byID: byID
        )
    }

    func directMatches(in snapshot: StyleSnapshot) -> Set<NodeID> {
        var matches: Set<NodeID> = []
        collect(from: snapshot.root, snapshot: snapshot, into: &matches)
        return matches
    }

    private func collect(
        from index: Int,
        snapshot: StyleSnapshot,
        into matches: inout Set<NodeID>
    ) {
        guard let node: StyleNode = snapshot.nodes[index] else { return }
        if node.content.tag != nil,
            matchesAny(content: node.content, snapshot: snapshot, index: index)
        {
            matches.insert(node.identity.id)
        }
        for child in node.identity.children {
            collect(from: child, snapshot: snapshot, into: &matches)
        }
    }

    private func matchesAny(
        content: StyleContent,
        snapshot: StyleSnapshot,
        index: Int
    ) -> Bool {
        guard let buckets: Buckets = buckets else {
            for selector in selectors where selector.matches(snapshot, index) {
                return true
            }
            return false
        }
        return matchesIndexed(
            content: content,
            snapshot: snapshot,
            index: index,
            buckets: buckets
        )
    }

    private func matchesIndexed(
        content: StyleContent,
        snapshot: StyleSnapshot,
        index: Int,
        buckets: Buckets
    ) -> Bool {
        for ruleIndex in buckets.universal
        where selectors[ruleIndex].matches(snapshot, index) {
            return true
        }
        if let tag: String = content.tag {
            for ruleIndex in buckets.byTag[tag] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        if let id: String = content.attributes["id"] {
            for ruleIndex in buckets.byID[id] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        let classes: [Substring] = content.attributes["class"]?.split(separator: " ") ?? []
        for name in classes {
            for ruleIndex in buckets.byClass[String(name)] ?? []
            where selectors[ruleIndex].matches(snapshot, index) {
                return true
            }
        }
        return false
    }
}

// MARK: - Buckets

private struct Buckets {
    let universal: [Int]
    let byTag: [String: [Int]]
    let byClass: [String: [Int]]
    let byID: [String: [Int]]
}
```

### 5.2 `Sources/Engine/Core/Frame.swift` — render

```diff
             browser?.measure.start("BrowserTab.style.apply")
             let media: MediaFeatures = currentMedia()
-            let hasBaseline: Bool = !state.document.sheets.index.media.matches.isEmpty
             let flipped: Set<String> = flippedMediaQueries(media)
             recordMediaMatches(media)
             browser?.measure.start("BrowserTab.style.scope")
             let scoped: (scope: StyleScope?, snapshot: StyleSnapshot?) =
-                (reusableStyle && hasBaseline)
-                ? scopedStyleScope(flipped)
-                : (nil, nil)
+                reusableStyle ? scopedStyleScope(flipped) : (nil, nil)
             let scope: StyleScope? = scoped.scope
             profiler.count(scope == nil ? "style.scope.none" : "style.scope.used")
-            if viewportStyle, scope == nil {
-                StyleInvalidation.markDocument(nodes)
-            }
             browser?.measure.stop("BrowserTab.style.scope")
             profiler.count("style.flipped.queries", by: flipped.count)
             profiler.count("style.scope.direct", by: scope?.direct.count ?? 0)
             let cascade: StyleCascade = StyleCascade(
                 index: state.document.sheets.index.list.index,
                 media: media,
                 scope: scope
             )
-            if scope?.isEmpty != true {
+            if scope?.isEmpty != true || stylesDirty {
                 let snapshot: StyleSnapshot = scoped.snapshot ?? cachedStyleSnapshot()
                 applyStyle(node: nodes, cascade: cascade, snapshot: snapshot)
             }
```

Alasan baris terakhir: bila scope kosong tetapi ada node kotor dari invalidasi
lain, `applyStyle` tetap harus jalan. Dengan scope kosong, hanya node kotor
yang diproses; node bersih tetap dilewati.

### 5.3 `Sources/Engine/Core/Frame.swift` — `scopedStyleScope`

```diff
     private func scopedStyleScope(
         _ flipped: Set<String>
     ) -> (scope: StyleScope?, snapshot: StyleSnapshot?) {
-        var rules: [(selector: any CSSSelector, body: [String: String])] = []
+        var selectors: [any CSSSelector] = []
         for rule in state.document.sheets.index.list.sorted {
             guard let query: String = rule.0, flipped.contains(query) else { continue }
-            rules.append((rule.1, rule.2))
+            selectors.append(rule.1)
         }
-        profiler.count("style.scope.rules", by: rules.count)
-        guard !rules.isEmpty else { return (StyleScope(direct: []), nil) }
-        guard rules.count <= 64 else { return (nil, nil) } // NOTE: why 64?
+        profiler.count("style.scope.rules", by: selectors.count)
+        guard !selectors.isEmpty else { return (StyleScope(direct: []), nil) }
 
-        var direct: Set<NodeID> = []
         let snapshot: StyleSnapshot = profiler.measure("style.snapshot.scope", {
             cachedStyleSnapshot()
         })
-        profiler.measure("style.scope.walk", {
-            @MainActor func walk(_ index: Int) {
-                guard let node: StyleNode = snapshot.nodes[index] else { return }
-                if node.content.tag != nil {
-                    for rule in rules {
-                        if rule.selector.matches(snapshot, index) {
-                            StyleInvalidation.markNode(dom.ref(node.identity.id))
-                            direct.insert(node.identity.id)
-                            break
-                        }
-                    }
-                }
-                for child in node.identity.children {
-                    walk(child)
-                }
-            }
-            walk(snapshot.root)
+        let direct: Set<NodeID> = profiler.measure("style.scope.walk", {
+            let matches: Set<NodeID> = ScopedStyleMatcher(selectors: selectors)
+                .directMatches(in: snapshot)
+            for id in matches {
+                StyleInvalidation.markNode(dom.ref(id))
+            }
+            return matches
         })
         return (StyleScope(direct: direct), snapshot)
     }
```

Tidak ada lagi jalur `nil` untuk viewport pass. `StyleInvalidation.markDocument`
tetap dipakai untuk invalidasi non-viewport (`setNeedsRender`, stylesheet baru).

## 6. Tes

File baru `Tests/ToyStackTests/MediaStyleScopeTests.swift`.

### 6.1 Breakpoint dengan 65 rule

Halaman: 65 `div` kelas `k0`…`k64`, 50 `div` tanpa kelas, semuanya di dalam satu
container. CSS: satu `@media (min-width: 600px)` berisi 65 rule
`.k0 { color: red; }` … `.k64 { color: red; }`.

Langkah:

1. Render lebar 800 (query aktif). `.k0` berwarna merah.
2. `setViewport(width: 400)` + `setNeedsViewportResize()`.
3. `render()`.
4. Periksa counter:
   - `style.scope.used == 1`
   - `style.scope.none == nil`
   - `style.scope.rules == 65`
   - `style.scope.direct == 65`
   - `style.visited < total node`
5. `.k0` tidak lagi merah.

Sebelum perubahan ini, langkah 4 melihat `style.scope.none == 1` dan
`style.visited == total node`: tes gagal. Sesudahnya lulus.

### 6.2 Pass campuran tidak boleh kehilangan node kotor

Halaman: `<div id="target">target</div>` tanpa rule yang cocok dengan query
yang berubah. Query flip hanya berisi `.absent { color: red; }`.

Langkah:

1. Render awal lebar 800.
2. Set inline style `color: blue` pada `#target`, lalu `setNeedsStyle(target)`.
3. `setViewport(width: 400)` + `setNeedsViewportResize()`.
4. `render()`.
5. `#target` harus biru.

Sebelum perubahan, scope kosong membuat `applyStyle` dilewati dan tes gagal.

## 7. Verifikasi

```sh
swift test --filter MediaStyleScopeTests
swift test
```

Lalu ukur ulang di GUI:

1. Buka halaman panjang yang punya breakpoint lebar.
2. Drag melewati breakpoint beberapa kali.
3. Simpan `browser.trace` baru.

Yang harus terlihat di trace:

- `style.invalidate.viewport` tetap ada.
- `style.scope.used` ada; `style.scope.none` tidak muncul pada pass viewport.
- `style.scope.rules` boleh > 64 dan pass tetap scoped.
- `style.visited` jauh di bawah jumlah node saat query hanya mengenai sedikit
  node.
- Bila query mengenai satu container besar dan mengubah `font-size`,
  `style.applied` tetap besar. Itu inheritance nyata, bukan tanda fallback.

## 8. Hasil verifikasi

### 8.1 Tes regresi

`swift test --filter MediaStyleScopeTests` dijalankan dua kali:

| Kondisi | Hasil |
|---|---|
| `Frame.swift` dikembalikan ke HEAD (fix dicabut) | **gagal**, 5 issue: `style.scope.none` muncul, `style.scope.direct` 0, `visited` = 233 dari 233, dan node campuran tetap hitam. |
| Fix diterapkan | **lulus**, 2/2 tes. |

`swift test` penuh: **229 tes / 38 suite lulus**.

### 8.2 Smoke test headless

Halaman sementara: 265 `div` (65 dengan `.k0`…`.k64`, 200 `.plain`), satu
`@media (min-width: 600px)` berisi 65 rule, viewport 800 → 400.

```sh
.build/debug/ToyStackHeadless file:///tmp/viewport-scope-65.html \
  --trace /tmp/viewport-scope.trace --run-for 0.6 \
  --resize-at 0.25:400:600 --width 800 --height 600
```

Hasil pass viewport dari trace:

| Metrik | Nilai |
|---|---:|
| `style.scope.used` | 1 |
| `style.scope.none` | tidak ada |
| `style.scope.rules` | 65 |
| `style.scope.direct` | 65 |
| `style.visited` | 133 dari 800 node |
| `style.applied` | 130 |
| `style.scope.walk` | 1,1 ms |
| `style.traverse` | 3,1 ms (load awal: 21,6 ms) |

### 8.3 Yang masih perlu diukur di GUI

Trace ini berasal dari `ToyStackHeadless`, bukan drag manual. Setelah build GUI
baru, drag melewati breakpoint pada halaman panjang dan kirim `browser.trace`
terbaru. Yang dicari: tidak ada `style.scope.none` pada pass viewport, dan
`style.visited` jauh di bawah jumlah node bila query hanya mengenai sebagian
kecil dokumen.


## 9. Risiko dan batas

- Selector `[atribut]` dan `:has()` punya `SelectorKey.universal`, jadi tetap
  diuji pada setiap elemen. Itu sudah sama dengan `RuleIndex` sekarang; bukan
  regresi, tetapi bukan jalur tercepat.
- Rekursi mengikuti kedalaman DOM. Sama seperti `applyStyle` dan walk lama.
- Bila trace berikutnya menunjukkan `style.scope.walk` masih dominan, langkah
  lanjutan adalah cache per query (Option B), bukan menaikkan batas 64 lagi.
- Perubahan ini tidak menyentuh biaya layout 84–166 ms. Itu tetap penyebab
  utama frame konten lambat.

## 10. Trace GUI 2026-11-05

Trace baru: 16.297 event, 24 style pass, 4 di antaranya pass viewport.

| Frame | `scope.used` | `scope.none` | `rules` | `direct` | `visited` | `applied` | Style | Layout |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 114 | 1 | — | 1 | 1 | 5.630 | 5.501 | 31,0 ms | 173,1 ms |
| 116 | 1 | — | 1 | 1 | 5.630 | 5.501 | 32,6 ms | 155,7 ms |
| 126 | 1 | — | 1 | 1 | 5.630 | 5.501 | 29,0 ms | 160,0 ms |
| 128 | 1 | — | 1 | 1 | 5.630 | 5.501 | 30,2 ms | 161,2 ms |

Kesimpulan dari trace:

- **Tidak ada `style.scope.none` pada pass viewport.** Media flip tidak lagi
  menandai seluruh dokumen.
- 5.630 node dikunjungi karena 5.501 di antaranya benar-benar berubah
  `font-size` lewat inheritance. `reapplyInherited` 6,7 ms dan `traverse`
  20,5 ms adalah pekerjaan nyata, bukan fallback.
- `style.scope.walk` masih 4,8–6,3 ms karena trace ini dibuat dengan versi
  matcher yang selalu memakai bucket. Jalur linear untuk <=8 rule baru
  ditambahkan setelah trace ini. Smoke test 15.005 node dengan satu rule
  mengukur walk **4,5 ms**, jadi sekitar 1–2 ms lebih murah daripada 6,3 ms di
  trace GUI.
- Style pass 29–32,6 ms hanya 15–17% dari frame viewport. Layout tetap
  156–173 ms, jadi bottleneck berikutnya tetap layout, bukan style.
- Jarak antar-frame konten saat drag 108–212 ms. Target smooth belum tercapai,
  tetapi bukan karena style pass viewport.

### Trace GUI kedua (setelah jalur linear)

Trace berikutnya: 10.906 event, 24 style pass, 4 pass viewport.

| Frame | `scope.used` | `scope.none` | `rules` | `direct` | `visited` | `applied` | Walk | Style | Layout |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 80 | 1 | — | 1 | 1 | 5.630 | 5.501 | 2,8 ms | 28,8 ms | 160,9 ms |
| 84 | 1 | — | 1 | 1 | 5.630 | 5.501 | 3,2 ms | 33,2 ms | 155,0 ms |
| 90 | 1 | — | 1 | 1 | 5.630 | 5.501 | 3,1 ms | 30,1 ms | 156,2 ms |
| 137 | 1 | — | 1 | 1 | 5.630 | 5.501 | 3,1 ms | 30,2 ms | 156,8 ms |

Perbandingan `style.scope.walk` antara dua trace GUI:

| Kondisi | Walk |
|---|---:|
| Matcher bucket untuk 1 rule (trace pertama) | 4,8–6,3 ms |
| Jalur linear baru (trace kedua) | **2,8–3,2 ms** |

Jadi pemilihan jalur linear bekerja di GUI: sekitar 2–3 ms lebih murah per
pass viewport. Tidak ada `style.scope.none` pada pass viewport di kedua trace.

Efeknya pada frame tetap kecil karena layout 155–161 ms. Di frame viewport,
`layout.visit` 79–85 ms, `inline.place` 43–49 ms, `inputs.build` 9–10 ms,
`styleChanges` 6–8 ms, dan `text` 18 ms. Jarak antar-frame konten 108–216 ms.
Bottleneck berikutnya tetap layout, khususnya inline placement dan item
building, bukan style.
