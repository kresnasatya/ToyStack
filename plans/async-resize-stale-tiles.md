# Resize: isi halaman tertinggal di lebar lama sampai di-scroll

Tanggal: 2026-11-15
Dasar: `browser.trace` (GUI, `https://browser.engineering/`, 113 blok, jendela
dibesarkan 458 → 1440 px dalam 23 langkah, 2757–3134 ms).

## Gejala

Jendela kecil dibesarkan. Teks tetap tergambar dengan lebar lama, lalu baru
"menyesuaikan" belakangan. Di trace, isi yang benar baru muncul saat scroll
pertama, sekitar 2,2 detik setelah drag selesai.

## Bukti dari trace

Layout dan paint jalan di setiap langkah (`layout.lines.total` turun 13 → 5),
tapi tile hanya dibuat ulang dari paint yang baru (`raster.composite.scan`)
sekali, di frame 36 (2944 ms dan 2950 ms):

| Frame | `raster.composite.scan` | tile hit / miss |
|---|---|---|
| 24–34 | tidak | 32→48 hit, hanya `missNew 8` (kolom baru di kanan) |
| 36 | ya, 2 kali | `missStale 53`, lalu `missStale 19` |
| 37–47 | tidak | 64→72 hit, 0 miss |
| 76 (5339 ms, scroll) | ya | **`missStale 54`**, `hits 18` |

`missStale` berarti slot tile yang sama sebelumnya punya isi lain. Jadi dari
frame 37 sampai scroll di 5339 ms, layar menampilkan paint dari frame 36
(lebar ±850–907 px) di jendela 1440 px. Frame 36 ikut dibuat ulang karena media
query berubah di 850 px (`viewportStyle=1`), bukan karena resize-nya sendiri.

## Penyebab

1. Tanda "tile perlu dibuat ulang" untuk frame ini hanya dihitung di awal tick
   animasi: `Frame.swift:1147` mengisi `composite.isNeeded` dari apa yang kotor
   saat itu.
2. Saat resize, layout latar selesai **di antara** tick. Contoh frame 24:
   resize 2757,8 ms → `layout.async.finish` 2765,3 ms → tick berikutnya
   2766,9 ms. Di tick sebelumnya layout masih berjalan dan tidak ada yang
   kotor, jadi tandanya `false`.
3. Setelah layout dipasang, `finishAsyncLayout` memanggil `setNeedsPaint()`
   (`Frame.swift:1444`), lalu `continueAfterInstall` langsung paint dan
   commit (`Frame.swift:1450-1456`). `setNeedsPaint` (`Frame.swift:2186`)
   tidak menyalakan `composite.isNeededForPaint`.
4. `makeSnapshot` (`Frame.swift:1466-1469`) melihat kedua tanda `false`, lalu
   mengirim `updates = [:]` (kosong, bukan `nil`). `Browser.commit`
   (`Browser.swift:340-344`) membacanya sebagai "cukup gambar ulang"
   (`setNeedsDrawOnly`).
5. Raster memakai layer lama `inputs.scene.previousLayers`
   (`Browser.swift:485-488`): perintah gambar lama dan kunci tile lama
   (`RasterLayer.swift:151`). `compositeGeneration` juga tidak naik, jadi
   presenter memasang layer lama dengan label ukuran layout yang baru
   (`RenderedSource.layoutSize` diambil dari `paintedLayoutSize`,
   `Browser.swift:454-457`).

Jalan sinkron tidak kena, karena paint di sana terjadi di dalam tick dan
`paint.isNeeded` ikut menyalakan `composite.isNeeded`. Tempat lain yang paint di
luar tick sudah menyalakan tandanya sendiri: `Frame.swift:1207` dan
`Frame.swift:1579`.

## Pilihan perbaikan

- **Opsi A (disarankan, sudah ada di working tree):** di `finishAsyncLayout`,
  nyalakan `composite.isNeededForPaint` sebelum `setNeedsPaint()`. Ini aturan
  yang sudah dipakai: siapa pun yang paint di luar tick, dia yang meminta
  composite. Satu baris, hanya mengubah jalur pemasangan layout latar.
- **Opsi B:** di `Browser.commit`, anggap setiap perubahan `paintRevision`
  butuh composite (`updates == nil || paintChanged`). Ini menangkap juga
  pemanggil yang lupa di masa depan. Tapi jalur cepat efek
  (`Browser.swift:331-338`) harus disusun ulang, karena dia bisa `return`
  sebelum cek itu, dan perubahannya menyentuh semua commit, bukan hanya
  resize.

Rekomendasi: Opsi A. Opsi B lebih umum, tapi mengubah jalur efek (opacity,
transform) yang tidak berhubungan dengan bug ini.

