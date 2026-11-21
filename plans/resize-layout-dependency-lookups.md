# Resize: cek ulang §6 dan rencana perbaikannya

Sumber: §6 di [resize-layout-closure-copies.md](resize-layout-closure-copies.md) ("Yang belum masuk rencana ini").

Data:
- `ToyStackHeadless` (release, HEAD `0191c22`) di `https://browser.engineering/reflow.html`: 1440×900, 380 resize dengan langkah 6 px per tick (1440 → 300 → 1440), cara yang sama seperti §5 rencana lama.
- `sample` (macOS) selama 7 detik resize, `--no-profile`.
- Counter `profile.layout` dari jalan yang sama dengan profiler aktif.

Tidak ada kode di repo yang diubah. Diff di §4 diterapkan apa adanya di salinan sementara (`/tmp/ts-s6`, hasil `rsync` dari HEAD). Hasilnya ada di §3.

## 1. Jawaban singkat

§6 **benar sebagian**. Angka persentasenya cocok, tetapi penyebab baris ketiga salah, dan kesimpulannya ("perlu mengubah bentuk `DependencyIndex` untuk ketiganya") tidak tepat.

| Baris di §6 | Klaim | Hasil cek ulang | Status |
|---|---|---|---|
| `markDependents` 18,9 % | dari `setFrame` dan `layoutLine` | 18,3 %. Semuanya lewat `setFrame`: **54 % dari frame blok** (`placeBlockFrame`), 43 % dari frame baris (`layoutLine`) | Benar |
| `__RawDictionaryStorage.find` 14,3 % | sebagian besar dari `markDependents` | 13,3 %; 202 dari 277 sampel (73 %) dari `markDependents` | Benar |
| `DependencyIndex.replaceDependent` 9,2 % | dari `setLineChildrenField`, karena setiap baris menulis ulang catatan `ascent`/`descent` | 12,3 %; 218 dari 256 sampel dari `setLineChildrenField`, **tetapi dari blok `layout.line.children.previous`** (`LayoutTree.swift:805-813`, catatan `y`). Blok `ascent`/`descent` (`LayoutTree.swift:793-801`) hanya 1 sampel | **Salah penyebab** |
| `layoutMode` 6,1 % | membuat array anak DOM baru (`LayoutDOMView.children.getter`) | 7,6 %. Array anak memang 42 % dari biayanya. Sisanya menyalin struct besar: `BlockData` utuh di `hasExtraNodes` (`self[block:]`, `LayoutTree.swift:999-1007`) dan `LayoutInput` utuh untuk setiap anak saat membaca `display` | Sebagian benar |
| Kesimpulan | ketiganya naik seiring jumlah baris yang disusun ulang; perlu mengubah `DependencyIndex` | `markDependents` lebih dari separuhnya dari blok, dan jumlah blok tetap 1.587 di setiap resize. `replaceDependent` tidak perlu perubahan `DependencyIndex`; penyebabnya urutan baris (§2.1) | Sebagian salah |

Counter yang membuktikan baris ketiga (median per layout):

| Counter | Nilai | Artinya |
|---|---:|---|
| `layout.line.children.deps` (blok `ascent`/`descent`) | 1 | hampir tidak pernah jalan |
| `layout.line.children.previous` (blok `y`) | 250 | jalan untuk hampir setiap baris yang disusun ulang |
| `layout.inline.place.rebuiltLines` | 252 | |
| `layout.line.children.previous.us` | 494 µs | 6 % dari `layout.document` (8.010 µs) |

## 2. Analisa

### 2.1 Kenapa "baris sebelumnya" berubah di setiap baris

Setiap baris menyimpan "baris sebelumnya" (`previous`), karena posisi `y` sebuah baris = `y` baris sebelumnya + tingginya. `DependencyIndex` mencatat hubungan ini: "`y` baris 2 membaca `y` dan `height` baris 1". Kalau `previous` berubah, catatan itu ditulis ulang (`replaceDependent`): satu `Set` baru dibuat, dibandingkan, lalu dua `Set` lama dikurangi dan dua `Set` lain ditambah.

Saat lebar berubah, `placeInlineItems` (`BlockLayoutPass.swift:910`) memecah ulang teks menjadi baris. Baris lama yang tidak bisa dipakai apa adanya masuk ke daftar `free` (`BlockLayoutPass.swift:939`), lalu diambil dengan `free.popLast()` (`BlockLayoutPass.swift:969`). `popLast` mengambil dari **belakang**:

| Baris baru | Dapat objek baris | `previous` lama | `previous` baru | Berubah? |
|---|---|---|---|---|
| ke-1 | L4 | L3 | – | ya |
| ke-2 | L3 | L2 | L4 | ya |
| ke-3 | L2 | L1 | L3 | ya |
| ke-4 | L1 | – | L2 | ya |

Semua baris berubah `previous`, jadi semua catatan `y` ditulis ulang. Kalau diambil dari **depan**, baris ke-n dapat Ln lagi, `previous`-nya tetap, dan tidak ada yang ditulis ulang.

Jalur lain di file yang sama sudah mengambil dari depan: `InlinePlacement.start(in:)` (`BlockLayoutPass.swift:1792`) memakai `LinePool` (`BlockLayoutPass.swift:1736-1750`). Jadi `popLast` adalah satu-satunya yang berbeda.

Tes di §4 Langkah 1a membuktikannya di HEAD: urutan baris sesudah resize `[10, 8, 6, 4]`, sebelumnya `[4, 6, 8, 10]`, dan `layout.line.children.previous` jalan 4 kali.

### 2.2 Kenapa `markDependents` mahal

