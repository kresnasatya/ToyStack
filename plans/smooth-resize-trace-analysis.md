# Analisis `browser.trace`: apakah resize sudah mulus?

Sumber: `browser.trace` (GUI, 100,5 detik, 159.339 event, 0 warning, 0 span terpotong).
Isi rekaman: 116 kali tarik jendela (lebar 279–1440 px, tinggi tetap 703 px), total 44,8 detik menarik.

## Kesimpulan

**Belum.** Event resize datang tiap ~16,7 ms (60 Hz), dan menggeser jendela dengan
pratinjau (gambar lama yang di-skala) memang lancar. Tapi isi halaman yang benar-benar
di-layout ulang pada lebar baru jarang muncul selama jendela ditarik:

| Ukuran | Nilai |
|---|---|
| Present selama menarik | 5.051 |
| …yang memakai isi baru (`preview=0`) | 480 (≈10,7 per detik) |
| …isi baru yang benar-benar tampil penuh (bind langsung + generasi baru yang selesai) | ≈275 (≈6 per detik) — **perkiraan**, lihat catatan |
| Layout latar belakang yang basi (`layout.async.superseded`) | 1.341 dari 1.630 (82%) |
| Rentang terpanjang tanpa isi baru per tarikan | median 309 ms, p90 423 ms, maks 672 ms |
| Jeda dari event resize terakhir sampai isi baru tampil | median 26 ms, p90 42 ms |

Setelah tangan berhenti, isi baru muncul cepat (≈26 ms). Masalahnya ada *selama*
menarik: pengguna lebih banyak melihat gambar lama yang di-skala atau terpotong.

Catatan perkiraan: tidak ada counter yang menandai "generasi layer baru sudah tampil".
Angka ≈275 = 194 bind yang memakai ulang layer (`view.kept > 0`, gambar tile baru
langsung dipasang) + 81 event `view` dengan `kept == 0 && deferred == 0` (generasi
baru selesai dipasang) di dalam rentang tarikan. Angka "41,5 ms sampai generasi
lengkap" di #6 juga hasil memasangkan event `added > 0` dengan `deferred == 0`
berikutnya; ini juga perkiraan.

## Penyebab (berurutan dari yang paling berat)

### 1. Satu putaran layout→paint→raster (~30 ms) lebih lama dari jarak antar-event (16,7 ms)

| Tahap | Median | p90 |
|---|---|---|
| `layout.async.document` (thread latar) | 16,9 ms | 21,0 ms |
| `layout.async.finish` (main) | 1,0 ms | 1,5 ms |
| `BrowserTab.paint` (main) | 4,2 ms | 5,7 ms |
| `composite_raster_and_draw` | 6,3 ms | 9,8 ms |
| Mulai layout → composite selesai | 29,7 ms | 38,8 ms |

Saat layout selesai, lebar jendela sudah bergeser 1–2 event. Layout itu jadi basi
(`Frame.swift:1428`). Main thread **bukan** sumber masalah: hanya sibuk 20% dari
waktu menarik, dan cuma 11 dari 2.326 slot 16,7 ms yang kelebihan.

### 2. Isi baru hanya boleh tampil bila lebarnya persis sama dengan jendela

`ContentPresentationState.decide(revision:viewSize:layoutSize:)`
(`Sources/Engine/Presentation/ContentPresentationState.swift:30`) memakai
`contentWidth != viewSize.width`. Karena penyebab #1, syarat ini hampir selalu gagal
saat menarik, jadi hasilnya `preview`. Isi baru hanya muncul saat tangan melambat
atau berhenti sebentar. Hasilnya, jarak antar-isi baru: median 31 ms, tetapi 67 dari
364 jarak ≥167 ms.

### 3. Layout basi tetap di-paint dan di-raster, lalu dibuang

Setiap layout yang basi tetap menjalankan paint (~4 ms main), lalu raster
(CPU worker median 19 ms, p90 35 ms per composite). Jalur `preview` di
`ContentPresenter.applySublayers` (`Sources/ToyStack/ContentPresenter.swift:192-210`)
hanya mengubah transform layer lama dan tidak memasang tile baru. Total
`raster.strip` selama rekaman: 33,5 detik CPU, sebagian besar untuk gambar yang
tidak pernah tampil.

### 4. Setiap perubahan lebar membuat hampir semua tile basi

