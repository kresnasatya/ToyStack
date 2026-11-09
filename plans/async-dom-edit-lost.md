# Edit DOM saat layout latar berjalan hilang

Tanggal: 2026-11-09
Tes: `AsyncResizeRestartTests.domEditDuringAPassReachesTheLayout`
(`withKnownIssue`).

## Penyebab (terbukti)

Probe sementara (sudah dihapus): sebuah `div` ditambahkan ke
`<section id="box">` lewat JS saat job latar berjalan. Yang dicatat untuk
`section` di tree yang sedang terpasang:

| Saat | job berjalan | catatan anak tertunda | dokumen perlu layout | anak layout | `state.layout.tree.isDirty` |
|---|---|---|---|---|---|
| job 1 berjalan | ya | 0 | tidak | 0 | ya |
| setelah `appendChild` | ya | **1** | **ya** | 0 | ya |
| setelah job 1 dipasang | tidak | **0** | **tidak** | 0 | **tidak** |
| setelah frame berikutnya | tidak | 0 | tidak | 0 | tidak |

Dua hal bersama-sama membuat edit itu hilang:

1. **Tandanya ada di tree yang dibuang.** Semua fungsi
   `LayoutInvalidation` (`LayoutInvalidation.swift:6-64`) menulis ke
   `node.dom.layoutBox.tree`. Selama job berjalan, itu tree yang sedang
   terpasang, bukan tree milik job. Saat dipasang, `swap(&box.tree, &retired)`
   (`Frame.swift:1418-1419`) mengganti tree itu dengan tree job, dan tanda
   ikut terbuang.
2. **Tidak ada layout lanjutan.** Pemasangan menulis
   `isDirty = layoutInFlightDirty || viewportMoved` (`Frame.swift:1443-1446`).
   Jalur JS hanya menulis ke tree, tidak memanggil `markDocumentDirty`
   (`Frame.swift:2079`), jadi `layoutInFlightDirty` tetap salah. Di frame
   berikutnya, `Frame.swift:963-970` melihat tree baru tidak butuh layout dan
   menganggap perubahannya hanya untuk paint.

Penulis lain ke tree terpasang yang kena masalah yang sama: `textChanged`,
`attributesChanged`, `imageChanged` (`markField` ukuran gambar), dan animasi
(`noteStyleChange`, `Frame.swift:1169-1170`). Untuk `setBlockScrollOffset`
(`Frame.swift:1726`, `:1781`, `:1793`), nilainya juga disimpan di DOM. Apakah
nilai itu dibaca ulang setelah pemasangan belum dicek.

## Pilihan perbaikan

- **Opsi A (disarankan): tunda dan terapkan ulang, di `LayoutBox`.** Semua
  penulis sampai ke tree lewat `LayoutBox` (`nearestBlock` →
  `node.dom.layoutBox`, `imageChanged`, dan animasi di `Frame.swift:1169-1170`
  lewat `state.layout.tree.box`). `LayoutBox` diberi satu pintu untuk
  mengubah tree. Pintu itu menerapkan perubahan ke tree sekarang, dan selama
  job berjalan juga mencatatnya. Saat job dipasang, catatan diterapkan ke tree
  job. Node yang sudah tidak ada di tree job (`contains`) dilewati, lalu
  layout lanjutan dijadwalkan (`layoutInFlightDirty`). Dengan cara ini,
  `LayoutInvalidation` dan animasi sama-sama tertangani. Biaya hanya dibayar
  oleh edit yang terjadi saat job berjalan.
- **Opsi B: layout ulang penuh.** Kalau ada edit apa pun saat job berjalan,
  pemasangan membuang hasil bertahap dan menjadwalkan layout dari nol. Kodenya
  paling sedikit, tapi setiap edit JS saat drag di halaman panjang
  membayar layout penuh (di `embeds.html` ±12–20 ms per layout latar, lihat
  `plans/issues/layout-visit-cost.md`).

Rekomendasi: Opsi A. Opsi B benar, tapi memindahkan biaya ke halaman yang
paling berat.

Tes yang perlu ada sebelum implementasi (gagal dulu):

- `domEditDuringAPassReachesTheLayout` tanpa `withKnownIssue`: tambah anak;
- teks diubah saat job berjalan (`textChanged`);
- anak dibuang saat job berjalan;
- satu langkah animasi yang memengaruhi layout (misalnya `width`) jatuh saat
  job berjalan, termasuk langkah terakhirnya: nilainya harus sampai ke layout
  berikutnya;
- edit lalu job dibatalkan atau DOM diganti: catatan tidak boleh diterapkan ke
  tree DOM lain;
- hasil akhir sama dengan layout dari nol (`renderSignature`, seperti
  `consecutiveBackgroundPassesMatchAFullLayout`).

## Sudah dikerjakan (Opsi A, 2026-11-09)