`markDependents` (`LayoutTree.swift:888-893`) dipanggil sekali untuk setiap field yang berubah: `layout.field.set` = 9.601 per layout. Setiap panggilan mencari satu kunci di dictionary `dependents` (`DependencyIndex.swift:8-14`). Di dalam `markDependents`, 207 dari 381 sampel adalah pencarian itu sendiri (hitung hash lalu cari di tabel), bukan pekerjaan menandai field.

Satu temuan sampingan: `LayoutField` adalah `enum LayoutField: String` (`LayoutField.swift:5`), jadi hash-nya dihitung dari teks namanya (`String.hash`, `LayoutField.rawValue.getter` muncul di `sample`). Percobaan menghitung hash dari `mask` saja menghapus `String.hash` dari `sample` (43 → 3 sampel), **tetapi waktu layout tidak berubah** (median 6,62 → 6,60 ms). Jadi yang mahal adalah pencarian di tabel besar, bukan hash teksnya. Karena itu rencana ini mengganti cara menyimpan, bukan cara menghitung hash.

Kunci layout berbentuk `(LayoutID, LayoutField)`. `LayoutID` adalah nomor urut, dan ada 11 `LayoutField`. Jadi kunci layout bisa langsung menjadi nomor slot di array: `id × 11 + nomor field`. Tidak ada hash, tidak ada pencarian.

### 2.3 `layoutMode`

`layoutMode` (`BlockLayoutPass.swift:508-519`) dipanggil untuk setiap blok (1.773 kali per layout) dan:
- membuat `LayoutDOMView` tiga kali (`domView(id)`), masing-masing memegang salinan `LayoutInputs`,
- membuat array `[LayoutDOMView]` untuk anak DOM (`LayoutDOMView.swift:11-13`) hanya untuk mencari satu anak `display: block`,
- membuat array itu sekali lagi di baris 516 hanya untuk `isEmpty`.

Membaca langsung dari `LayoutInputs` (yang sudah punya `children`, `tag`, `text`) menghilangkan array dan `LayoutDOMView`. `layout.mode.us` turun dari 427 ke 207 µs.

Salinan `BlockData` di `hasExtraNodes` tidak diubah di rencana ini: penyebabnya `subscript(block:)` (`LayoutTree.swift:999-1007`) yang dipakai di banyak tempat, dan itu butuh analisa sendiri.

## 3. Verifikasi di salinan sementara

| Cek | Hasil |
|---|---|
| Langkah 1a di HEAD: `swift test --filter InlineTextLayoutTests/rewrapKeepsLinesInTheirOldOrder` | **gagal** di dua `#expect`: urutan `[10, 8, 6, 4]` ≠ `[4, 6, 8, 10]`, dan `layout.line.children.previous` count 4 |
| Sesudah Langkah 1–3: `swift test --filter "FieldKeyMapTests\|LayoutInputsTests\|InlineTextLayoutTests\|DependencyIndexTests\|LayoutDependencyTests"` | 31 tes lolos |
| Sesudah Langkah 1–3: `swift test --no-parallel` | 429 tes lolos |
| Sesudah Langkah 1–3: `swift test` (paralel), 5 kali | `syncLayoutResizeWaitsForTheTick` gagal 2 dari 5. **HEAD tanpa perubahan juga gagal 3 dari 5** dengan tes yang sama (sudah dicatat di §3 rencana lama) |
| Screenshot headless di t = 4,2 s dan di akhir drag | sama persis dengan HEAD (`cmp`) |

Layout per resize (`BrowserTab.layout`, 380 resize per jalan, release, `--no-profile`), HEAD dan hasil rencana dijalankan bergantian:

| Metrik | HEAD | Sesudah Langkah 1–3 |
|---|---:|---:|
| Median, 3 jalan | 6,93 / 6,92 / 6,93 ms | **5,14 / 5,17 / 5,17 ms** |
| p90, 3 jalan | 10,51 / 10,42 / 10,46 ms | **7,51 / 7,47 / 7,43 ms** |
| Rata-rata, 3 jalan | 7,61 / 7,59 / 7,61 ms | **5,61 / 5,62 / 5,63 ms** |
| Median / p90 dengan profiler (seperti GUI), 1 jalan | 8,05 / 11,79 ms | **6,28 / 8,77 ms** |

Per langkah (median dari 3 jalan, diukur berurutan):

| Langkah | Median | p90 |
|---|---:|---:|
| 1. Urutan baris | 7,25 → 6,62 ms | 11,08 → 9,24 ms |
| 2. `layoutMode` | 6,60 → 6,27 ms | 9,14 → 8,82 ms |
| 3. `FieldKeyMap` | 6,21 → 5,29 ms | 8,76 → 7,67 ms |

Langkah 2 dan 3 diukur dengan percobaan hash `LayoutField` (§2.2) masih terpasang; percobaan itu sendiri tidak mengubah waktu, dan angka akhir di tabel atas diukur tanpa percobaan itu.

`sample` sesudah Langkah 1–3 (persentase dari waktu layout, yang sekarang lebih pendek):

| Bagian | HEAD | Sesudah |
|---|---:|---:|
| `markDependents` | 18,3 % | 8,7 % |
| `__RawDictionaryStorage.find` | 13,3 % | 1,5 % |
| `DependencyIndex.replaceDependent` | 12,3 % | 0,3 % |
| `layoutMode` | 7,6 % | 4,8 % |

## 4. Rencana

### File yang berubah

