# CSS variables, rem, vw, vh

## What changed

| File | Why |
|---|---|
| `Parsing/CSSParser.swift` | `--name: …` keeps its whole value (spaces, commas, strings) and its case. A shorthand (`margin`, `border`, `font`, …) that holds `var()` is not split yet: every longhand gets a pending value. `:root` parses. `_` is allowed in words. |
| `Style/PendingSubstitution.swift` (new) | The "split me after substitution" value a longhand carries through the cascade. |
| `Style/CustomProperties.swift` (new) | An element's custom properties: parent's map + own declarations, `var()` substituted, cycles made invalid, results over 64 KiB made invalid. `substituted(into:)` fills `var()` in normal declarations and drops the ones that end up invalid (they then inherit or take their initial value). |
| `Style/ApplyStyle.swift` | New `style.apply.variables` phase between inline style and post. A node that uses variables gives up the text-only re-inherit shortcut. A change in custom properties forces children to restyle, the same way an inherited text change does. When the root font size changes, only nodes that use `rem` are marked for restyle. |
| `Style/StyleFields.swift` | Stores the computed custom properties and which outside sizes (viewport, root font) the node's declarations depend on. |
| `Style/RelativeLengths.swift` (was `FontRelativeUnits.swift`) | Adds `rem`, `vw`, `vh`. |
| `Style/DocumentMetrics.swift` (new) | Root font size + viewport size: what `rem`, `vw`, and `vh` resolve against. |
| `Style/StyleDependencies.swift` (new) | `.viewport` / `.rootFont` flags per node. |
| `Style/StyleCascade.swift` | Carries the root font size for the pass and builds `DocumentMetrics`. |
| `Style/MediaFeatures.swift` | `frameWidth` became `viewport: CGSize`. |
| `Style/StyleInvalidation.swift` | `markDependents(_:on:)`. |
| `Style/Selectors/PseudoclassSelector.swift` | `:root`. |
| `Core/Frame.swift` | `setViewport` marks `vw`/`vh` users dirty when the size changes, so a resize restyles them even when no media query flips. It also covers iframes whose height alone changes. |

## Decisions

- **Shorthands with `var()`**: Option A would split at parse time, one token per slot. It is simple, but it breaks `margin: var(--m)` when `--m` is `4px 8px`. Option B splits after substitution, the way the spec says (CSS Values 5 Appendix A). **Chose B.**
- **Root font size change**: Option A forces the whole tree, which broke `BreakpointInheritanceStopTests`: a fixed font size must stop the restyle. Option B marks only the nodes whose declarations use `rem`. **Chose B.**
- `var(` is matched without regard to letter case. The CSS-wide keywords `initial`, `inherit`, and `unset` work in custom properties.

## Not covered

- `calc()`, `vmin`/`vmax`/`svh`/`dvh`, and `lh`.
- `rem`/`vw`/`vh` inside border widths, radii, and outline widths. Those are still px-only, the same as `em` was before.

## Proof

- Tests: `Parsing/CustomPropertyParsingTests`, `Style/CustomPropertyTests`, `Style/ViewportLengthTests`, `Style/RootPseudoClassTests`, and new cases in `Style/FontRelativeLengthTests`.
- Demo: `www/css-variables-units.html`

```bash
swift run ToyStackHeadless "file://$PWD/www/css-variables-units.html" \
  --screenshot-at 0.3 /tmp/vars-800.png \
  --resize-at 0.5:400:600 --screenshot-at 1.0 /tmp/vars-400.png
```