Counter `tiles` selama menarik: median `missStale` 44, `hits` 18, `missNew` 0.
Lebar berubah → posisi baris teks berubah → hash isi tile berubah → raster ulang.

### 5. Layout lebar baru menyentuh semua blok

`profile.layout` median: `layout.width.changed` 1.583 dari 1.587 blok,
`layout.inline.place` 7,3 ms, `layout.line.children.previous` 4,5 ms.
Pengukuran teks sudah ter-cache (`text.measureMisses` 0), jadi biayanya ada di
pemecahan dan penempatan baris (~444 baris).

### 6. Pemasangan isi baru bertahap dan kadang dibatalkan

Generasi layer baru dipasang tersembunyi dengan jatah piksel per present
(`ContentPresenter.swift:384-393`). Waktu sampai satu generasi lengkap: median
41,5 ms, p90 90,8 ms. Ada 43 generasi yang dibuang sebelum selesai karena sudah
datang generasi berikutnya. `view.commit` saat bind: median 5,3 ms, p90 13 ms,
maks 36,6 ms di thread presenter (bandingkan 0,05 ms saat preview).

### 7. Ukuran acuan untuk men-skala pratinjau salah — **diperbaiki; diverifikasi dengan resize ber-skrip di GUI, belum dengan tarikan tangan**

Presenter memanggil `decide(revision:viewSize:layoutSize:)`
(`Sources/ToyStack/ContentPresenter.swift:134-138`), bukan versi yang memakai
`baseViewSize`. Versi ini mengembalikan `.preview(from: contentWidth)`, dengan
`contentWidth` = lebar layout **terbaru yang basi**
(`ContentPresentationState.swift:30-34`).

Semua 5.051 present selama menarik lewat jalur sublayer
(`view.usesSublayersFlips.sublayers == 1`). Di jalur itu, cabang preview
(`ContentPresenter.swift:192-210`) hanya mengubah transform `contentLayer` lalu
`return`. Placement frame baru tidak disentuh, jadi yang tampil tetap layer dari
bind **terakhir**, yang lebarnya bisa lain.

Akibatnya `PreviewFit` (`Sources/Engine/Presentation/PreviewFit.swift:15`)
menghitung skala dari lebar yang salah. Contoh: bind terakhir 1440 px, layout basi
1220 px, jendela 1201 px → skala 0,984. Yang benar 1201/1440 = 0,834, jadi sisi kanan
terpotong. Saat membesar, skala dibatasi `min(1, …)`, jadi di sisi kanan muncul
area kosong berwarna kanvas.

Catatan: jalur gambar tunggal (`applyImage`) memang memasang gambar baru saat
preview, tetapi tidak memakai ukuran `from` sama sekali (hanya
`contentsGravity = .resize`). Jadi mengganti acuan di `decide` aman untuk jalur itu.

#### Perbaikan

`ContentPresentationState` sekarang mencatat lebar layer yang **sedang tampil**
(`shownContentWidth`). Presenter memberi tahu lewat `didShow(layoutSize:viewSize:)`
setiap kali layer suatu layout benar-benar terlihat:

- bind langsung di `applySublayers` (generasi sama, atau belum ada layer),
- generasi baru yang selesai dipasang di `applyPendingGeneration`,
- gambar baru di `applyImage`.

Bind yang masih *staging* (layer baru masih tersembunyi) **tidak** memanggil
`didShow`, karena yang terlihat masih layer lama. Preview lalu men-skala dari
`shownContentWidth`. Lebar layout terbaru hanya dipakai bila belum ada layer
yang pernah tampil.

`Sources/Engine/Presentation/ContentPresentationState.swift`:

```diff
     public private(set) var baseViewSize: CGSize?
+    /// Width, in view pixels, of the layout whose layers are on screen. A
+    /// bound frame can still be staging behind older layers, so this can lag
+    /// the last bind.
+    public private(set) var shownContentWidth: CGFloat?
     private var lastRevision: PresentedRevision?
@@
-        let contentWidth: CGFloat = layoutSize.width > 0
-            ? layoutSize.width
-            : viewSize.width
+        let contentWidth: CGFloat = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
         if contentWidth != viewSize.width {
             lastRevision = revision
+            // The preview scales the layers on screen, not this unbound
+            // layout, so it must start from the width those layers were laid
+            // out at.
+            let shownWidth: CGFloat = shownContentWidth ?? contentWidth
             return .preview(
-                from: CGSize(width: contentWidth, height: viewSize.height)
+                from: CGSize(width: shownWidth, height: viewSize.height)
             )
         }
@@
         return .bind
     }
+
+    /// Records that the layers laid out at `layoutSize` are now on screen.
+    public mutating func didShow(layoutSize: CGSize, viewSize: CGSize) {
+        shownContentWidth = Self.contentWidth(layoutSize: layoutSize, viewSize: viewSize)
+    }
+
+    private static func contentWidth(layoutSize: CGSize, viewSize: CGSize) -> CGFloat {
+        return layoutSize.width > 0 ? layoutSize.width : viewSize.width
+    }
```