| File | Langkah | Kenapa |
|---|---|---|
| `Tests/ToyStackTests/Layouts/InlineTextLayoutTests.swift` | 1a | Tes: baris yang dipakai ulang tetap di urutan lamanya |
| `Sources/Engine/Layouts/BlockLayoutPass.swift` | 1b, 2b | `placeInlineItems` mengambil baris lama dari depan; `layoutMode` membaca langsung dari `LayoutInputs` |
| `Tests/ToyStackTests/Layouts/LayoutInputsTests.swift` (baru) | 2a | Tes untuk `hasBlockChild` |
| `Sources/Engine/Layouts/LayoutInputs.swift` | 2b | `hasBlockChild` |
| `Tests/ToyStackTests/Core/FieldKeyMapTests.swift` (baru) | 3a | Tes untuk `FieldKeyMap` |
| `Sources/Engine/Core/FieldKeyMap.swift` (baru) | 3b | Tempat menyimpan pembaca per kunci: kunci layout di array, kunci style di dictionary |
| `Sources/Engine/Core/DependencyIndex.swift` | 3b | `dependents` memakai `FieldKeyMap` |

Tidak ada nama metrik yang berubah, jadi `profiling.md` tetap sama.

### Keputusan desain

**Langkah 1: cara mengambil baris lama dari depan**

- **Option A (rekomendasi)**: pakai `LinePool` yang sudah ada (`BlockLayoutPass.swift:1736`). Satu cara untuk memberi baris lama di seluruh file. Trade-off: tidak ada.
- **Option B**: `oldLines.filter(…).reversed()`, lalu tetap `popLast()`. Satu baris berubah, tetapi file punya dua cara berbeda untuk hal yang sama, dan urutannya bergantung pada `reversed()` yang mudah terhapus tanpa sengaja.

**Langkah 2: `layoutMode`**

- **Option A (rekomendasi)**: tambah `LayoutInputs.hasBlockChild(_:)`, di samping `children`, `tag`, `text` yang sudah ada. `layoutMode` jadi pendek, dan perilaku untuk node yang tidak ada bisa dites langsung.
- **Option B**: tulis loop di dalam `layoutMode` saja. Waktunya sama, tidak ada fungsi baru, tetapi loop yang sama tidak bisa dipakai di tempat lain dan tidak bisa dites langsung.

**Langkah 3: cara menyimpan pembaca per kunci**

- **Option A (rekomendasi)**: `FieldKeyMap`, yaitu array dengan satu slot per `(LayoutID, LayoutField)` untuk kunci layout, dan dictionary untuk kunci style. API `DependencyIndex` tidak berubah, hanya tempat simpannya. Trade-off: memakai 88 byte per node layout (11 slot × 8 byte), termasuk node yang sudah dihapus, karena `LayoutID` adalah nomor urut yang tidak dipakai ulang (`LayoutTree.swift:124-125`).
- **Option B**: tetap dictionary, tetapi hash `LayoutField` dari `mask`, bukan dari teks nama. Sudah dicoba: `String.hash` hilang dari `sample`, tetapi waktu layout tidak berubah (§2.2).
- **Option C**: simpan pembaca di dalam `LayoutNode`. Pencarian juga jadi array, tetapi `LayoutNode` sudah punya 4 property tersimpan (`kind`, `dom`, `links`, `state`), jadi harus dikelompokkan ulang, dan aturan pencatatan pembaca pindah dari `DependencyIndex` ke `LayoutTree`. Tidak dicoba.

`inputsByDependent` (arah sebaliknya) tetap dictionary: dipakai hanya saat catatan ditulis ulang, dan sesudah Langkah 1 itu hanya 0,3 % dari waktu layout.

---

### Langkah 1: baris lama dipakai ulang sesuai urutannya

#### 1a. Tes

`Tests/ToyStackTests/Layouts/InlineTextLayoutTests.swift:90-93`:

```diff
         #expect((profiler.snapshot()["layout.inline.refresh"]?.count ?? 0) > 0)
         expectIncrementalMatchesFull(page)
     }
+
+    @Test func rewrapKeepsLinesInTheirOldOrder() throws {
+        let words: String = Array(repeating: "word", count: 60).joined(separator: " ")
+        let page: LayoutTestPage = LayoutTestPage(
+            html: #"<p id="para">\#(words)</p>"#,
+            rules: """
+                body { display: block; }
+                p { display: block; }
+            """
+        )
+        let p: ElementRef = try #require(page.firstElement(id: "para"))
+        let linesBefore: [LayoutID] = page.lineIDs(in: p)
+        #expect(linesBefore.count >= 3, "the paragraph must wrap onto several lines")
+
+        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
+        page.frame.setNeedsViewportResize()
+        profiler.reset()
+        page.frame.render()
+
+        let linesAfter: [LayoutID] = page.lineIDs(in: p)
+        #expect(Array(linesAfter.prefix(linesBefore.count)) == linesBefore)
+        #expect(profiler.snapshot()["layout.line.children.previous"] == nil)
+        expectIncrementalMatchesFull(page)
+    }
 }
```

Jalankan `swift test --filter InlineTextLayoutTests/rewrapKeepsLinesInTheirOldOrder`. Hasil yang diharapkan: **gagal** di dua `#expect`, urutan `[10, 8, 6, 4]` ≠ `[4, 6, 8, 10]` dan `layout.line.children.previous` count 4.

Kenapa tesnya seperti ini: 60 kata di lebar 800 px menjadi 4 baris, di 300 px menjadi lebih banyak, dan tidak ada baris yang mulai dari kata yang sama dengan panjang yang sama, jadi semua baris lewat daftar `free`. Tes lama `widthResizeWithBreakChangeReusesLineObjects` (`ViewportResizeTests.swift:186`) tidak menangkap ini karena paragrafnya hanya 1 baris sebelum resize. `expectIncrementalMatchesFull` menjaga hasil layout tetap sama dengan layout dari nol.