| File | Perubahan |
|---|---|
| `Sources/Engine/Core/LayoutEdit.swift` (baru) | Tiga jenis edit yang disimpan menurut id node DOM: `childrenChanged`, `imageChanged`, `layoutInputChanged`. |
| `Sources/Engine/Layouts/LayoutBox.swift` | `startRecordingEdits`, `record`, `takeRecordedEdits`. Catatan bernilai nil kalau tidak ada job. |
| `Sources/Engine/Core/LayoutInvalidation.swift` | Setiap fungsi publik mencatat edit lewat box, lalu menandai tree sekarang (`apply`). Tambah/sisip anak dicatat sebagai `childrenChanged` dari induknya, karena job yang sedang berjalan mungkin sudah membaca anak baru dari DOM; jadi saat diputar ulang, anak tidak ditambahkan dua kali. |
| `Sources/Engine/Core/Frame.swift` | `startAsyncLayout` mulai mencatat saat job mengambil salinan tree. `finishAsyncLayout` memutar ulang catatan ke tree job setelah `swap`. Layout lanjutan tidak perlu dijadwalkan di sini: pemanggil edit juga meminta render (`setNeedsRender`/`setNeedsStyle` → `invalidateStyle` → `markDocumentDirty`, `Frame.swift:2087-2098`), dan itu sudah menyalakan `layoutInFlightDirty`. |
| `Tests/ToyStackTests/AsyncResizeRestartTests.swift` | `withKnownIssue` dihapus. 3 tes baru (teks, buang anak, animasi). Semuanya dibandingkan dengan layout dari nol (`expectIncrementalMatchesFull`, browser dilepas supaya layout pembanding berjalan sinkron). |

Animasi (`Frame.swift:1169-1170`) **tidak** diubah.
`animationDuringAPassReachesTheLayout` sudah lulus sebelum perbaikan: semua
langkah, termasuk langkah terakhir, jatuh saat job berjalan, dan lebar akhirnya
tetap 200. Dugaan saya, perubahan style sampai ke job berikutnya lewat
perbandingan input layout (`resolveLayoutInputs`), bukan lewat tanda di tree.
Ini belum ditelusuri. Tesnya disimpan sebagai penjaga.

Hasil:

| Kondisi | Tes yang gagal |
|---|---|
| Sebelum perbaikan | tambah anak (`layoutID` nil + berbeda dari layout penuh), ubah teks, buang anak |
| Sesudah perbaikan | tidak ada |
| Mutasi: tanpa putar ulang | tambah anak, ubah teks, buang anak |
| Suite penuh | `swift test` 351 lulus; `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` 351 lulus |

Versi pertama perbaikan juga menyalakan `layoutInFlightDirty` saat
pemasangan. Bagian itu dihapus. Yang membuatnya terlihat perlu hanya tes teks
versi awal, yang mengedit teks tanpa meminta render, sesuatu yang tidak
dilakukan pemanggil sungguhan. Setelah tes memanggil `setNeedsRender()`, tidak
ada tes yang gagal tanpa tanda itu. Kontrolnya, yaitu edit yang sama setelah
job selesai, cocok dengan layout penuh.

Tes "job dibatalkan atau DOM diganti" tidak dibuat. `layoutInFlight` hanya
menjadi salah di `finishAsyncLayout`, jadi tidak ada jalan batal. Saat DOM
diganti, `replaceDOM` membuang box lama beserta catatannya
(`state.layout.tree.box = nil`), dan pemasangan berhenti di pemeriksaan
`box.tree.dom === dom`. Catatan tidak bisa sampai ke DOM lain.

`contentChangeDuringAPassHoldsPaintBack` memanggil
`page.tab.runAnimationFrame()`, yang melewati frame yang belum dimuat. Tes itu
tetap menguji sesuatu: `paintAndCommit` tetap dipanggil
(`BrowserTab.swift:218`). Kalau penahan paint di `BrowserTab.swift:233`
dimatikan, tes itu gagal (`stillWaiting`).

## Temuan baru: posisi scroll di dalam block kembali ke nilai lama

Ini bug terpisah; sudah diperbaiki dengan Opsi B (lihat bagian berikutnya). Probe (sudah dihapus) memakai block
`overflow: scroll` setinggi 50 px berisi 40 paragraf:

| Jalan | Langkah | DOM (`scrollOffsetY`) | Tree (`blockScrollOffset`) |
|---|---|---|---|
| Sinkron | scroll 10, lalu resize 800 → 400 dan `render` | 10 | **0** |
| Latar | scroll 10 sebelum job | 10 | 10 |
| Latar | scroll +30 saat job berjalan | 40 | 40 |
| Latar | setelah job dipasang | 40 | **10** (di run lain **0**) |
| Latar | setelah job berikutnya (lebar 380) | 40 | **10** |