`Sources/ToyStack/ContentPresenter.swift`:

```diff
-        let completeGeneration: Bool = frame.content.generation != lastBoundGeneration
-        lastBoundGeneration = frame.content.generation
+        let completeGeneration: Bool = frame.content.source.generation != lastBoundGeneration
+        lastBoundGeneration = frame.content.source.generation
+        presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)
@@
             pendingGeneration = nil
             lastBoundGeneration = generation
+            presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)
             lastDeferred = 0
@@
             contentLayer.contentsScale = scale.display
         }
+        presentationState.didShow(layoutSize: frame.displayedLayoutSize, viewSize: viewSize)
 
         contentLayer.transform = CATransform3DIdentity
@@
         measure.counter("view.presentation", [
-            "preview": preview ? 1 : 0
+            "preview": preview ? 1 : 0,
+            "baseWidth": Int(previousSize?.width ?? 0),
+            "viewWidth": Int(viewSize.width)
         ], frame: frame.frameID)
```

(`frame.content.generation` → `frame.content.source.generation` juga di
`applySublayers`, `applyPendingGeneration`, dan `applyImage`.)

#### Bagian kedua: lebar layout harus ikut composite, bukan dibaca saat present

`didShow` hanya benar kalau `frame.displayedLayoutSize` memang lebar layer yang
dibawa frame itu. Sebelumnya `Browser.presentedFrame` membaca
`rootFrame.paintedLayoutSize` **saat present**, padahal `content` adalah hasil
composite terakhir. Present yang jatuh di antara paint lebar baru dan selesainya
composite (di trace: preview pada 17,1 ms dan 21,8 ms, di antara paint 16,6 ms dan
composite 24,7 ms) membawa lebar baru dengan layer lama.

Sekarang lebar layout dicatat bersama nomor generasi saat composite dimulai,
dalam tipe baru `RenderedSource` (`Sources/Engine/Presentation/RenderedSource.swift`).

```diff
// Sources/Engine/Presentation/PresentedContent.swift
     public var usesSublayers: Bool = false
-    /// Identifies the compositor generation that produced these layers.
-    /// A new generation must be bound as one complete frame; tiles from one
-    /// generation may still arrive in later presents.
-    public var generation: UInt64 = 0
+    public var source: RenderedSource = RenderedSource()

// Sources/Engine/Presentation/PresentedFrame.swift
     public let viewport: PresentedViewport
-    /// Viewport size in CSS pixels at which this content was laid out.
-    public let layoutSize: CGSize
-
-    /// The size the laid-out content occupies in view pixels.
+
+    /// The size the composited content occupies in view pixels.
     public var displayedLayoutSize: CGSize {
-        CGSize(
+        let layoutSize: CGSize = content.source.layoutSize
+        return CGSize(
@@
-        viewport: PresentedViewport,
-        layoutSize: CGSize = .zero
+        viewport: PresentedViewport
     ) {
@@
-        self.layoutSize = layoutSize

// Sources/Engine/Core/Browser.swift
                 scrollbar: activeSidebar
-            ),
-            layoutSize: activeTab?.rootFrame.paintedLayoutSize ?? .zero
+            )
         )
@@
-        let generation: UInt64 = compositeGeneration
+        // The layout size travels with the composite: a present dispatched
+        // before this composite returns must still describe the old layers.
+        let source: RenderedSource = RenderedSource(
+            generation: compositeGeneration,
+            layoutSize: activeTab?.rootFrame.paintedLayoutSize ?? .zero
+        )
@@
-                            generation: generation
+                            source: source
```

#### Test

- `ContentPresentationStateTests.staleLayoutPreviewsFromShownWidth`: tampil 1440,
  layout basi 1220, jendela 1201 → preview dari 1440. Sebelum perbaikan: 1220.
