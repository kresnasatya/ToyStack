# A2 complete — display list is one enum

Companion to [oop-refactor-1-2-display-op.md](./oop-refactor-1-2-display-op.md), step A2.

## What landed

| Sub-step | Change |
|---|---|
| 2a | `BrowserVisualEffect` and all subclasses own `[DisplayOp]`; cast loops replaced with `child.execute(renderer:)`; `needsCompositing`, `parent`, `addParentPointers`, `maxRectBottom` removed |
| 2b | All constructor call sites emit `DisplayOp`; `scrollbarBarRect`, `drawCursor`, `scrollbarCommands`, `Chrome.paint` return ops |
| 2c | `LayoutObject.paint` / `paintEffects` / `applyPaintEffects`, `PaintTree`, caches, `Frame.displayList`, `RasterScene`, `FrameDisplay*`, `FrameRender` use `[DisplayOp]` |
| 2d | `Browser.computeComposite` is one `walkDisplayItems` pass; `CompositedLayer` stores `[DisplayOp]`, merges by `LayerID.effect` scope, derives `absoluteBounds` from `ancestorChain` |
| 2e | All draw loops call `op.execute(renderer:)`; no `DisplayCommand` casts |
| 2f | `displaySignature` switches on `DisplayOp`; `PaintCacheTests`, `PaddingLayoutTests`, `PaintCullingTests`, `LayoutOracleTests` pattern-match cases |
| 2g | `DisplayItem`, `DisplayCommand`, eight `Draw*` files, and `ScrollbarBar` deleted; `treeToList(DisplayItem)` removed |
| labels | Every multi-payload `DisplayOp` case carries argument labels; `.effect` stays unlabeled |

`ClipShape` and `CompositedLayer` are public, `BrowserColor` is `Hashable`.

## A2 gate

| Check | Result |
|---|---|
| `swift build` | exit 0 |
| `swift test` | 189 tests in 26 suites passed |
| `www/ch11/index.html` screenshot | byte-identical to the A1 baseline |
| `www/ch11/exercise-11-3.html` screenshot | byte-identical to the A1 baseline |

Baseline was built from `HEAD` (`refactor: model draw items as one value type`) in a temporary worktree, then removed.

Pixel parity caught one real regression before it shipped: `Blend` and `BlurFilter` initially passed the outer `renderer` into their `drawLayer` closure instead of the closure's `r`, which dropped blur/opacity. Both now use `r`.

## Left for later steps

- `profiling.md` note: `paint.range.copy` metric is gone from the table but the measurement call remains in `PaintTree`; A3 removes the call.
- `PaintTree` still copies child ranges (`Array(displayList[childStart...])`); B3 removes the copies when effects flatten to `beginEffect` / `endEffect`.
- Phase B still replaces the `BrowserVisualEffect` class tree with `EffectScope` values and `DisplayEffect`.