#### 1b. `placeInlineItems` memakai `LinePool`

`Sources/Engine/Layouts/BlockLayoutPass.swift:937-940`:

```diff
             used.insert(old.line)
         }
-        var free: [LayoutID] = oldLines.filter({ !used.contains($0) })
+        var free: LinePool = LinePool(oldLines.filter({ !used.contains($0) }))
         let collectsBoxes: Bool = !items.contains(where: { item in
```

`BlockLayoutPass.swift:968-971`:

```diff
             let line: LayoutID
-            if let freeLine: LayoutID = free.popLast() {
+            if let freeLine: LayoutID = free.take() {
                 line = freeLine
             } else {
```

`LinePool` adalah `private struct` di file yang sama, jadi bisa dipakai di sini.

Jalankan `swift test --filter InlineTextLayoutTests`: 5 tes lolos. Lalu `swift test`.

---

### Langkah 2: `layoutMode` tanpa array anak

#### 2a. Tes

File baru `Tests/ToyStackTests/Layouts/LayoutInputsTests.swift`:

```diff
+import Testing
+
+@testable import Engine
+
+@Suite(.serialized)
+@MainActor
+struct LayoutInputsTests {
+
+    @Test func blockChildIsFoundAmongInlineSiblings() throws {
+        let page: LayoutTestPage = LayoutTestPage(
+            html: #"<div id="mixed">one <b>two</b><p>three</p></div><div id="flat">one <b>two</b></div>"#,
+            rules: """
+                body { display: block; }
+                div { display: block; }
+                p { display: block; }
+            """
+        )
+        let mixed: ElementRef = try #require(page.firstElement(id: "mixed"))
+        let flat: ElementRef = try #require(page.firstElement(id: "flat"))
+        let inputs: LayoutInputs = page.tree.inputs
+
+        #expect(inputs.hasBlockChild(mixed.id))
+        #expect(!inputs.hasBlockChild(flat.id))
+    }
+
+    @Test func nodeOutsideTheInputsHasNoBlockChild() {
+        let page: LayoutTestPage = LayoutTestPage(
+            html: #"<p>one</p>"#,
+            rules: """
+                body { display: block; }
+                p { display: block; }
+            """
+        )
+
+        #expect(!page.tree.inputs.hasBlockChild(NodeID(raw: UInt32.max)))
+    }
+}
```

Jalankan `swift test --filter LayoutInputsTests`. Hasil yang diharapkan: **gagal compile**, `value of type 'LayoutInputs' has no member 'hasBlockChild'`.

`blockChildIsFoundAmongInlineSiblings` menangkap loop yang hanya melihat anak pertama atau terakhir. `nodeOutsideTheInputsHasNoBlockChild` menangkap node yang tidak ada di `LayoutInputs` (misalnya DOM berubah sebelum layout), yang harus dianggap tanpa anak, bukan crash.

#### 2b. `hasBlockChild` dan `layoutMode`

`Sources/Engine/Layouts/LayoutInputs.swift:43-47`:

```diff
     func children(_ id: NodeID) -> [NodeID] {
         return input(id)?.node.children ?? []
     }
 
+    func hasBlockChild(_ id: NodeID) -> Bool {
+        for child in children(id) where style(child).layout.display == .block {
+            return true
+        }
+        return false
+    }
+
     func parent(_ id: NodeID) -> NodeID? {
```

`style(child)` sama dengan yang dibaca kode lama lewat `$0.style.computed`, jadi anak yang tidak punya input tetap berhenti di `preconditionFailure` seperti sekarang.

`Sources/Engine/Layouts/BlockLayoutPass.swift:508-519`:

```diff
     private func layoutMode(_ id: LayoutID) -> LayoutMode {
         if hasExtraNodes(id) { return .inline }
-        if domView(id).text != nil { return .inline }
-        let hasBlockChild: Bool = domView(id).children.contains(where: {
-            $0.style.computed.layout.display == .block
-        })
-        if hasBlockChild { return .block }
-        if let el = domView(id).element {
-            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? .block : .inline
-        }
-        return .inline
+        let node: NodeID = domID(of: id)
+        let inputs: LayoutInputs = inputs
+        if inputs.text(node) != nil { return .inline }
+        if inputs.hasBlockChild(node) { return .block }
+        guard let tag: String = inputs.tag(node) else { return .inline }
+        let replaced: Bool = tag == "input" || tag == "img" || tag == "iframe" || tag == "canvas"
+        return inputs.children(node).isEmpty && !replaced ? .block : .inline
     }
```

Artinya sama: `domView(id).element` ada kalau dan hanya kalau `inputs.tag(node) != nil` (`LayoutDOMView.swift:20-23`), dan `el.children` adalah `inputs.children(node)` yang dibungkus. `let inputs` menyimpan `LayoutInputs` sekali, supaya `source.inputs` tidak dibaca empat kali.

Jalankan `swift test --filter LayoutInputsTests`: 2 tes lolos. Lalu `swift test`; tes layout yang sudah ada (`LayoutOracleTests`, `BlockLayoutTests`, `EmbedLayoutTests`) menjaga keputusan block/inline.

---

### Langkah 3: pembaca kunci layout disimpan di array

#### 3a. Tes

File baru `Tests/ToyStackTests/Core/FieldKeyMapTests.swift`:

```diff
+import Testing
+
+@testable import Engine
+
+@Suite
+struct FieldKeyMapTests {
+    private static let reader: FieldKey = .layout(LayoutID(raw: 9), .y)
+    private static let otherReader: FieldKey = .layout(LayoutID(raw: 9), .height)
+
+    @Test func lastFieldOfOneNodeAndFirstFieldOfTheNextStayApart() {
+        var map: FieldKeyMap = FieldKeyMap()
+        let lastOfFour: FieldKey = .layout(LayoutID(raw: 4), .inlineContent)
+        let firstOfFive: FieldKey = .layout(LayoutID(raw: 5), .x)
+
+        map[lastOfFour, default: []].insert(Self.reader)
+        map[firstOfFive, default: []].insert(Self.otherReader)
+
+        #expect(map[lastOfFour] == [Self.reader], "two keys share one slot")
+        #expect(map[firstOfFive] == [Self.otherReader], "two keys share one slot")
+        #expect(map[.layout(LayoutID(raw: 5), .y)] == nil)
+    }
+
+    @Test func pairsListEveryKeyThatStillHasReaders() {
+        var map: FieldKeyMap = FieldKeyMap()
+        let width: FieldKey = .layout(LayoutID(raw: 3), .width)
+        let removed: FieldKey = .layout(LayoutID(raw: 7), .descent)
+        let display: FieldKey = .style(NodeID(raw: 2), .display)
+        map[width, default: []].insert(Self.reader)
+        map[removed, default: []].insert(Self.reader)
+        map[display, default: []].insert(Self.otherReader)
+
+        map[removed]?.remove(Self.reader)
+
+        let keys: Set<FieldKey> = Set(map.pairs.map({ $0.key }))
+        #expect(keys == [width, display])
+    }
+
+    @Test func readingANodeThatWasNeverWrittenFindsNothing() {
+        let map: FieldKeyMap = FieldKeyMap()
+
+        #expect(map[.layout(LayoutID(raw: 1_000_000), .y)] == nil)
+        #expect(map.pairs.isEmpty)
+    }
+
+    @Test func removeAllForgetsLayoutAndStyleKeys() {
+        var map: FieldKeyMap = FieldKeyMap()
+        map[.layout(LayoutID(raw: 1), .x), default: []].insert(Self.reader)
+        map[.style(NodeID(raw: 1), .position), default: []].insert(Self.reader)
+
+        map.removeAll(keepingCapacity: true)
+
+        #expect(map.pairs.isEmpty)
+    }
+}
```

Jalankan `swift test --filter FieldKeyMapTests`. Hasil yang diharapkan: **gagal compile**, `cannot find type 'FieldKeyMap' in scope`.

Yang ditangkap setiap tes:
- `lastFieldOfOneNodeAndFirstFieldOfTheNextStayApart`: rumus slot yang salah (misalnya dikali 10, bukan 11), yang membuat field terakhir node 4 dan field pertama node 5 memakai slot yang sama. Pembaca yang tertukar berarti field yang salah ditandai kotor.
- `pairsListEveryKeyThatStillHasReaders`: `pairs` yang salah mengubah slot kembali ke kunci, lupa kunci style, atau masih menampilkan kunci yang pembacanya sudah habis. `fieldKeys(for:)` memakai `pairs`, dan `LayoutDependencyTests` membandingkan hasilnya dengan `LayoutInputTable`.
- `readingANodeThatWasNeverWrittenFindsNothing`: membaca di luar panjang array harus `nil`, bukan crash.
- `removeAllForgetsLayoutAndStyleKeys`: `DependencyIndex.rebuild(from:)` (`DependencyIndex.swift:34-45`) mulai dari `removeAll`; kunci yang tertinggal akan menandai field yang sudah tidak membaca apa-apa.

#### 3b. `FieldKeyMap`

File baru `Sources/Engine/Core/FieldKeyMap.swift`:

```diff
+import Foundation
+
+/// `markDependents` looks up the readers of every layout field a pass
+/// changes, about 9,600 lookups per resize step on a long article. A
+/// dictionary hashes the key and probes its table on each lookup; here a
+/// layout key is an array index instead. Style keys are few and stay hashed.
+struct FieldKeyMap {
+    private var layout: [Set<FieldKey>] = []
+    private var style: [FieldKey: Set<FieldKey>] = [:]
+
+    private static let fieldCount: Int = LayoutField.allCases.count
+
+    private static func slot(_ id: LayoutID, _ field: LayoutField) -> Int {
+        return id.raw * fieldCount + field.mask.trailingZeroBitCount
+    }
+
+    private mutating func grow(to slot: Int) {
+        guard slot >= layout.count else { return }
+        layout.append(contentsOf: repeatElement([], count: slot + 1 - layout.count))
+    }
+
+    subscript(key: FieldKey) -> Set<FieldKey>? {
+        get {
+            switch key {
+            case .layout(let id, let field):
+                let slot: Int = Self.slot(id, field)
+                guard slot < layout.count, !layout[slot].isEmpty else { return nil }
+                return layout[slot]
+            case .style:
+                return style[key]
+            }
+        }
+        _modify {
+            switch key {
+            case .layout(let id, let field):
+                let slot: Int = Self.slot(id, field)
+                grow(to: slot)
+                // Moving the set out leaves it uniquely owned, so an insert or
+                // remove through the yield does not copy it.
+                var value: Set<FieldKey>? = layout[slot].isEmpty ? nil : layout[slot]
+                layout[slot] = []
+                defer { layout[slot] = value ?? [] }
+                yield &value
+            case .style:
+                yield &style[key]
+            }
+        }
+    }
+
+    subscript(
+        key: FieldKey,
+        default defaultValue: @autoclosure () -> Set<FieldKey>
+    ) -> Set<FieldKey> {
+        get { return self[key] ?? defaultValue() }
+        _modify {
+            switch key {
+            case .layout(let id, let field):
+                let slot: Int = Self.slot(id, field)
+                grow(to: slot)
+                var value: Set<FieldKey> = layout[slot]
+                layout[slot] = []
+                defer { layout[slot] = value }
+                yield &value
+            case .style:
+                yield &style[key, default: defaultValue()]
+            }
+        }
+    }
+
+    @discardableResult
+    mutating func removeValue(forKey key: FieldKey) -> Set<FieldKey>? {
+        switch key {
+        case .layout(let id, let field):
+            let slot: Int = Self.slot(id, field)
+            guard slot < layout.count, !layout[slot].isEmpty else { return nil }
+            let value: Set<FieldKey> = layout[slot]
+            layout[slot] = []
+            return value
+        case .style:
+            return style.removeValue(forKey: key)
+        }
+    }
+
+    mutating func removeAll(keepingCapacity: Bool) {
+        layout.removeAll(keepingCapacity: keepingCapacity)
+        style.removeAll(keepingCapacity: keepingCapacity)
+    }
+
+    var pairs: [(key: FieldKey, value: Set<FieldKey>)] {
+        var result: [(key: FieldKey, value: Set<FieldKey>)] = []
+        let nodeCount: Int = (layout.count + Self.fieldCount - 1) / Self.fieldCount
+        for raw in 0..<nodeCount {
+            for field in LayoutField.allCases {
+                let slot: Int = Self.slot(LayoutID(raw: raw), field)
+                guard slot < layout.count, !layout[slot].isEmpty else { continue }
+                result.append((key: .layout(LayoutID(raw: raw), field), value: layout[slot]))
+            }
+        }
+        for (key, value) in style {
+            result.append((key: key, value: value))
+        }
+        return result
+    }
+}
```

