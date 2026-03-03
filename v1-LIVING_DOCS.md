# Living Documentation

This document catalogs all the major entities/components in the [brownie - Python-based web browser in branch ch01-10](https://github.com/kresnasatya/brownie/tree/ch01-10).

### Requirements

**No third-party dependencies allowed!** It should be pure with Swift.

### File Structure Suggestion

> This is just suggestion and may change in the future.

```
BrowserSwift/
├── URL.swift                    # URL handling and networking
├── HTML/
│   ├── Parser.swift             # HTML parsing
│   ├── Element.swift            # DOM Element
│   └── Text.swift               # DOM Text node
├── CSS/
│   ├── Parser.swift             # CSS parsing
│   └── Selector.swift           # CSS selectors
├── Layout/
│   ├── DocumentLayout.swift
│   ├── BlockLayout.swift
│   ├── LineLayout.swift
│   ├── TextLayout.swift
│   └── InputLayout.swift
├── JavaScript/
│   └── JSContext.swift          # JavaScriptCore wrapper
├── Rendering/
│   ├── PaintCommand.swift
│   ├── VisualEffect.swift
│   └── CompositedLayer.swift
├── Browser/
│   ├── Browser.swift
│   ├── Tab.swift
│   └── Chrome.swift
└── Utils/
    ├── DisplayList.swift
    └── TaskRunner.swift
```

## References

This project appears to be based on the "Web Browser from Scratch" tutorial series:

- Book: [Web Browser Engineering](https://browser.engineering)
- GitHub: [browserengineering/browser](https://github.com/browserengineering/book)