Konsekuensi: setiap langkah resize sekarang benar-benar membuat tile baru dari
paint baru. Sebelumnya langkah itu "murah" karena hasilnya salah. Biaya
sebenarnya terlihat di frame 36: raster ±6 ms (53 tile), dan presenter butuh
±13 ms sampai layer baru terpasang. Kalau drag terasa lebih berat setelah ini,
itu biaya yang memang harus dibayar. Langkah berikutnya adalah mengukur dan
mengurangi biaya itu, bukan melewatinya.

## Langkah

### 1. Tes dulu

File baru: `Tests/ToyStackTests/Core/AsyncResizeCompositeTests.swift`.
Domainnya `Core/`, karena yang bekerja adalah `Frame` (`finishAsyncLayout`,
`makeSnapshot`).

Tes memeriksa yang dilihat pengguna: teks di layer yang dipakai untuk membuat
tile (`browser.drawList` → `.compositedLayer` → `layer.content.items`) tidak
boleh melewati lebar layout yang sudah di-paint. `settle(untilWidth:)` saja
tidak cukup: `displayedLayoutSize` ikut melaporkan lebar baru walaupun tile
masih lama (lihat penyebab 5).

Tick kosong setelah halaman dimuat itu penting. Tick saat load meninggalkan
`composite.isNeeded = true`. Tanpa tick kosong, commit pertama setelah resize
masih ikut tanda itu dan bug tidak muncul. Di aplikasi, tick jalan terus setiap
frame, jadi tanda itu sudah bersih sebelum drag dimulai.

```swift
import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct AsyncResizeCompositeTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func finishedPassReachesTheTiles() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser()
        defer {
            browser.stopAnimationTimer()
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)
        try #require(Self.widestText(browser.drawList) > 500, "the page does not reach past 500 px at 800")

        browser.resize(to: CGSize(width: 500, height: 600), deferLayout: true)
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(await Self.settle(browser, untilWidth: 500 * browser.pageZoom))

        let widest: CGFloat = Self.widestText(browser.drawList)
        #expect(
            widest <= frame.paintedLayoutSize.width,
            "the tiles still show an older layout: text reaches \(widest) in a \(frame.paintedLayoutSize.width) px layout"
        )
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func passSupersededByADragReachesTheTiles() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser()
        defer {
            browser.stopAnimationTimer()
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)

        browser.resize(to: CGSize(width: 600, height: 600), deferLayout: true)
        browser.resize(to: CGSize(width: 450, height: 600), deferLayout: true)
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(await Self.settle(browser, untilWidth: 450 * browser.pageZoom))

        let widest: CGFloat = Self.widestText(browser.drawList)
        #expect(
            widest <= frame.paintedLayoutSize.width,
            "the tiles still show an older layout: text reaches \(widest) in a \(frame.paintedLayoutSize.width) px layout"
        )
    }

    // MARK: - Helpers

    /// The rightmost text edge in the layers the tiles were drawn from.
    private static func widestText(_ drawList: [DisplayOp]) -> CGFloat {
        var widest: CGFloat = 0
        for op in drawList {
            guard case .compositedLayer(let layer, _, _, _) = op else { continue }
            for item in layer.content.items {
                guard case .text(_, _, _, let rect) = item else { continue }
                widest = max(widest, rect.right)
            }
        }
        return widest
    }

    private static func loadedBrowser() async throws -> (Browser, String) {
        let pagePath: String = NSTemporaryDirectory() + "resize-composite-\(UUID().uuidString).html"
        let html: String = (0..<20).map { (index: Int) -> String in
            "<p>Paragraph \(index) has enough words to fill a wide line and wrap into several lines when the window gets narrow.</p>"
        }.joined()
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()
        try #require(await pump({ browser.activeTab?.isLoaded == true }))
        try #require(await settle(browser, untilWidth: 800 * browser.pageZoom))
        // The app ticks every display frame. An idle tick clears the composite
        // request left by the load, as it does before a real drag starts.
        try #require(browser.activeTab?.rootFrame).runAnimationFrame()
        return (browser, pagePath)
    }

    private static func settle(_ browser: Browser, untilWidth width: CGFloat) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            _ = await pump({ browser.isRenderIdle })
            if browser.isRenderIdle, browser.presentedFrame.displayedLayoutSize.width == width {
                return true
            }
        }
        return false
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
```

Tes kedua menutup kasus drag: resize kedua datang saat layout pertama masih
berjalan. Layout 600 dipasang sebagai layout lama, lalu layout 450 dijalankan
dari `continueAfterInstall`. Tile terakhir harus dari 450.

Konfirmasi gagal: baris perbaikan di `Frame.swift:1443` sudah ada di working
tree, jadi hapus dulu sementara (`git stash -- Sources/Engine/Core/Frame.swift`),
lalu jalankan:

```sh
TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --filter AsyncResizeCompositeTests
```

Hasil yang saya dapat di salinan repo:

```
finishedPassReachesTheTiles: (widest → 775.03125) <= (frame.paintedLayoutSize.width → 500.0)
passSupersededByADragReachesTheTiles: (widest → 775.03125) <= (frame.paintedLayoutSize.width → 450.0)
```

Gagalnya karena alasan yang benar: tile masih berisi teks dari layout 800 px.
Kembalikan perbaikannya dengan `git stash pop`.

### 2. Perbaikan (Opsi A)

`Sources/Engine/Core/Frame.swift`, di `finishAsyncLayout`:

```diff
         if needsRelayout {
             state.runtime.schedule.needsRender = true
         }
+        state.display.composite.isNeededForPaint = true
         setNeedsPaint()
         return true
     }
```

Hasilnya: `makeSnapshot` mengirim `updates = nil`, `Browser.commit` memanggil
`setNeedsComposite()`, layer dibuat ulang dari paint baru, dan
`compositeGeneration` naik, jadi presenter berpindah ke layer baru.

### 3. Jalankan suite

| Perintah | Tanpa perbaikan | Dengan perbaikan |
|---|---|---|
| `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --filter AsyncResizeCompositeTests` | 2 gagal | 2 lulus |
| `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` | – | 422 lulus |
| `swift test` | 1 gagal di 2 dari 3 run | 1 gagal di 2 dari 2 run |

Kegagalan di `swift test` biasa adalah
`ResizeLayoutStartTests.syncLayoutResizeWaitsForTheTick`
(`paintedLayoutSize.width` 800, seharusnya 500). Kegagalan ini **sudah ada
sebelum perbaikan**. Muncul juga tanpa baris baru, hanya saat suite jalan
paralel, dan lulus 3 dari 3 kali kalau suite itu dijalankan sendiri. Ini masalah
terpisah, bukan akibat perbaikan ini.

### 4. Cek di aplikasi

Rekam `browser.trace` lagi dengan gerakan yang sama (jendela kecil → besar).
Yang diharapkan:

- `raster.composite.scan` muncul di setiap frame resize, bukan hanya di frame
  saat media query berubah;
- event `tiles` pertama sesudah drag selesai tidak lagi menunjukkan
  `missStale` saat scroll pertama;
- `view.staging completed=1` muncul tidak lama setelah setiap
  `layout.async.finish`.

### Hasil cek ulang (2026-11-15, `browser.trace` setelah perbaikan)

Trace baru: 631 event resize dalam 26 kali drag (lebar 257–1440 px), bolak-balik
kecil ↔ besar.

| Yang dicek | Sebelum | Sesudah |
|---|---|---|
| Frame resize yang membuat ulang tile (`raster.composite.scan`) | 1 dari 23 | **620 dari 620** |
| Isi lebar akhir terpasang (`view.staging completed=1`) setelah resize terakhir | baru saat scroll, ±2,2 detik | 2–8 ms biasanya, paling lama 23,6 ms |
| Resize → isi untuk lebar itu terpasang | tidak pernah (tile lama) | p50 6,4 ms, p90 17,6 ms, p99 22,9 ms |
| Langkah yang isinya terpasang sebelum resize berikutnya | – | 516 dari 605 (85%) |
| `composite_raster_and_draw` di frame resize | – | p50 2,3 ms, p95 5,5 ms, maks 13,4 ms |

Catatan:

- `missStale` masih muncul 4–6 ms setelah resize terakhir. Itu benar: tile
  dibuat ulang karena isinya memang berubah.
- `missStale` kecil saat scroll jauh setelah drag (misalnya 3 tile di scroll
  2180) berasal dari tile di luar layar. Tile itu terakhir digambar di lebar
  lama, dan baru digambar ulang saat terlihat. Yang terlihat di layar sudah
  benar.
- Langkah yang lambat (> 12 ms, 120 langkah) punya median 37 tile miss.
  Langkah yang cepat punya median 4. Di langkah lambat, layer baru butuh
  beberapa present untuk mengunggah tile (`view.staging completed=0`, 279 kali,
  dengan batas 2.000.000 piksel per present). Selama itu, layar menampilkan
  isi langkah sebelumnya yang diskalakan. Ini sisa jeda yang masih terasa.
  Bug tile lama sudah selesai.
- Satu jeda 144 ms (di 72326 ms) terjadi karena drag berhenti. Tidak ada event
  resize di antaranya.

## Pesan commit

```
fix: show the new layout after resizing instead of an older one

After a window resize, the page kept showing text laid out for an
older width until something else forced a repaint, such as a scroll.
A finished background layout was painted, but the tiles were never
rebuilt from that paint: the request to rebuild them is only made at
the start of an animation tick, and the layout finished between ticks.
The engine then treated the new paint as a redraw of the old tiles.

finishAsyncLayout now sets composite.isNeededForPaint, the same way
the other paints outside a tick already do, so the commit rebuilds the
layers from the new paint.
```