- `ContentPresentationStateTests.bindNotYetShownKeepsPreviewingFromShownWidth`:
  tampil 1440, bind 1300 yang masih staging, jendela 1250 → preview tetap dari 1440.
  Sebelum perbaikan: 1300.
- `BrowserPresentedFrameTests.presentBeforeCompositeReportsTheShownLayoutWidth`:
  `Browser` sungguhan memuat halaman di 800 px, di-resize ke 500 px, lalu satu
  frame dijalankan. Paint 500 px sudah selesai, composite belum kembali, dan
  `presentedFrame.displayedLayoutSize` harus tetap 800. Sebelum perbaikan: 500.

Tiga titik panggil `didShow` di `ContentPresenter` tidak punya unit test, karena
presenter memakai `CALayer` di target app, sedangkan test hanya mengimpor `Engine`.
Itu diverifikasi lewat GUI di bawah.

#### Verifikasi GUI

Aplikasi dijalankan dengan `TOYSTACK_ASYNC_LAYOUT=1` dari `/tmp/toystack-smoke`
(supaya trace tidak menimpa `browser.trace` milik repo). Jendela diubah ukurannya
lewat System Events: 1440 → 600 → 1300 px, langkah 12 px tiap 16 ms (128 event
resize). Trace-nya punya 469 present: 292 preview, 177 bind.

Dari counter `view` ditentukan lebar layer yang benar-benar tampil, yaitu bind
incremental (`kept > 0`) atau generasi baru yang selesai (`deferred == 0`).
Hasilnya, **292 dari 292** preview punya `baseWidth` sama dengan lebar itu. Contoh
di awal tarikan: bind 1428 dan 1416 masih staging, jadi preview tetap memakai
`baseWidth = 1440`, karena layer 1440 yang masih terlihat.

Batas verifikasi: resize ber-skrip, bukan tarikan tangan. Kebenaran visual tidak
ditangkap sebagai gambar; yang diperiksa adalah angka yang dipakai untuk men-skala.

Sisa masalah yang tidak ikut diperbaiki: saat bind masih staging, cabang bind
memasang transform `scale.page` tanpa skala pas, jadi layer lama tampil 1:1 di
jendela baru selama ~40 ms sampai generasi baru lengkap.

### 8. Gangguan kecil: style ulang sinkron saat melewati breakpoint media query

Selama menarik ada 30 `BrowserTab.style`: median 13,8 ms, maks 21,4 ms, di main
thread. Pemicunya `style.flipped.queries` dan `style.changed.font-size` pada semua
tag. Ditambah 22 `BrowserTab.animFrame` >8 ms. Ini menyebabkan tersendat sesekali,
bukan penyebab utama.

## Arah perbaikan (belum ada perubahan kode)

Memakai layout basi dan membuang layout basi saling bertentangan, jadi pilih salah satu.

**Option A — tampilkan layout basi yang lebarnya hampir sama.** Bind layout yang
selisih lebarnya kecil, lalu skala ke lebar jendela. Raster layout basi tetap jalan
karena hasilnya dipakai.
- Untung: isi yang terlihat tertinggal paling jauh ~1 putaran (~30 ms), bukan
  ratusan ms.
- Rugi: skala ~0,98 membuat teks sedikit buram/goyang sampai bind yang pas. Biaya
  `view.commit` (median 5,3 ms) dibayar lebih sering.

**Option B — buang layout basi lebih awal.** Saat `finish` tahu viewport sudah
bergeser, lewati paint/raster dan langsung mulai layout lebar terbaru. Selama
menarik, andalkan pratinjau dari bind terakhir.
- Untung: hemat ~4 ms main thread + ~19 ms CPU raster per layout basi.
- Rugi: isi baru tetap jarang tampil selama menarik (#2 tidak terselesaikan).

**Rekomendasi: Option A**, karena keluhan utamanya isi yang terlambat, bukan CPU.
#7 (pratinjau salah skala) sudah diperbaiki lebih dulu karena terlihat di kedua
option.

Terpisah dari pilihan itu: turunkan biaya layout per lebar ke ≤ ~10 ms. Hampir semua
blok memang berubah lebar, jadi melewati blok tidak banyak membantu. Yang perlu
dipangkas adalah biaya per baris: `layout.inline.place` dan
`layout.line.children.previous` (#1, #5).
