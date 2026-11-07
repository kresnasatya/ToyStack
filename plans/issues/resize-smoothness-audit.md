# Audit Kemulusan Resize ToyStack

Tanggal: 2026-11-08
Sumber data: `browser.trace` terbaru (GUI, mode layout async, 1070 event
resize, 30 sesi drag). Dokumen ini hanya analisis; tidak ada perubahan kode.

## Jawaban singkat

Belum. Gambar memang diperbarui sekitar 55 kali per detik saat jendela
di-drag, tetapi yang ditampilkan hampir selalu **frame lama yang diperkecil**,
bukan halaman yang sudah di-layout ulang di lebar baru. Isi halaman baru
"menyusul" setelah pointer berhenti.

| Ukuran | Hasil |
|---|---:|
| Job layout async yang dimulai | 1013 |
| Job yang dibuang karena dibatalkan | **963 (95%)** |
| Layout baru yang terpasang selama drag | 0–2 per sesi drag |
| Isi basi terpanjang selama drag | **1,74 s** (drag 1,74 s, 103 event) |
| Waktu sampai isi benar setelah pointer dilepas | 39–84 ms |
| Jarak antar-present saat drag (median) | 17–19 ms |
| Layout dokumen penuh yang selesai | median 44,9 ms, p95 65,3 ms, maks 240,9 ms |
| Style saat breakpoint media query (main thread) | 14–25 ms |

## Penghalang, urut dari dampak terbesar

### 1. Layout dibatalkan setiap kali event resize datang

**Status: sudah diperbaiki dengan Opsi A (2026-11-08).** Rinciannya ada di
`plans/issues/resize-flow-roadmap.md`, Step 5. Butir di bawah ini mencatat
kondisi sebelum perbaikan, jadi nomor barisnya merujuk ke kode lama.

- `Frame.setNeedsViewportResize` (`Sources/Engine/Core/Frame.swift:2132`)
  memanggil `cancelLayoutJobIfStale()` (`Frame.swift:2036`) pada **setiap**
  perubahan lebar.
- `finishAsyncLayout` (`Frame.swift:1376-1384`) membuang hasil yang dibatalkan,
  lalu memulai job baru.
- Event resize datang tiap 16,7 ms, layout halaman ini butuh sekitar 45–65 ms.
  Akibatnya job hampir tidak pernah selesai: job yang dibatalkan rata-rata
  baru jalan 10 ms. Ini kondisi "selalu mulai ulang, tidak pernah selesai".
- Engine nyata memakai aturan sebaliknya: pekerjaan yang sedang jalan
  diselesaikan, lalu frame berikutnya memakai ukuran terbaru. Konten mungkin
  tertinggal beberapa frame, tetapi selalu maju.

### 2. Layout lebar baru terlalu mahal untuk satu frame

- Layout yang selesai: median 44,9 ms, p95 65,3 ms, jauh di atas anggaran
  16,7 ms. Roadmap mencatat 1773 block dikunjungi ulang pada setiap perubahan
  lebar (`plans/issues/resize-flow-roadmap.md`, Step 2b).
- Belum ada batas relayout: perubahan lebar selalu menyentuh seluruh dokumen.
- Worker menyalin pohon layout sebelum mengubahnya (`Frame.swift:1343`,
  `var tree: LayoutTree = tree`; `LayoutTree` adalah struct dengan array
  `nodes`, sementara main thread masih memegang salinan lama). [INFERENSI:
  biaya salinan ini belum diukur terpisah.]
- Walaupun penghalang #1 dibereskan, dengan biaya ini isi halaman baru hanya
  bisa diperbarui sekitar 15–20 kali per detik.

### 3. Breakpoint media query menahan main thread

- Saat media query berubah, `invalidateStyle(fromViewport:)`
  (`Frame.swift:2135-2136`) menjalankan style di main thread: 14–25 ms per
  breakpoint di trace ini, maksimum 113 ms di luar resize.
