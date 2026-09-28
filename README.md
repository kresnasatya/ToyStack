# ToyStack

A toy browser engine with Swift. Motivated from [Browser Engineering book](https://browser.engineering).

This project comes from curiosity to make a browser engine with Swift programming language. Mostly, we use browsers that engine build with C/C++ programming language in real-world use case. In 2012 (according to Wikipedia), there's new browser engine called Servo is built in Rust programming language.

There are three reasons why I want to make the toy browser engine with Swift programming language:

1. Curiousity and learning how hard it is make the browser engine.

2. Everything is object.

The web has Document Object Model (DOM). Swift has Object Oriented Programming. There's correlation between those terms.

> How does the DOM relate to Swift’s OOP model in the context of building a browser engine?

3. SwiftUI

To show the result of the browser engine that build with Swift, we need to wrap it into the desktop app. Luckily, I’m using Apple product like MacBook (macOS) and it has access to the SwiftUI. I don’t need to waste my time to seeking the GUI desktop engine. :)

## What It Covers

The ToyStack follows the Browser Engineering chapters. I have made the project called [Brownie](https://github.com/kresnasatya/brownie). It's a browser engine with Python (the code provided by Browser Engineering book - I just follow and make some fixes). Thanks to the Artificial Intelligence - LLM, I can port the Python code into Swift much easier step by step.

The process divided into 4 chapters:

- [x] ch01-10 - It covers Chapter 1 (Downloading Web Pages) to Chapter 10 (Keeping Data Private)

- [x] ch11-14 - It covers Chapter 11 (Adding Visual Effects) to Chapter 14 (Making Content Accessible)

- [ ] ch15 - It covers Chapter 15 (Supporting Embedded Content)

- [ ] ch16 - It covers Chapter 16 (Reusing Previous Computation)

## Domain Architecture

- **Core**: App facing controllers + frame bookkeeping + shared primitives.
- **Parsing**: Turns text into trees.
- **Style**: Cascade + compute style, media features, inline style, text direction, whitespace, forced colors.
- **Style/Selectors**: It holds the matching machinery (tag/class/id/descendant/has/RuleIndex).
- **Layouts**: Geometry/layout: block, inline, line, text, input, button layout + LayoutObject/LayoutMetrics.
- **Display**: Paint list construction, the `Draw*` commands, colors, Blend/Transform/BlurFilter/ScrollEffect, PaintTree, scrollbar, focus ring.
- **Raster**: Turning display list into pixels: compositing layers, tiles/tile store, raster scheduler + worker pool, budgets, invalidation.
- **Presentation**: The public hand-off of a finished frame to the UI.
- **Animation**: Time-based interpolation, keyframe/numeric/color/transform animations, style transitions, frame timing.
- **Accessibility**: A11y tree, highlight bounds, and the speech thread.
- **Networking**: Fetching from network.
- **Platform**: OS/renderer abstraction: `Renderer` protocol + `CGRenderer` Core Graphics implementation, `BrowserFont`, `LayerOptions`, `JSRuntime`.
- **Scheduling**: Work execution.
- **Diagnostic**: Instrumentation: `MeasureTime` (trace spans), `Profiler`
- **Resources** Bundle assets

Rough flow: **Networking** -> **Parsing** -> **Style** -> **Layouts** -> **Display** -> **Raster** -> **Presentation**, with **Core** orchestrating, **Animation/Accessibility** feeding in, and **Platform/Scheduling/Diagnostic** supporting.

## How to Run?

To run this project, build with command `swift build` then use command `swift run ToyStack` to launch ToyStack browser.