Catatan:
- Nama method dan subscript sama dengan dictionary (`[key]`, `[key, default:]`, `removeValue(forKey:)`, `removeAll(keepingCapacity:)`), jadi kode di `DependencyIndex` tidak perlu ditulis ulang.
- Nomor field diambil dari `mask.trailingZeroBitCount` (`LayoutField.swift:18-32`): `mask` sudah memberi setiap field bit sendiri dari 0 sampai 10, dan `switch` di sana memaksa field baru punya `mask`.
- Slot yang kosong berarti "tidak ada pembaca". Kode `DependencyIndex` yang menghapus kunci saat `Set`-nya kosong (`DependencyIndex.swift:72-74`) tetap benar; untuk kunci layout itu tidak melakukan apa-apa lagi.
- Hanya 2 property tersimpan, sesuai aturan maksimal 4.

`Sources/Engine/Core/DependencyIndex.swift:5-9`:

```diff
 struct DependencyIndex {
     private var storage: DependencyStorage = DependencyStorage()
 
-    private var dependents: [FieldKey: Set<FieldKey>] {
+    private var dependents: FieldKeyMap {
         _read { yield storage.dependents }
```

`DependencyIndex.swift:181-184`:

```diff
     func fieldKeys(for dependent: FieldKey) -> Set<FieldKey> {
         var keys: Set<FieldKey> = []
-        for (input, list) in dependents where list.contains(dependent) {
+        for (input, list) in dependents.pairs where list.contains(dependent) {
             keys.insert(input)
```

`DependencyIndex.swift:192-199`:

```diff
 private final class DependencyStorage {
-    var dependents: [FieldKey: Set<FieldKey>]
+    var dependents: FieldKeyMap
     var inputsByDependent: [FieldKey: Set<FieldKey>]
 
     init(
-        dependents: [FieldKey: Set<FieldKey>] = [:],
+        dependents: FieldKeyMap = FieldKeyMap(),
         inputsByDependent: [FieldKey: Set<FieldKey>] = [:]
     ) {
```

Jalankan `swift test --filter "FieldKeyMapTests|DependencyIndexTests|LayoutDependencyTests"`: semua lolos. `DependencyIndexTests` menjaga copy-on-write (`copyKeepsItsEdgesWhenTheOriginalIsWritten`), dan `LayoutDependencyTests` membandingkan seluruh indeks dengan `LayoutInputTable`. Lalu `swift test`.

---

### Langkah 4: ukur ulang

Pakai cara di §5 [resize-layout-closure-copies.md](resize-layout-closure-copies.md). Target sesuai §3: median sekitar 5,2 ms, p90 sekitar 7,5 ms (`--no-profile`), dan `layout.line.children.previous` count sekitar 0 per layout (dengan profiler).

Di GUI, rekam ulang `browser.trace` dengan posisi scroll dan kecepatan drag seperti rekaman 22:46 (§7.4 rencana lama), lalu bandingkan layout p50/p90 dan jumlah frame dengan layout + paint > 16,67 ms.

## 5. Yang belum masuk rencana ini

Dari `sample` sesudah Langkah 1–3:

| Bagian | % | Catatan |
|---|---:|---|
| `layoutLine` | 34,6 | Penempatan anak baris dan `setFrame` baris |
| `placeInlineItems` | 21,7 | Menyusun ulang baris |
| `markDependents` | 8,7 | Sisa: menandai field pembaca (`markField`, `markAncestorsDirty`), bukan pencarian lagi |
| `layoutMode` | 4,8 | Sisa: salinan `BlockData` di `subscript(block:)` (`LayoutTree.swift:999-1007`), yang dipakai di banyak tempat |

Lebar 800 px (§2.4 rencana lama) dan raster juga di luar rencana ini.

## 6. Temuan setelah diterapkan (`browser.trace` 15-11, 11:01)

