# How real browsers pick `http` or `https` for typed addresses

When you type `google.com` (no scheme), the browser runs three steps:

1. **Guess**: is this an address or a search?
2. **Fix up**: turn the text into a full URL.
3. **Choose the scheme**: try `https` first, fall back to `http` if needed.

## 1. Guess: address or search?

The text is treated as an address if:

- It has a known top-level domain from the Public Suffix List (`google.com`, `bbc.co.uk`). `foo.notarealtld` is treated as a search.
- It is an IP address (`192.168.1.1`, `[::1]`).
- It is `localhost` or has a port (`localhost:8080`).
- It ends with `/` (`intranet/`): this is how users force a single word to be an address.
- It has `user@host` or a path (`example.com/docs`).

It is treated as a search if:

- It has spaces (`how to cook rice`).
- It starts with `?` (Chrome's explicit "search this").
- It is a single word with no dot (`weather`). On company networks a single word might be a real machine name (`http://intranet/`), so Chrome searches but looks up the name in the background and shows a "Did you mean http://intranet/?" bar if it exists.

Chromium: `AutocompleteInput::Parse` + `url_formatter::FixupURL`. Firefox: `URIFixup`.

## 2. Fix up

`google.com` → `google.com/` with a scheme added. The URL parser (WHATWG URL Standard) adds the `/` path. The address bar then hides `https://` and often `www.` again when showing it to you, but the real URL keeps them.

## 3. Choose the scheme

### History

| Era | What happens with `google.com` |
|---|---|
| Before 2021 | Browser sends `http://google.com/`. Server answers `301` → `https://...`. One wasted unencrypted round trip that an attacker on the network can hijack. |
| HSTS | After the first secure visit, the server sends `Strict-Transport-Security`. The browser remembers it and rewrites `http` → `https` internally (Chrome shows it as a `307 Internal Redirect`) before any network traffic. |
| HSTS preload list | A list shipped inside the browser (google.com is on it), so even the very first visit never uses `http`. |
| Chrome 90 (Apr 2021) | Typed addresses without a scheme try `https` first. If it fails, fall back to `http`. |
| Chrome 115 (2023) | "HTTPS-Upgrades": every `http` navigation (also links), not only typed ones, is tried as `https` first with fallback. The typed-only code was later removed because this covers it. |
| Firefox 136 (2025) | HTTPS-First on by default, same idea (try `https`, fall back to `http`). |
| Safari | Upgrades to `https` for sites known to support it, with fallback. |

### Fallback rule (Chrome / Firefox)

```
type "example.com"
  -> HSTS / preload says https?      -> use https, no fallback ever
  -> otherwise try https://example.com/
       success                       -> done
       connection fails / bad cert /
       too slow (Chrome: ~3s timer)  -> retry http://example.com/
                                        (Chrome remembers this host is http-only for a while)
```

Important detail: if the site is in the HSTS list, the browser **never** falls back to `http`. Falling back would let an attacker block port 443 and force you onto plain `http`.

Some browsers also read the DNS `HTTPS` record (SVCB): if it exists, the site supports `https`, so upgrade with confidence.

## ToyStack today

Implemented in commits `b769f5d` through `617fa3c`. `build-app.sh` sets `NSAllowsArbitraryLoads`; without it macOS blocks every `http://` load in `ToyStack.app` (`URLError -1022`).

| Step | Where |
|---|---|
| Address or search, fix up, pick scheme | `Sources/Engine/Networking/AddressInput.swift`, `Punycode.swift`, `TopLevelDomains.swift` (IANA list in `Resources/tlds-alpha-by-domain.txt`) |
| HSTS | `HSTSPolicy.swift`, `HSTSStore.swift` (saved to `~/Library/Application Support/ToyStack/hsts.json`), `HSTSRedirect.swift`, used by `WebURL.request` and `Frame.load` |
| Fallback to http | `HTTPFallback.swift`, `HTTPOnlyHosts.swift`, `Frame.load(_:fallback:)`, `BrowserTab.replaceURL` |
| Short address, "Not Secure" | `AddressDisplay.swift`, `Sources/ToyStack/AddressBar.swift`, `BrowserToolbar.swift` |
| "Did you mean http://word/?" | `HostLookup.swift`, `BrowserTab.didYouMean`, `Sources/ToyStack/DidYouMeanBar.swift` |

| Input | ToyStack now |
|---|---|
| `google.com` | `https://google.com/`, http fallback if https fails |
| `localhost:8000` | `http://localhost:8000/` |
| `intranet/` | `http://intranet/` |
| `intranet` | search, plus "Did you mean http://intranet/?" if the name resolves |
| `foo.notarealtld` | search |
| `München.de` | `https://xn--mnchen-3ya.de/` |

Not done: suggestions while typing (history, bookmarks, inline completion).