Penyebab (dari kode, belum dibuktikan dengan tes): layout mengambil posisi
scroll dari `LayoutInputs.scrollOffsets` (`BlockLayoutPass.swift:478`). Nilai
itu disalin dari `dom.side.scrollOffsets` hanya saat input dibangun
(`LayoutInputsBuilder.swift:101`). Scroll tidak mengubah `dom.revision`, jadi
resize yang hanya mengubah lebar memakai ulang input lama
(`Frame.swift:1271-1273`). Akibatnya setiap layout ulang mengembalikan posisi
scroll ke nilai saat input terakhir dibangun. Masalah ini juga terjadi di
jalan sinkron, jadi tidak hanya soal job latar.

## Opsi B: posisi scroll hanya di DOM (sudah dikerjakan, 2026-11-09)

Model ini mengikuti browser sungguhan: posisi scroll bukan masukan layout.
Layout hanya menghasilkan tinggi isi, yaitu seberapa jauh kotak bisa
di-scroll. Posisinya disimpan di satu tempat yang tidak hilang saat layout
diulang. Di ToyStack tempat itu `dom.side.scrollOffsets`. Paint membacanya
lalu membatasinya ke tinggi isi.

| File | Perubahan |
|---|---|
| `Sources/Engine/Layouts/BlockData.swift` | `BlockScroll` hanya menyimpan `contentHeight`; `offset` dihapus. |
| `Sources/Engine/Layouts/BlockLayoutPass.swift` | Layout tidak lagi menulis posisi scroll. `blockScrollOffset` (`@MainActor`) membaca DOM dan membatasinya dengan `blockScrollRange` (baru). Scrollbar memakai nilai yang sama. `setBlockScrollOffset` dihapus. |
| `Sources/Engine/Layouts/LayoutInputs.swift`, `LayoutInputsBuilder.swift` | `scrollOffsets` dan `scrollOffset(_:)` dihapus dari input layout. |
| `Sources/Engine/Core/Frame.swift` | `scrollAt`, `scrollElementDown`, `scrollElementUp` hanya menulis DOM, lalu meminta paint. Batas scroll memakai `blockScrollRange`. |
| `Tests/ToyStackTests/ScrollBoxTests.swift` (baru) | Layout ulang tidak memindahkan kotak; `scrollTop` dari JS langsung tergambar; posisi lewat ujung isi digambar di ujung. Ketiganya memeriksa offset efek scroll di hasil paint. |
| `Tests/ToyStackTests/AsyncResizeRestartTests.swift` | `scrollDuringAPassSurvivesTheInstall`. |

Sebelum perubahan keempat tes gagal: offset 0, bukan 10 / 25 / 313,6 / 30.
`scrollTop` dari JS ternyata juga tidak pernah tergambar sampai input layout
dibangun ulang. Sesudah perubahan, suite penuh lulus 355 tes, dengan dan tanpa
`TOYSTACK_BACKGROUND_LAYOUT_TEST=1`.

Perbedaan dengan browser sungguhan yang masih ada:

- Nilai di DOM tidak dipotong saat isi memendek. Paint yang memotongnya, jadi
  kalau isi memanjang lagi, posisi lama kembali. Browser sungguhan memotong
  nilai yang disimpan setelah layout.
- Scroll masih menggambar ulang (`setNeedsPaint`). Belum ada scroll yang hanya
  menggeser hasil gambar lama di compositor.

## Hit test di dalam kotak scroll (sudah diperbaiki, 2026-11-09)

Bug ini sudah ada sebelum Opsi B. `LayoutTree.hitTest` tidak memperhitungkan
posisi scroll kotak saat turun ke anak-anaknya. Probe (sudah dihapus): kotak
di-scroll 40 px dan paint memakai offset 40, tetapi klik di titik yang sama
tetap mengenai "Paragraph 0". Klik, hover, dan link di dalam kotak scroll jadi
mengenai elemen yang salah.

Perbaikan di `Sources/Engine/Layouts/LayoutPaintPass.swift:6-33`, sama seperti
cara paint menggambar kotak scroll (`PaintPass.swift:137-161`):

- titik hanya diteruskan ke anak kalau ada di dalam kotak, karena isi di luar
  kotak tidak tergambar;
- saat turun ke anak, y ditambah posisi scroll kotak (`blockScrollOffset`).

`hitTest` dan `linkHref` menjadi `@MainActor`, karena `blockScrollOffset`
membaca DOM. Semua pemanggilnya sudah di main thread.

Tes di `ScrollBoxTests`:

| Tes | Sebelum | Sesudah |
|---|---|---|
| `hitTestFollowsTheScrollPosition` | kena node 3 (paragraf pertama), seharusnya node 7 | lulus |
| `hitTestSkipsContentOutsideTheBox` | titik di bawah kotak kena node 9 (isi yang terpotong) | lulus |

Mutasi: kalau pengecekan "di dalam kotak" dibuang, tes kedua gagal. Suite penuh
357 tes lulus, dengan dan tanpa `TOYSTACK_BACKGROUND_LAYOUT_TEST=1`.