- Snapshot input layout juga dibuat di main thread
  (`layout.async.start.inputs`, `Frame.swift:1311`): 10–17 ms saat style berubah.
- Selama itu preview tidak bisa dikirim; trace menunjukkan jeda present
  sampai 46 ms tepat di breakpoint.

### 4. Bentuk preview berbeda dari browser nyata

- `PreviewFit` (`Sources/Engine/Presentation/PreviewFit.swift:15`) memperkecil
  frame lama secara seragam saat jendela mengecil (teks ikut mengecil) dan
  tidak pernah memperbesar saat jendela melebar (sisi baru kosong).
- Karena penghalang #1, preview ini yang dilihat pengguna hampir sepanjang
  drag. Di browser nyata keadaan "frame lama" hanya berlangsung 1–3 frame,
  jadi bentuk preview hampir tidak terlihat.

### 5. Jam frame dan present masih bergantung pada main thread

- Jam frame adalah `Timer` 60 Hz di `RunLoop.main`
  (`Sources/Engine/Core/Browser.swift:229-243`), bukan jam yang mengikuti
  refresh layar. Layar 120 Hz tidak dimanfaatkan.
- Preview dikirim dari main thread (`Browser.swift:209-215`). Setiap kerja
  berat di main thread (penghalang #3) langsung menunda preview.
- Belum ada compositor terpisah yang bisa mengubah ukuran tampilan tanpa main
  thread.

### Yang sudah cukup baik

- Tidak ada layout di main thread untuk resize; event resize hanya menandai
  dirty (`BrowserTab.resize`, `Sources/Engine/Core/BrowserTab.swift:241`).
- Preview dibatasi satu per frame (`Browser.swift:189-207`).
- Biaya commit layer saat resize terkendali: `view.commit` p95 4,6 ms,
  maksimum 16,9 ms saat drag.
- Setelah pointer dilepas, isi benar muncul dalam 39–84 ms.

## Urutan perbaikan yang disarankan

1. **Jamin layout selalu maju.** Ada dua pilihan:
   - **Opsi A (disarankan):** jangan batalkan job karena lebar berubah.
     Biarkan selesai, pasang hasilnya sebagai frame antara, lalu mulai job
     berikutnya di lebar terbaru. Mirip perilaku Chromium/WebKit. Kekurangan:
     isi bisa tertinggal satu job (sekitar 45–65 ms).
   - **Opsi B:** tetap membatalkan, tetapi hanya jika job masih muda (misalnya
     baru jalan kurang dari satu frame). Lebih hemat CPU, tetapi ambang waktunya
     sulit dipilih dan tetap bisa macet di halaman yang lebih berat.
   - Tes yang harus gagal lebih dulu: rangkaian resize tiap 16,7 ms dengan
     layout yang lebih lambat dari jarak event harus tetap memasang minimal satu
     hasil layout sebelum event terakhir.
2. **Kurangi biaya layout lebar baru** (Step 2b roadmap): offset vertikal per
   subtree supaya block yang hanya bergeser tidak mengunjungi turunannya.
3. **Keluarkan kerja breakpoint dari jalur preview**: buat snapshot input
   layout lebih murah atau pindahkan sebagian ke worker.
4. **Ubah bentuk preview** setelah #1 selesai: frame lama ditempel di kiri
   atas pada skala 1:1, sisi baru diisi warna latar halaman.
5. **Jam frame mengikuti layar** (`CADisplayLink` di macOS 14+), lalu pisahkan
   jalur preview dari main thread.

## Cara mengulang pengukuran

Muat `browser.trace` sebagai JSON, lalu:

- hitung span `layout.async.finish` yang berisi counter
  `layout.async.discarded` → job dibuang;
- kelompokkan counter `BrowserTab.resize` dengan jeda < 300 ms → satu sesi
  drag;
- per sesi, cari `layout.async.finish` yang tidak dibuang di dalam rentang sesi
  → layout baru selama drag; jarak terpanjang antar-titik itu → isi basi
  terpanjang;
- jarak antar-`present.main` di dalam sesi → kecepatan preview.