### 6.1 Perbedaan kode dari rencana

| # | Di mana | Masalah | Akibat |
|---|---|---|---|
| 1 | `FieldKeyMap.swift:85` | `nodeCount` tanpa `/ Self.fieldCount` | `pairs` memeriksa 11× lebih banyak node. Hasilnya tetap benar (slot di luar array dilewati), tetapi lebih lambat. `pairs` hanya dipakai `fieldKeys(for:)` di tes, jadi trace tidak terpengaruh |
| 2 | `FieldKeyMap.swift` | Dua komentar "kenapa" tidak ikut: penjelasan di atas `struct` dan "Moving the set out leaves it uniquely owned…" di `_modify` | Tanpa komentar kedua, `layout[slot] = []` sebelum `yield` mudah dianggap tidak perlu. Kalau dihapus, setiap `insert` lewat `_modify` akan menyalin `Set` |
| 3 | `InlineTextLayoutTests.swift` | Pesan `"the paragraph must be wrap onto several lines"` | Hanya teks pesan |

`Sources/Engine/Core/FieldKeyMap.swift:85`:

```diff
-        let nodeCount: Int = (layout.count + Self.fieldCount - 1)
+        let nodeCount: Int = (layout.count + Self.fieldCount - 1) / Self.fieldCount
```

### 6.2 Tes yang lebih kuat untuk rumus slot

Rumus slot (`id × 11 + mask.trailingZeroBitCount`) menganggap `mask` semua field adalah bit berurutan 0 sampai 10. Kalau suatu saat ada field dengan bit yang dilompati (misalnya `1 << 11` padahal hanya ada 11 field), slot field itu sama dengan slot `x` node berikutnya. `lastFieldOfOneNodeAndFirstFieldOfTheNextStayApart` hanya memeriksa satu pasangan. Ganti dengan tes yang memeriksa semua field dari dua node berdampingan, dan juga memeriksa `pairs` mengembalikan kunci yang sama.

`Tests/ToyStackTests/Core/FieldKeyMapTests.swift:10-21`:

```diff
-    @Test func lastFieldOfOneNodeAndFirstFieldOfTheNextStayApart() {
-        var map: FieldKeyMap = FieldKeyMap()
-        let lastOfFour: FieldKey = .layout(LayoutID(raw: 4), .inlineContent)
-        let firstOfFive: FieldKey = .layout(LayoutID(raw: 5), .x)
-
-        map[lastOfFour, default: []].insert(Self.reader)
-        map[firstOfFive, default: []].insert(Self.otherReader)
-
-        #expect(map[lastOfFour] == [Self.reader], "two keys share one slot")
-        #expect(map[firstOfFive] == [Self.otherReader], "two keys share one slot")
-        #expect(map[.layout(LayoutID(raw: 5), .y)] == nil)
-    }
+    @Test func everyFieldOfTwoNeighbouringNodesKeepsItsOwnReaders() {
+        var map: FieldKeyMap = FieldKeyMap()
+        var keys: [FieldKey] = []
+        for raw in [4, 5] {
+            for field in LayoutField.allCases {
+                let key: FieldKey = .layout(LayoutID(raw: raw), field)
+                map[key, default: []].insert(.layout(LayoutID(raw: raw + 100), field))
+                keys.append(key)
+            }
+        }
+
+        for case .layout(let id, let field) in keys {
+            let reader: FieldKey = .layout(LayoutID(raw: id.raw + 100), field)
+            #expect(map[.layout(id, field)] == [reader], "\(field) of node \(id.raw) shares a slot")
+        }
+        #expect(Set(map.pairs.map({ $0.key })) == Set(keys))
+    }
```

Sudah dicoba di salinan sementara dari kode yang sekarang:
- Kode apa adanya: `swift test --filter FieldKeyMapTests` → 4 tes lolos.
- `LayoutField.inlineContent` diubah ke `1 << 11`: tes baru **gagal** (3 issue): field `inlineContent` node 4 dan `x` node 5 saling memakai slot, dan `pairs` mengembalikan kunci yang salah.

Tes ini memeriksa perilaku (setiap kunci membaca pembacanya sendiri), bukan bentuk `mask`, jadi tetap berlaku kalau rumus slot diganti.

### 6.3 Hasil di GUI

Rekaman: 61 detik, 874 event resize dalam 13 kali drag, 869 layout di background. Tidak ada `trace.warning`, tidak ada span terpotong, `layout.animation.fallback` 0, `layout.async.handoff sharedIndex` 0, `layout.dependencies.copy` 0.

Kondisi rekaman, dibanding rekaman lama (§7.4 rencana lama):

| | 09:13 | 22:46 | 15-11 11:01 |
|---|---:|---:|---:|
| Posisi scroll (`tiles.scroll`) | 371 px | 567 px | 527 px |
| Tile dipakai ulang / digambar ulang per frame (p50) | 42 / 35 | 35 / 32 | 35 / 40 |
| Operasi paint per frame (p50) | 182 | 206 | 203 |
| Perubahan lebar per event resize (p50) | 4 px | 5 px | 6 px |
| Thread raster yang jalan bersamaan dengan layout (rata-rata) | 0,79 | 0,89 | **1,24** |

Sebanding, kecuali raster: rekaman ini merebut CPU dari layout lebih sering, jadi angka layout di bawah sedikit merugikan hasil baru.

Layout (`layout.async.document`):

