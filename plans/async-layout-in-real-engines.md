# Apakah engine nyata memakai async layout seperti ToyStack?

## Apa yang dimaksud "async layout" di ToyStack

Saat window di-resize, ToyStack menjalankan layout di thread `browser.layout` ([`Frame.swift:1297`](../Sources/Engine/Core/Frame.swift) `startAsyncLayout`). Selama itu:

- main thread tetap melukis dan melakukan hit-test di pohon layout yang lama;
- layar menampilkan gambar lama yang diskalakan (preview);
- hasil layout dipasang begitu selesai ([`Frame.swift:1381`](../Sources/Engine/Core/Frame.swift) `finishAsyncLayout`), walaupun window sudah pindah ke lebar lain.

Jalur ini hanya aktif di app GUI (`usesAsyncLayout = true`, [`ToyStack.swift`](../Sources/ToyStack/ToyStack.swift)). Headless dan test tetap sinkron.

## Jawaban singkat

Tidak ada engine besar yang membuat layout **berjalan sendiri lepas dari JavaScript** dengan cara ToyStack. Yang mereka lakukan berbeda:

1. **Layout tetap di thread yang sama dengan JavaScript** (Blink, WebKit, Gecko, Servo), atau di thread lain tapi JavaScript **menunggu** hasilnya saat butuh ukuran (Ladybird).
2. **Selama resize, yang dibuat async adalah tampilannya, bukan layout-nya.** Bagian ini sama dengan ToyStack: layar terus menampilkan gambar lama sampai frame dengan ukuran baru datang.

## Per engine

| Engine | Tempat layout berjalan | Yang jalan di thread/proses lain | Saat window di-resize |
|---|---|---|---|
| **Blink** (Chrome) | Main thread renderer: style, layout, pre-paint, paint ([RenderingNG architecture](https://developer.chrome.com/docs/chromium/renderingng-architecture)) | Thread compositor (scroll, sebagian animasi), raster dan draw di proses Viz | Viz mengenal surface "fallback" ([`surface_range.h`](https://chromium.googlesource.com/chromium/src/+/main/components/viz/common/surfaces/surface_range.h)). Bahwa surface lama inilah yang tampil selama resize sampai renderer mengirim frame ukuran baru adalah [INFERENCE]; sumber ini tidak menyebut resize secara langsung. |
| **WebKit** (Safari) | Main thread proses WebContent | Compositing di proses UI (remote layer tree di Cocoa), thread scrolling | macOS: layer tree terakhir tetap tampil sementara WebContent melakukan layout untuk ukuran baru secara async ([bug 323132](https://bugs.webkit.org/show_bug.cgi?id=323132)). iOS/visionOS: snapshot ditampilkan selama live resize (`LiveResizeSnapshotState`, [commit](https://chromium.googlesource.com/external/github.com/WebKit/webkit/+/e7e4231516b7817b4dc6200703d207933f828059%5E%21)) |
| **Gecko** (Firefox) | Main thread | Style dihitung paralel oleh Stylo, tapi main thread menunggu sampai selesai ([Rust blog](https://blog.rust-lang.org/2017/11/14/Fearless-Concurrency-In-Firefox-Quantum)). WebRender dan compositor ada di thread/proses lain ([Rendering Overview](https://firefox-source-docs.mozilla.org/gfx/RenderingOverview.html)) | Tidak diverifikasi di sumber ini |
| **Servo** | Thread script (sejak Feb 2024) | Dulu ada thread layout terpisah, tapi dihapus karena "almost always runs synchronously with script" ([PR #31346](https://github.com/servo/servo/pull/31346)) | Tidak diverifikasi di sumber ini |
| **Ladybird** | Sejak Oktober 2026: thread sendiri untuk style + layout, dan satu lagi untuk paint recording ([newsletter Okt 2026](https://ladybird.org/newsletter/2026-10-31)) | Style, layout, paint, dan `:hover` tetap jalan sementara JavaScript sibuk | Tidak disebut. Tujuan perubahannya adalah script yang lama, bukan resize |

Ladybird adalah yang paling mirip ToyStack. Bedanya, Ladybird punya satu aturan penting: kalau script meminta informasi layout (misalnya ukuran elemen), script itu "waits until pending layout work is finished, so it never gets stale data".

## Kenapa engine nyata tidak bebas menjalankan layout secara async

JavaScript bisa menanyakan hasil layout **saat itu juga**, misalnya `offsetWidth`, `getBoundingClientRect()`, atau `getComputedStyle()`. Jawabannya harus sesuai dengan DOM terbaru. Akibatnya ada dua pilihan:

- **Layout di thread yang sama dengan script.** Ini model Blink, WebKit, Gecko, dan Servo. Pengalaman Servo menunjukkan bahwa thread terpisah tidak memberi untung kalau script tetap harus menunggu.
- **Layout di thread lain, tapi script menunggu saat bertanya.** Ini model Ladybird.

ToyStack belum punya API untuk menanyakan ukuran: tidak ada `getBoundingClientRect`, `offsetWidth`, atau `clientWidth` di `Sources/Engine`. Karena itu ToyStack bisa memasang layout untuk lebar yang sudah lewat tanpa masalah kebenaran yang terlihat oleh halaman.

## Konsekuensi untuk ToyStack

Begitu ToyStack menambahkan API untuk menanyakan ukuran, pertanyaan itu tidak boleh membaca pohon layout yang sedang tampil selama job layout masih berjalan. Ada dua pilihan:

- **Option A — tunggu job selesai.** Script menunggu job yang sedang jalan, lalu layout lebar terbaru dijalankan secara sinkron, dan baru setelah itu ukuran dijawab. Ini model Ladybird. Hasilnya selalu benar. Kekurangannya, script bisa tertahan sepanjang satu layout (~16 ms di halaman besar).
- **Option B — matikan async layout begitu halaman memakai API ukuran.** Lebih sederhana, tapi halaman seperti itu kehilangan resize yang mulus.

Rekomendasi: **Option A**, karena kebenaran untuk script lebih penting daripada kelancaran resize. Ini juga satu-satunya model di daftar ini yang menjalankan layout di luar thread script dan tetap benar.
