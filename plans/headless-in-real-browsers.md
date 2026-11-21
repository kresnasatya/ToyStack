# Bagaimana browser nyata membuat mode headless?

## Latar belakang

gladion.app macet di app GUI tetapi lancar di `ToyStackHeadless`. Penyebabnya: app GUI memasang `BrowserTab.pageSource` dari SwiftUI ([`ToyStack.swift:267`](../Sources/ToyStack/ToyStack.swift)), sedangkan headless tidak. Headless juga mematikan async layout (kecuali `TOYSTACK_ASYNC_LAYOUT=1`, [`Browser.swift:144`](../Sources/Engine/Core/Browser.swift)) dan menghentikan timer animasi ([`ScenarioRunner.swift:12`](../Sources/ToyStackHeadless/ScenarioRunner.swift)). Jadi headless memakai engine yang sama, tetapi bukan pengaturan app yang sama.

## Jawaban singkat

Ada dua cara, dan browser besar akhirnya memakai keduanya untuk tujuan berbeda:

1. **Browser yang sama, hanya tanpa jendela yang terlihat.** Semua kode app tetap jalan; yang diganti hanya lapisan paling bawah yang bicara dengan sistem operasi (jendela, layar). Tujuannya: hasil sama persis dengan yang dilihat pengguna.
2. **Program terpisah yang hanya memakai engine.** Lebih kecil dan bisa mengatur waktu sendiri (jam palsu, frame satu per satu), sehingga hasilnya selalu sama setiap kali dijalankan. Tujuannya: test dan screenshot yang stabil.

`ToyStackHeadless` saat ini adalah cara nomor 2.

## Per browser

| Browser | Cara | Catatan |
|---|---|---|
| **Chrome** | Dulu cara 2, sekarang cara 1 | Headless lama adalah "a separate, alternate browser implementation" yang "didn't share any of the Chrome browser code in `//chrome`". Sejak Chrome 112, headless baru adalah Chrome biasa yang "creates, but doesn't display, any platform windows" ([Chrome Headless mode](https://developer.chrome.com/docs/chromium/headless)). Sejak Chrome 132, headless lama hanya ada sebagai program terpisah `chrome-headless-shell` ([Removing --headless=old](https://developer.chrome.com/blog/removing-headless-old-from-chrome)). |
| **Chrome** (jam palsu) | Hanya di cara 2 | `--virtual-time-budget` mempercepat `setTimeout`/`setInterval` ([Headless CLI](https://developer.chrome.com/docs/automation-and-testing/headless-cli)). Tim Chrome: "Virtual time and manual frame control are not supported in the new headless, but are still available with headless_shell", karena memasangnya di Chrome sungguhan "would take an effort of a different magnitude" ([headless-dev](https://groups.google.com/a/chromium.org/g/headless-dev/c/WgNE0CAlx-8)). |
| **Firefox** | Cara 1 | Firefox yang sama dengan flag `-headless` ([Mozilla Hacks](https://hacks.mozilla.org/2017/12/using-headless-mode-in-firefox/)). Lapisan jendela sistem operasi diganti dengan versi headless (`widget/headless/HeadlessWidget.cpp`, [bug 1338004](https://bugzilla.mozilla.org/show_bug.cgi?id=1338004)). Mozilla menjalankan test mereka sendiri (mochitest, Web Platform Tests) dalam mode ini ([bug 1399956](https://bugzilla.mozilla.org/show_bug.cgi?id=1399956), [bug 1373739](https://bugzilla.mozilla.org/show_bug.cgi?id=1373739)). |
| **WebKit** (Safari) | Cara 2 untuk test | Layout test dijalankan oleh program khusus, WebKitTestRunner / DumpRenderTree, yang mencetak pohon render halaman ([WebKit Testing](https://docs.webkit.org/Build%20%26%20Debug/Tests.html), [Writing New Tests](https://webkit.org/writing-new-tests)). Port WPE tidak bergantung pada toolkit UI apa pun ([WPE Architecture](https://wpewebkit.org/about/architecture.html)). |
| **Ladybird** | Keduanya | `ladybird --headless --test-mode` adalah app yang sama tanpa jendela; runner test `test-web` menjalankan test Text, Layout, Ref, dan Screenshot ([Testing.md](https://github.com/LadybirdBrowser/ladybird/blob/master/Documentation/Testing.md)). |

## Kenapa Chrome pindah ke cara 1

Headless lama berbagi engine (`//content`) tetapi tidak berbagi kode app (`//chrome`). Semua yang dipasang oleh app hanya ada di mode berjendela. Bug yang hanya muncul di satu mode tidak terlihat di mode lain.

Ini sama dengan bug gladion.app: `Engine` = engine bersama, `ToyStack` = kode app. `pageSource` dan `usesAsyncLayout = true` hanya dipasang di app, sehingga headless tidak pernah melewati jalur yang macet.

## Pelajaran untuk ToyStack

- **Jangan buang jam palsu headless.** Timer yang dihentikan dan `--frame-limit` / `--screenshot-at` adalah versi ToyStack dari virtual time dan manual frame control di `chrome-headless-shell`. Chrome tetap menyimpan fitur ini justru karena di browser sungguhan fitur ini sulit dibuat.
- **Pindahkan pengaturan app ke engine.** Sebisa mungkin, `ToyStack` dan `ToyStackHeadless` harus memanggil satu fungsi setup yang sama (halaman `about:bookmarks`, async layout), sehingga perbedaan yang tersisa hanya jendela dan jam. Ini Option A dari diskusi sebelumnya.
- **Cara 1 penuh (app GUI tanpa jendela) belum perlu.** App ToyStack kecil; setelah setup dipindah ke engine, sisa kode di `Sources/ToyStack` hanya SwiftUI dan presentasi layer. Menjalankan app GUI tanpa jendela memerlukan izin perekaman layar untuk screenshot di macOS, seperti yang terlihat saat investigasi gladion.app (`screencapture` hanya menangkap wallpaper).