| | 09:13 | 22:46 | 15-11 11:01 |
|---|---:|---:|---:|
| p50 / p90 (tanpa job lebar 800 px) | 9,66 / 13,85 ms | 8,73 / 11,94 ms | **7,55 / 10,49 ms** |
| Layout > 13,2 ms | 12,7 % | – (22:28: 6,8 %) | **4,2 %** |
| `layout.line.children.previous` per job | ~250 | ~250 | **0** (maks 1) |
| `layout.mode.us` per job (p50) | – | – | 213 µs (headless sebelum: 427 µs) |

Per kelompok baris yang disusun ulang (p50, tanpa job lebar 800 px):

| Baris disusun ulang | 09:13 | 22:46 | 15-11 11:01 | n |
|---|---:|---:|---:|---:|
| 0–100 | 7,60 ms | 6,69 ms | **5,67 ms** | 214 |
| 100–200 | 8,58 ms | – | **6,30 ms** | 132 |
| 200–400 | 9,95 ms | 8,81 ms | **7,68 ms** | 252 |
| 400–700 | 11,45 ms | – | **9,01 ms** | 206 |
| 700+ | 15,10 ms | 12,13 ms | **9,52 ms** | 48 |

Layout dengan 200–500 baris disusun ulang, menurut jumlah thread raster yang jalan bersamaan:

| Thread raster bersamaan | 09:13 | 22:28 | 15-11 11:01 |
|---|---:|---:|---:|
| < 0,5 | 9,69 ms | 8,85 ms | **7,06 ms** (n = 106) |
| 0,5–1,5 | 10,22 ms | 9,69 ms | **7,67 ms** (n = 60) |
| ≥ 1,5 | 10,97 ms | 10,94 ms | **8,87 ms** (n = 161) |

Pembanding yang benar untuk rencana ini adalah 22:28 / 22:46: keduanya sudah memakai perbaikan rencana lama, sama dengan HEAD tempat headless di §3 diukur. Rekaman 09:13 masih sebelum rencana lama, jadi selisih terhadap 09:13 berisi hasil dua rencana sekaligus.

Terhadap 22:28 / 22:46, rencana ini membuat layout p50 13 % lebih cepat (8,73 → 7,55 ms), p90 12 % (11,94 → 10,49 ms), dan per kelompok baris 13–22 %. Di kelompok yang raster-nya hampir diam, layout 20 % lebih cepat (8,85 → 7,06 ms); di dua kelompok raster lain 19–21 %. Itu lebih kecil dari headless (−26 %). Rekaman ini juga lebih sering menjalankan raster bersamaan dengan layout (rata-rata 1,24 thread, sebelumnya 0,89). [INFERENCE] Sisa selisihnya kemungkinan dari perbedaan mesin dan cara drag antar rekaman, bukan dari perbaikan yang tidak bekerja: counter `layout.line.children.previous` dan `layout.mode.us` sama dengan hasil headless.

Lewat lebar 800 px: 10 job. 7 di antaranya 23,5–25,7 ms (sebelumnya 26,3–28,9 ms). Satu 34,6 ms (yang pertama, `text.font` 3,4 ms karena cache font masih kosong), dan dua 10,3 ms yang berurutan di t = 43,7 s.

Bagian lain:

| | 09:13 | 22:28 | 15-11 11:01 |
|---|---:|---:|---:|
| Paint p50 | 3,45 ms | 4,02 ms | 3,68 ms (p90 4,58) |
| `composite_raster_and_draw` p50 / p90 | 4,8 / 7,8 ms | 6,8 / 14,6 ms | 5,86 / 10,63 ms |
| Jarak antar event resize > 20 ms | 20,1 % | – (22:46: 25,5 %) | **36,4 %** |

Jarak antar event resize yang > 20 ms bukan karena mesin sibuk: selama jarak itu, main thread hanya sibuk 17 % (di jarak ≤ 20 ms: 29 %). Event dari sistem memang datang lebih jarang di rekaman ini (p50 15,2 ms, p75 22,4 ms), jadi bergantung pada cara drag.

Dua angka baru, belum ada pembandingnya di rekaman lama:
- Layout + paint > 16,67 ms: **6,8 %**. Cara hitung saya: durasi `layout.async.document` + `BrowserTab.paint` pertama sesudah job selesai. Cara hitung 15,7 % di §7.4 rencana lama tidak tertulis, jadi jangan dibandingkan langsung.
- Dari event resize sampai lebar itu tampil di layar (`view.presentation` dengan `baseWidth` = lebar itu): p50 **24,6 ms**, p90 37,7 ms. Layout sekarang sekitar 7,6 ms dari itu; sisanya paint (~3,7 ms), raster (~5,9 ms), dan upload tile.

### 6.4 Kesimpulan

- Langkah 1–3 bekerja di GUI: dibanding 22:28 / 22:46 (pembanding yang sama dengan headless), layout p50 13 % lebih cepat, per kelompok baris 13–22 %, dan 19–21 % per kelompok raster, walaupun raster lebih sering jalan bersamaan. Headless memberi −26 %, jadi keuntungan di GUI lebih kecil. Angka terhadap 09:13 (23–37 %) adalah gabungan rencana lama dan rencana ini.
- §6.1 #1 (`nodeCount`) dan tes §6.2 sudah diterapkan; `swift test --no-parallel`: 429 tes lolos. Yang tersisa hanya teks: nama tes `everyFieldOfTwoNeighbouringNodesKeepsItOwnReaders` (seharusnya `…KeepsItsOwnReaders`), pesan `"must be wrap"` (§6.1 #3), dan komentar §6.1 #2 yang belum dikembalikan.
- Sisa frame yang terlambat sekarang lebih banyak berasal dari event resize yang datang jarang, lewat lebar 800 px, dan raster + upload sesudah layout, bukan dari layout biasa.
