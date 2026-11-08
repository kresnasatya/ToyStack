# Mengurangi biaya `layout.visit`

Tanggal: 2026-11-08
Dasar: pengukuran di `plans/issues/resize-flow-roadmap.md` ("Layout cost
measured") dan satu CPU sample. Dokumen ini hanya usulan; belum ada perubahan
kode.

## Temuan dari CPU sample

Cara ambil: `ToyStackHeadless` release, `www/bench/large.html`, 900 resize
bolak-balik 1000 ↔ 640 px (tidak ada baris yang pindah), `--no-profile`, lalu
`sample <pid> 12`. 6307 sample jatuh di dalam `layoutDocument`.

**83% waktu layout habis untuk menyalin data dan menghitung referensi, bukan
untuk menghitung posisi.**

| Fungsi paling atas di stack | Bagian dari layout |
|---|---:|
| `_platform_memmove` (menyalin memori) | 18,0% |
| `swift_retain` + `swift_release` | 19,5% |
| `bridgeObjectRetain/Release` (array, string) | 11,0% |
| salinan `LayoutNodeSeed` / `LayoutKind` | 7,6% |
| pencarian dictionary | 2,5% |

Penyalinan itu dipicu oleh (dikelompokkan ke fungsi Engine terdekat):

| Pemicu | Bagian dari layout |
|---|---:|
| `LayoutTree.setKind` | 13,1% |
| `LayoutTree.markDependents` | 9,4% |
| isi `layoutBlock` (closure) | 13,2% |
| `LayoutTree.inlineTextLinePlan` | 6,8% |
| `LayoutTree.setFrame` | 5,7% |
| `setChildren`, `markAncestorsDirty`, `markUsed`, `markClean`, `setDirtyDescendants`, `readCGFloat` | 18,6% |

Penyebabnya terlihat di kode. Hampir setiap baca dan tulis field menyalin
**seluruh** `LayoutNode` keluar dari array, lalu menulisnya kembali:

- `LayoutTree.node(_:)` (`Sources/Engine/Layouts/LayoutTree.swift:165`)
  mengembalikan salinan `LayoutNode`: `kind` (enum berisi `BlockData` dengan
  array), `links.children` (array), dan `state`.
- Penulis: `setKind` (`:181`), `setChildren` (`:193`), `markUsed` (`:380`),
  `markClean` (`:403`), `markField` (`:409`), `markAncestorsDirty` (`:418`),
  `setDirtyDescendants` (`:428`), dan `setFrame` (`:514`) semuanya memakai pola
  `var node = self.node(id); …; nodes[id.raw] = node`.
- Pembaca: `readCGFloat` memanggil `isDirty` lalu `storedCGFloat` (`:436`);
  keduanya menyalin seluruh node hanya untuk membaca satu angka.
- `setFrame` membuat array sementara `[LayoutField.zoom, .x, .y, .width]` dua
  kali per panggilan (`:528`, `:534`).
- Pola `var data = blockData(id); data.… = …; setKind(.block(data), at: id)` di
  `layoutBlock` (`Sources/Engine/Layouts/BlockLayoutPass.swift:347`, `:370`,
  `:413`, `:464`) menyalin `BlockData` keluar dan masuk lagi. Karena salinan
  lama masih dipegang array, mengubah array di dalamnya memicu salinan baru.

Satu block yang tidak berubah barisnya melewati puluhan salinan seperti ini.
Itulah ±9 µs per block.

## Usulan

### Opsi A — baca dan tulis node di tempat (disarankan lebih dulu)

Ganti pola salin-ubah-tulis dengan akses langsung ke elemen array:

```swift
nodes[id.raw]!.state.fields.markClean(field)
```

Pembaca mengambil hanya field yang dibutuhkan, bukan seluruh node. `setFrame`
memakai empat panggilan biasa, bukan array sementara. Untuk `BlockData`, buat
satu helper yang mengubah payload di tempat; payload dipindah keluar sebentar
supaya array di dalamnya tidak tersalin.

- **Untung:** menyasar langsung 83% yang terukur. Perilaku tidak berubah, jadi
  bisa dibuktikan dengan alat yang sudah ada.
- **Risiko:** kecil, perubahan mekanis. Yang perlu dijaga: semua tempat yang
  sekarang membaca node sebelum menulis harus tetap melihat nilai yang sama.
- **Bukti:** `LayoutOracleTests` (layout bertahap == layout penuh), screenshot
  `large.html` identik byte demi byte, `layout.document` sebelum dan sesudah
  pada drag yang sama, dan CPU sample ulang.
- [INFERENSI] Perkiraan: jika separuh dari 83% itu hilang, satu layout di
  `large.html` turun dari ±19 ms ke ±11 ms. Angka pastinya harus diukur.

#### Hasil (diterapkan 2026-11-08)

Tiga langkah, masing-masing diukur di drag yang sama (release headless,
`large.html`, 89 resize 1000 → 644 px, tiga kali jalan):

| Langkah | `BrowserTab.layout`, `--no-profile` (median) |
|---|---:|
| Sebelum | 15,7–16,0 ms |
| 1. Akses node lewat `self[node: id]` (`_read`/`_modify`), helper tanpa salinan node, tanpa array sementara | 12,1–12,8 ms |
| 2. Penyimpanan `[LayoutNode]` tanpa optional; node yang dihapus ditandai `state.isRemoved` | 7,7–8,2 ms |
| 3. `self[block: id]` untuk `BlockData`; `hasExtraNodes(_:)`; tulis hanya bila nilainya berubah | **5,7–5,8 ms** |

Langkah 2 perlu karena langkah 1 saja belum cukup. `LayoutNode` berukuran 413
byte, dan membuka `nodes[id.raw]!` di accessor `_read` tetap menyalin seluruh
node: `memmove` naik ke 30% di CPU sample.

Jalur lain pada kode yang sama:

| Jalur | Sebelum | Sesudah |
|---|---:|---:|
| `layout.document` dengan profiler (drag lebar) | 18,3–18,9 ms | 8,7–8,8 ms |
| Drag sempit 450 → 302, layout tanpa baris pindah | 19,1–19,5 ms | 9,2–9,3 ms |
| Drag sempit, layout yang memindah baris (4 per drag) | 43,4–56,9 ms | 23,1–31,0 ms |
| Layout di thread latar (`layout.async.document`) | 21,1–21,2 ms | **12,3 ms** |

Bukti perilaku tidak berubah: screenshot `large.html` 450 → 300 dan
1000 → 700 identik byte demi byte dengan sebelum perubahan, `swift test` 300
tes lulus, dan `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test --no-parallel` 300
tes lulus.

Langkah 4 (diterapkan 2026-11-08): `self[line:]`, `self[text:]`, `self[embed:]`,
dan `self[document:]` menggantikan `lineData`/`textData`/`embedData`/
`documentData` dan pola salin-ubah-tulis untuk `LineData`, `TextData`, dan
`EmbedData` (19 tempat `setKind(.line/.text/.embed(...))`). Semua payload
sekarang dibaca dan ditulis dengan cara yang sama.

Dibanding `HEAD` sebelum Opsi A, diukur dengan build yang sama dan tiga kali
jalan:

| Halaman dan drag | Sebelum Opsi A | Sesudah langkah 4 |
|---|---:|---:|
| `large.html` 1000 → 644, `--no-profile` | 15,8–15,9 ms | 5,7–5,8 ms |
| `large.html` 450 → 302, layout yang memindah baris | 43,7–57,4 ms | 24,2–41,0 ms |
| `large.html`, layout di thread latar | 21,9–22,9 ms | 12,7–12,8 ms |
| 300 paragraf panjang, Helvetica, 1000 → 644 (semua 89 layout memindah baris), `--no-profile` | 16,0–16,2 ms | **7,9–8,0 ms** |

Screenshot identik byte demi byte untuk `large.html` (450 → 300, 1000 → 700) dan
halaman paragraf panjang (1000 → 713).

Di `large.html`, langkah 4 tidak terlihat dibanding langkah 3 (5,7–5,8 ms, dan
layout yang memindah baris 23–24 ms vs 24–25 ms). Sumbangannya di halaman
paragraf panjang tidak bisa dipisah dari langkah 1–3 karena build langkah 3
tidak disimpan.

Sisa di CPU sample halaman paragraf panjang (69% dari layout masih salin dan
hitung referensi):

- `inlineTextLinePlan` 21,6%. `case .text(var text)` menyalin setiap kata
  beserta string dan fontnya (`objc_msgSend`, `CFRetain`). Ini wilayah Opsi B.
- `placeInlineItems` 9,3%.
- `layoutLineBoxes` 8,7%: membangun ulang array box dan lebar setiap baris.

### Opsi B — lewati perhitungan rencana baris saat lebar masih aman

`inlineTextLinePlan` (`BlockLayoutPass.swift:383`) dihitung ulang untuk setiap
paragraf di setiap resize, walaupun hasilnya sama (6,8% layout, 2,1 ms).
Simpan rentang lebar tempat rencana baris itu tetap berlaku. Contoh termudah:
paragraf satu baris yang lebar teksnya muat di lebar lama dan lebar baru pasti
tetap satu baris. Kalau lebar baru masih di dalam rentang, lewati perhitungan.

- **Untung:** kecil sampai sedang, dan aman. Engine nyata juga menyimpan lebar
  isi minimum dan maksimum untuk keputusan seperti ini.
- **Risiko:** rentang yang salah membuat baris tidak pecah ulang. Butuh tes di
  batas rentang (tepat muat, kurang 1 px).

#### Hasil (diterapkan 2026-11-08)

`BlockContent.inlineLinePlan` sekarang `InlineLinePlan`
(`Sources/Engine/Layouts/InlineLinePlan.swift`): baris-barisnya plus `fits`,
rentang lebar yang menghasilkan pemecahan yang persis sama. Rentangnya diambil
dari keputusan yang sudah dibuat algoritma: batas bawah adalah ujung terjauh
kata yang tetap di barisnya, batas atas adalah ujung terdekat kata yang
pindah baris. Selama semua perbandingan `cursorX + width > lebar` berjawaban
sama, setiap `cursorX` juga sama, jadi hasilnya identik dengan menghitung
ulang. `refreshInlineItems` mengosongkan `fits` bila lebar kata berubah (font
berganti); rencana lamanya tetap disimpan hanya untuk memakai ulang baris.

Tes:

- `ViewportResizeTests.widthChangeThatKeepsEveryBreakReusesTheLinePlan`: gagal
  sebelum perubahan (`layout.inline.plan.computed` = 1), lulus sesudahnya (0).
- `ViewportResizeTests.widthSweepKeepsLineBreaksIdenticalToAFullLayout`: lebar
  420 → 240 per 3 px lalu 241 → 421 per 4 px, melewati breakpoint yang
  mengganti font. Setiap langkah dibandingkan dengan layout dari nol, dan tes
  mensyaratkan ada langkah yang menghitung ulang dan ada yang memakai ulang.

`embeds.html`, drag 1000 → 644, tiga kali jalan, dibanding commit langkah 1:

| Jalur | Sebelum | Sesudah |
|---|---:|---:|
| Main thread, `--no-profile` | 9,7–9,8 ms | **8,3–8,6 ms** |
| `layout.document` dengan profiler | 12,7–12,8 ms | 11,6–12,0 ms |
| Thread latar | 17,5 ms | **16,6–16,7 ms** |
| `layout.inline.plan` per layout | 1,71 ms | 0,33 ms |

Rencana yang dihitung per layout: 41 dari 1407 block inline (yang barisnya
memang berubah). Screenshot `embeds.html` identik byte demi byte (lebar 640,
lebar 1000 setelah scroll 3000 px, dan akhir drag).

Catatan: di halaman ini layout di thread latar ±5 ms lebih lama dari layout
yang sama di main thread dengan profiler (16,7 vs 11,6–12,0 ms). Penyebabnya
belum diukur.

### Opsi C — simpan posisi relatif terhadap induk

Saat ini posisi disimpan mutlak. Kalau sebuah block bergeser,
`layoutBlock` menandai `y` setiap barisnya kotor (`BlockLayoutPass.swift:334-337`),
sehingga semua baris ikut dikunjungi. Ini yang membuat layout yang memindah
baris naik ke ±45 ms: semua paragraf di bawahnya ikut bergeser. Dengan posisi
relatif terhadap induk, block yang bergeser tidak perlu menyentuh isinya.
Paint, hit test, dan `absoluteBounds` lalu menjumlahkan offset induk saat
berjalan turun.

- **Untung:** besar untuk halaman yang barisnya sering pindah, seperti halaman
  GUI yang ±40 ms.
- **Risiko:** sedang sampai besar. Semua pembaca posisi harus diubah.

### Opsi D — layout area yang terlihat lebih dulu saat drag

Selama drag, layout cukup sampai sedikit di bawah layar, tampilkan hasilnya,
lalu selesaikan sisanya di job berikutnya. Isi di bawah layar tidak mengubah
posisi isi di atasnya. Gecko punya reflow yang bisa diinterupsi, dan Blink
punya `content-visibility: auto` untuk melewati isi di luar layar.

- **Untung:** paling besar untuk halaman panjang; biayanya tidak lagi
  bergantung pada panjang halaman.
- **Risiko:** besar. Tinggi dokumen dan scrollbar sementara salah; anchor dan
  posisi scroll perlu dijaga; perlu status "layout belum selesai".

## Urutan yang disarankan

1. **Opsi A.** Biaya terbesar yang terukur, risiko terkecil, tanpa perubahan
   perilaku.
2. Ukur ulang (`profile.layout` dan CPU sample). Jika satu layout di
   `large.html` sudah di bawah ±8 ms, lanjut ke **Opsi B**.
3. Putuskan C atau D berdasarkan halaman GUI. Jika sebagian besar biaya ada di
   layout yang memindah baris, pilih C. Jika halamannya sangat panjang, D.

## Rencana tes untuk Opsi A

Opsi A tidak mengubah perilaku, jadi tidak ada tes baru yang bisa gagal lebih
dulu karena perilaku. Kontraknya dijaga oleh tes yang sudah ada:

- `LayoutOracleTests` dan suite layout lain harus tetap lulus.
- Screenshot `large.html`, 450 → 300 dan 1000 → 700, harus identik byte demi
  byte dengan sebelum perubahan.
- Ukuran keberhasilan: `layout.document` median pada drag 1000 → 644 turun, dan
  porsi memmove/retain/release di CPU sample turun.

## Halaman GUI: `https://browser.engineering/embeds.html` (2026-11-08)

Release headless, drag 1000 → 644 px (4 px per tick), kode dengan Opsi A
langkah 1–4:

| Jalur | Waktu per layout |
|---|---:|
| Main thread, `--no-profile` | 11,9–13,5 ms |
| Main thread, `layout.document` dengan profiler | 14,7 ms |
| Thread latar (`layout.async.document`) | 19,7 ms |
| GUI trace terakhir, thread latar | 24,0 ms |

Profil per layout (median): 1587 block dikunjungi, tetapi hanya **41**
paragraf yang barisnya dipecah ulang (`layout.inline.place`) dan hanya 23 block
yang boleh melewati barisnya (`layout.inline.children.skipped`). Sebanyak
1452 baris tetap dikunjungi, 1169 di antaranya lewat jalur "hanya bergeser
vertikal" (`layout.line.place.verticalOnly`). Penyebabnya: begitu satu paragraf
berubah tinggi, semua block di bawahnya bergeser, dan setiap baris block yang
bergeser dikunjungi.

CPU sample (drag bolak-balik 1000 ↔ 640, 8 detik), waktu inklusif dari layout:

| Fungsi | Porsi |
|---|---:|
| `layoutLine` (semua kunjungan baris) | 37,5% |
| — `syncInlineBoxes`, hampir seluruhnya dari jalur vertikal (`LineLayoutPass.swift:148`) | 18,4% |
| `inlineTextLinePlan` (sasaran Opsi B) | 16,4% |
| `placeInlineItems` | 11,1% |
| `markDependents` | 10,9% |
| `textTextWidth` | 9,5% |
| `layoutLineBoxes` | 7,3% |
| salinan struct `LayoutTree` (closure di `layoutBlock` dan `layoutLine`) | ±6% |

`syncInlineBoxes` di jalur vertikal membangun ulang dan membandingkan box yang
isinya pasti sama. Box menyimpan `y = textAbsoluteY(child) - y(line)` =
`y(child) + inlineYOffset - y(line)` = `y(child) - childOriginY`
(`TextLayoutPass.swift:105`), jadi tidak bergantung pada posisi baris; `x` dan
lebar tidak berubah karena jalur ini mensyaratkan `x`, lebar anak, dan jumlah
anak tidak berubah. [INFERENSI dari kode; belum dibuktikan dengan tes.]

Urutan yang disarankan untuk halaman ini:

1. Lewati `syncInlineBoxes` di jalur vertikal (cukup perbarui `boxRevision`
   bila perlu). Sasaran ±18%, perubahan kecil, tes: box sesudah geser vertikal
   harus sama dengan box hasil layout penuh.
2. Opsi B (rencana baris dan salinan per kata): ±16%.
3. Opsi C (posisi relatif terhadap induk): menghapus kunjungan baris dari block
   yang hanya bergeser, yaitu sebagian besar dari 37,5% `layoutLine`.

### Langkah 1 diterapkan (2026-11-08)

Di jalur "hanya bergeser vertikal" (`LineLayoutPass.layoutLine`), baris yang
sudah punya box tidak lagi membangunnya ulang; `followBoxRevision` hanya
memperbarui `boxRevision` bila revisi block berubah. Counter baru
`layout.line.boxes.built` menghitung baris yang box-nya dibangun dari anak teks.

Tes: `InlineBoxTests.lineThatOnlyMovesKeepsItsBoxes`. Margin paragraf pertama
diubah, sehingga semua baris hanya bergeser dan tidak ada baris yang
ditempatkan ulang. Sebelum perubahan tes ini gagal dengan
`layout.line.boxes.built` = 2; sesudahnya 0, box baris yang bergeser sama
dengan sebelumnya, dan hasilnya sama dengan layout penuh.

`embeds.html`, drag 1000 → 644, tiga kali jalan, dibanding commit Opsi A:

| Jalur | Sebelum | Sesudah |
|---|---:|---:|
| Main thread, `--no-profile` | 11,9–12,3 ms | **9,7–10,0 ms** |
| `layout.document` dengan profiler | 15,0–15,2 ms | 12,7 ms |
| Thread latar (`layout.async.document`) | 20,0–20,2 ms | **17,4–17,6 ms** |

Box yang dibangun per layout: 1 (baris yang belum punya box), bukan sekitar
1169. Screenshot `embeds.html` identik byte demi byte (lebar 640, dan lebar
1000 setelah scroll 3000 px).

### Selisih thread latar vs main thread (2026-11-08, setelah Opsi B)

`embeds.html`, drag 1000 → 644, median per layout, tiga kali jalan. Span yang
sebanding: `BrowserTab.layout` (main thread) dan `layout.async.document`
(thread latar); keduanya termasuk sweep. Angka "5 ms" sebelumnya membandingkan
`layout.document`, yang tidak termasuk sweep (1,1 ms).

| | Dengan profiler | Tanpa profiler |
|---|---:|---:|
| Main thread | 12,3 ms | 8,2 ms |
| Thread latar | 15,8 ms | 11,8 ms |

Dua penyebab terpisah:

1. **Profiler: ±4 ms di kedua mode** (±34% dari waktu layout yang diprofil).
   `Profiler.count` 15–21% di CPU sample: setiap hitungan mengambil lock dan
   meng-hash string nama counter. Pemanggil terbanyak: `markDependents`,
   `setFrame`, `blockStyle`, `layoutLine`. GUI menjalankan profiler, dan di
   thread latar hasilnya tidak pernah menjadi `profile.layout` (lihat
   `profiling.md`, Known distortions), jadi di GUI biaya ini tidak menghasilkan
   data yang berguna.
2. **Salinan copy-on-write di thread latar: ±3,6 ms.** Pohon milik job berbagi
   storage dengan pohon terpasang di main thread, jadi penulisan pertama
   menyalin seluruhnya:
   - `DependencyIndex.replaceDependent` → `_NativeDictionary.copy()`: 18,4% dari
     waktu thread latar. Dua dictionary `[FieldKey: Set<FieldKey>]` disalin
     setiap job.
   - `markField` → salinan array node (`_consumeAndCreateNew`,
     `swift_arrayInitWithCopy`): ±6%.

Usulan:

- **Dependency index milik job sepenuhnya.** Pohon terpasang menyerahkan
  `dependencies` ke salinan job saat job dimulai (pohon terpasang dipakai untuk
  paint dan hit test, yang tidak membaca index). Selama job berjalan, tanda
  dependency di pohon terpasang memang sudah hilang saat job dipasang, jadi
  tidak ada perilaku yang berubah. Sasaran: bagian terbesar dari 3,6 ms.
- **Salinan array node** melekat pada desain snapshot (main thread tetap
  menggambar pohon lama). Mengecilkan node (413 byte, `BlockData` 232 byte di
  dalam enum) mengurangi biayanya; itu perubahan lebih besar.
- **Profiler**, pilih salah satu:
  - matikan profiler secara default di GUI (nyalakan lewat variabel
    lingkungan), headless tetap memprofil;
  - beri job di thread latar profiler sendiri yang dikirim sebagai
    `profile.layout`: datanya jadi berguna, tetapi biayanya tetap;
  - buat `Profiler.count` murah (kunci counter tanpa hash string, akumulasi per
    thread tanpa lock): data dan kecepatan sama-sama terjaga, perubahan paling
    besar.

Dipilih: C (profiler murah) lalu B (window `profile.layout` milik job), setelah
perbaikan salinan copy-on-write.

#### Salinan copy-on-write diperbaiki (2026-11-08)

Menyerahkan dependency index saja tidak cukup: tree yang ditangkap di capture
list task tetap hidup selama task berjalan, jadi tulisan pertama job tetap
menyalin array node dan index (pengukuran pertama: tidak ada beda di luar
variasi). Perbaikannya dua bagian:

- `LayoutJobHandoff` (`Sources/Engine/Core/LayoutJobHandoff.swift`)
  memindahkan tree ke job; job mengambilnya dengan `take()`, sehingga job satu-
  satunya pemilik salinannya.
- Pohon terpasang menyerahkan `dependencies` (diganti index kosong) karena paint
  dan hit test tidak membacanya, dan pohon job menggantikannya saat dipasang.

Tes penjaga: `AsyncResizeRestartTests.consecutiveBackgroundPassesMatchAFullLayout`
(empat layout latar berturut-turut harus sama dengan layout dari nol). Tes ini
gagal bila job diberi index kosong, jadi benar menjaga kehilangan dependency.

`embeds.html`, drag 1000 → 644, dua putaran bergantian `HEAD`/sesudah:

| Thread latar | Sebelum | Sesudah |
|---|---:|---:|
| Tanpa profiler | 12,0–12,2 ms | **8,5–8,7 ms** |
| Dengan profiler | 16,0–16,6 ms | 14,6–14,8 ms |

Main thread tidak berubah (8,2–8,4 ms tanpa profiler). Thread latar sekarang
hampir sama dengan main thread. Screenshot identik byte demi byte.

#### Profiler murah, satu window per thread (2026-11-08)

Biaya per panggilan (release, microbenchmark): kunci + kunci `String` 78 ns;
tanpa kunci 36 ns; alamat literal + kunci 26 ns; alamat literal tanpa kunci
14 ns. Kunci dan hash string sama-sama perlu dihapus.

`Profiler` sekarang menyimpan satu window per thread (pthread TLS, struct
lewat pointer mentah), tanpa kunci, dengan nama `StaticString` dikunci menurut
alamatnya. Nama yang dibangun saat runtime memakai `count(named:)`.

Percobaan pertama memakai `byAddress[address, default: ...]` di class; hasilnya
lebih lambat (12,6 → 19,1 ms dengan profiler) karena `default:` mengalokasikan
objek setiap panggilan (`swift_allocObject` → `__isPlatformVersionAtLeast`).
Versi akhir mencari slot dulu lalu memperbarui array di tempat.

`embeds.html`, drag 1000 → 644, dua putaran bergantian `HEAD`/sesudah:

| Median per layout | Sebelum | Sesudah |
|---|---:|---:|
| Main thread, dengan profiler | 12,1–12,9 ms | **9,1–9,6 ms** |
| Main thread, tanpa profiler | 8,1–8,6 ms | 8,1–8,6 ms |
| Thread latar, dengan profiler | 14,3–14,9 ms | **9,4–9,8 ms** |
| Thread latar, tanpa profiler | 8,3–8,7 ms | 8,4–8,5 ms |

Biaya profiler: main thread ±4 → ±1 ms; thread latar ±6 → ±1 ms (sebelumnya
juga berebut kunci dengan main thread). Screenshot identik byte demi byte.

Perilaku di main thread sama (nama, nilai, event `profile.<phase>`). Yang
berubah: hitungan dari thread lain tidak lagi masuk ke window main thread, jadi
`profile.paint` di GUI tidak lagi membawa potongan `layout.*`.

#### `profile.layout` dari job latar (2026-11-08)

Job di thread latar membuka window profiler-nya sendiri dan menulisnya sebagai
`profile.layout` di jalur `browser.layout`, dengan frame saat job dimulai. Tes:
`BackgroundLayoutProfileTests.backgroundLayoutWritesItsOwnLayoutProfile` (gagal
sebelum perubahan: tidak ada `profile.layout` di jalur itu).

Trace headless async `embeds.html`: 90 `profile.layout` untuk 90 job, semuanya
di `browser.layout`; tidak ada `profile.paint` yang membawa `layout.*`. Biaya:
tidak terukur (thread latar dengan profiler 9,38–9,48 → 9,37–9,39 ms).
Screenshot identik byte demi byte.

#### Sweep terarah (2026-11-08)

Sweep tidak lagi menelusuri seluruh tree. `LayoutTree` mencatat node yang
terlepas (`detached`): node yang di-append tetapi belum dipasang, dan anak yang
dibuang dari daftar anak induknya (kecuali sudah diadopsi induk lain). Sweep
hanya membuang node itu beserta subtree yang masih dimilikinya. Di build debug,
setiap sweep dibandingkan dengan penelusuran penuh dari root (`assert`); seluruh
suite tes lulus dengan pemeriksaan itu.

Tes: `LayoutSweepTests.sweepLooksOnlyAtWhatThePassDetached` (sebelum: sweep
memeriksa 258 node, batas < 32) dan `noUnreachableNodeSurvivesAPass` (node hidup
selalu sama dengan node yang terjangkau dari root, melewati re-break,
pemindahan, dan edit DOM).

`embeds.html`, drag 1000 → 644, dua putaran bergantian:

| Median per layout | Sebelum | Sesudah |
|---|---:|---:|
| Main thread, tanpa profiler | 8,2–8,8 ms | **7,3–7,9 ms** |
| Thread latar, tanpa profiler | 8,6–9,1 ms | **7,7–8,0 ms** |

Biaya sweep per job (median) turun dari 1,17 ms ke 0: kebanyakan job hanya
memakai ulang baris dan tidak melepas node apa pun. Screenshot identik.
