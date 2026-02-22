# Living Documentation

This document catalogs all the major entities/components in the [brownie - Python-based web browser](https://github.com/kresnasatya/brownie).


## Overview

This is a web browser built from scratch using Python with graphics/rendering provided by Skia, SDL2, and OpenGL.
It implements network request, HTML parsing, CSS parsing, layout engine, JavaScript execution, and basic browser features like tabs, navigation, and form handling.

## Core Entities

### 1. URL (`url.py`)

**Purpose**: Handles URL parsing, resolution, and HTTP/HTTPS network requests.

**Responsibilities**:
- Parse URLs into scheme, host, port, and path components.
- Make HTTP and HTTPS requests using sockets and SSL
- Handle cookies with SameSite attribute support
- Resolve relative URLs againsts a base URL
- Compute URL origins for security (CSP, CORS)

**Key Methods**:
- `__init__(url)` - Parse URL string
- `request(referrer, payload)` - Make HTTP request with cookie support
- `resolve(url)` - Resolve relative/absolute URLs
- `origin()` - Get origin for security checks

---

### 2. HTMLParser (`html_parser.py`)

**Purpose**: Parse HTML text into a DOM tree of Element and Text nodes.

**Responsibilities**:
- Tokenize HTML into tags and text
- Handle self-closing tags
- Build proper parent-child relationships
- Implicit tag insertion (html, head, body)
- Parse tag attributes

**Key Methods**:
- `parse()` - Main parsing entry point
- `add_text()` - Create text nodes
- `add_tag()` - Create element nodes
- `get_attributes()` - Parse tag attributes
- `implicit_tags()` - Add missing structural tags

---

### 3. CSSParser (`css_parser.py`)

**Purpose**: Parse CSS text into selectors and style rules.

**Responsibilities**:
- Parse CSS selectors (tag and descendant)
- Parse CSS property declarations
- Support error recovery in malformed CSS
- Compute selector priority/specifity

**Key Methods**:
- `parse()` - Parse full CSS stylesheet
- `selector()` - Parse selector
- `body()` - Parse CSS rule body
- `word()`, `literal()`, `pair()` - Token helpers

**Classes**:
- `TagSelector` - Matches elements by tag name
- `DescendantSelector` - Matches descendant relationships

---

### 4. Element and Text (`element.py`, `text.py`)

**Purpose**: DOM node representation.

**Element**:
- Represents HTML tags
- Stores tag name and attributes
- Maintains parent and children
- Store computed styles
- Store animations

**Text**:
- Represents text nodes in the DOM
- Store text content

---

### 5. DocumentLayout (`document_layout.py`)

**Purpose**: Root layout node for the entire document.

**Responsibilities**:
- Create initial BlockLayout for the HTML root
- Set document dimensions
- Root of the layout tree

---

### 6. BlockLayout (`block_layout.py`)

**Purpose**: Layout block-level elements and inline content.

**Responsibilities**:
- Layout block children vertically
- Layout inline children with line wrapping
- Handle text measurement and word wrapping
- Create LineLayout and TextLayout children
- Handle input elements
- Paint background colors and border-radius

**Key Methods**:
- `layout()` - Recursively layout children
- `layout_mode()` - Determine block vs inline layout
- `word()` - Add a word to current line
- `new_line()` - Start a new line
- `recurse()` - Recursively layout inline content
- `paint()` - Generate paint commands
- `self_rect()` - Get layout rectangle

---

### 7. LineLayout (`line_layout.py`)

**Purpose**: Represents a single line of inline content.

**Responsibilities**:
- Hold TextLayout children
- Calculate line height

---

### 8. TextLayout (`text_layout.py`)

**Purpose**: Layout for a single word or text fragment.

**Responsibilities**:
- Store text node and word
- Calculate text dimensions
- Paint text

---

### 9. InputLayout (`input_layout.py`)

**Purpose**: Layout for input elements and buttons.

**Responsibilities**:
- Fixed width layout for form inputs
- Paint input background
- Paint input text or placeholder

### 10. JSContext (`js_context.py`)

**Purpose**: JavaScript execution environment using dukpy (JavaScript interpreter).

**Responsibilities**:
- Initialize JavaScript interpreter
- Export Python functions to JavaScript
- Execute JavaScript code
- Handle DOM-JavaScript bindings
- Implement XMLHttpRequest
- Implement setTimeout and requestAnimationFrame
- Event dispatch to JavaScript

**Key Methods**:
- `run()` - Execute JavaScript code
- `querySelectorAll()` - DOM query
- `getAttribute()` - Get element attribute
- `innerHTML_set()` - Modify innerHTML
- `XMLHttpRequest_send()` - Make XHR
- `setTimeout()` - Schedule callback
- `requestAnimationFrame()` - Request animation frame
- `dispatch_event()` - Dispatch event to JS

---

### 11. Tab (`tab.py`)

**Purpose**: Represents a browser tab containing a loaded web page.

**Responsibilities**:
- Load and render web pages
- Handle click events (links, forms, inputs)
- Handle keyboard input
- Manage scroll position
- Run animation frames
- Apply CSS styles
- Build layout tree
- Generate display list (paint commands)
- Manage browser history
- Enforce Content Security Policy

**Key Methods**:
- `load()` - Load a URL
- `click()` - Handle click events
- `keypress()` - Handle keyboard input
- `render()` - Style, layout, and paint
- `run_animation_frame()` - Run RAF callbacks and animations
- `draw()` - Execute paint commands
- `submit_form()` - Handle form submission
- `go_back()` - Navigate back in history

**State**:
- `url` - Current URL
- `scroll` - Scroll position
- `history` - Navigation history
- `focus` - Focused element
- `nodes` - DOM tree
- `rules` - CSS rules
- `document` - Layout tree
- `display_list` - Paint commands

---

### 12. Chrome (`chrome.py`)

**Purpose**: Browser chrome (UI elements outside the web content)

**Responsibilities**:
- Draw tab bar
- Draw URL/address bar
- Draw back button
- Draw new tab button
- Handle chrome click events
- Handle keyboard input in address bar

**UI Elements**:
- New tab button (+)
- Tab indicators
- Back button (<)
- Address bar

---

### 13. Browser (`browser.py`)

**Purpose**: Main browser application managing window, tabs, and rendering.

**Responsibilities**:
- Create SDL2 window and OpenGL context
- Initialize Skia graphics context
- Manage multiple tabs
- Handle user input (click, key, scroll)
- Compositing layer management
- Rasterization and drawing
- Animation frame scheduling
- Thread management for tab tasks

**Key Methods**:
- `new_tab()` - Create new tab
- `handle_click()` - Handle mouse click
- `handle_key()` - Handle keyboard input
- `handle_down()` - Handle scroll down
- `composite()` - Create composited layers
- `raster_chrome()`, `raster_tab()` - Rasterize content
- `draw()` - Draw to screen
- `commit()` - Receive tab update
- `schedule_animation_frame()` - Schedule RAF

**Dependencies**:
- **SDL2** - Window creation and event handling
- **Skia** - 2D graphics rendering
- **OpenGL** - Hardware-accelerated rendering

---

### 14. Paint Commands (`draw_*.py`)

**Purpose**: Individual drawing options.

**Types**:
- `DrawRect` - Draw rectangle
- `DrawRRect` - Draw rounded rectangle
- `DrawLine` - Draw line
- `DrawOutline` - Draw border/outline
- `DrawText` - Draw text
- `DrawCompositedLayer` - Draw composited layer

---

### 15. Visual Effects (`visual_effect.py`, `blend.py`)

**Purpose**: CSS visual effects.

**Effects**:
- Border radius
- Blending modes
- Layer compositing

---

### 16. CompositedLayer (`composited_layer.py`)

**Purpose**: Graphics layer for compositing.

**Responsibilities**:
- Rasterize paint commands to a texture
- Enable efficient re-rasterization
- Support GPU acceleration

---

### 17. Task & TaskRunner (`task.py`, `task_runner.py`)

**Purpose**: Asynchronous task execution.

**Responsibilities**:
- Run tasks on background thread
- Serialize access to tab data
- Prevent concurrent modifications

---

### 18. DOM Utilities (`dom_utils.py`)

**Purpose**: Shared utility functions.

**Functions**:
- `tree_to_list()` - Flatten tree to list
- `style()` - Apply CSS styles
- `cascade_priority()` - CSS cascade priority
- `paint_tree()` - Generate paint commands
- `print_tree()` - Debug print
- `get_font()` - Get font from Skia

---

### 19. Animation (`numeric_animation.py`)

**Purpose**: CSS transitions and animations.

---

### 20. CommitData (`commit_data.py`)

**Purpose**: Data package sent from tab to browser thread.

**Contains**:
- URL
- Scroll position
- Document height
- Display list

---

## External Dependencies

### Graphics & Windowing

- **Skia** - 2D graphics library (canvas, paths, text, effects)
- **SDL2** - Window creation, event handling, OpenGL context
- **OpenGL** - Hardware-accelerated rendering

### JavaScript

- **Dukpy** - JavaScript interpreter

## Network

- **socket** - TCP connections
- **ssl** - HTTPS/TLS

---

## Data Flow

### Loading a Web Page

1. User enters URL or clicks link
2. Tab calls `URL.request()` to fetch HTML
3. HTMLParser builds DOM tree
4. CSSParser parses linked stylesheets
5. JSContext intializes and runs scripts
6. Tab applies styles to DOM (`style()`)
7. DocumentLayout creates layout tree
8. BlockLayout recursively computes positions
9. Paint tree generates display list
10. Tab commits data to Browser
11. Browser composites, rasterizes, and draws

### Rendering Pipeline

1. **Style** - Apply CSS rules to DOM nodes
2. **Layout** - Compute positions and sizes
3. **Paint** - Generate draw commands
4. **Composite** - Group into layers
5. **Rasterize** - Draw layers to textures
6. **Draw** - Composite to screen

### Event Handling

1. Browser receives input event
2. Browser forwards Chrome or Tab
3. Tab executes JavaScript event handlers
4. If not prevented, perform default action
5. Schedule animation frame if needed

---

## Architecture Notes

### Threading

- **Browser thread** - Handle events, drawing, tab management
- **Tab thread** - Runs tab tasks (loading, rendering, JS)
- Uses locks to protect shared state

### Security

- Content Security Policy (CSP)
- Cookie SameSite attribute
- CORS enforcement for XMLHttpRequest

### Performance

- Composited layers for efficient re-rasterization
- Dirty flags (needs_style, needs_layout, needs_paint)
- Asynchronous script loading and execution
- GPU-accelerated rendering via OpenGL

---

## Swift Port Considerations

### Replacements for Third-Party Libraries

#### Skia -> **Core Graphics + Core Text * Metal**

- **Core Graphics** - 2D drawing, paths, images, colors
- **Core Text** - Text layout and font rendering
- **Metal** - Hardware-accelerated graphics (replaces OpenGL)
- **Core Animation** - Compositing and animations (native layer support!)

#### SDL2 -> **AppKit / SwiftUI**

- **NSWindow / NSView** - Window management
- **NSEvent** - Event handling
- Metal-backed view for rendering

#### dukpy -> **JavaScriptCore**

- Native JavaScript engine built into iOS/macOS
- `JSContext` - JavaScript execution environment

#### Network -> **URLSession**

- Native HTTP/HTTPS client
- Cookie management built-in
- Support TLS out of the box

### Advantages of Swift Implementation

1. **No third-party dependencies** - All graphics, windowing, and JavaScript are built into the OS
2. **Better performance** - Native Metal rendering vs OpenGL
3. **Modern concurrency** - async/await vs threading
4. **Type safety** - Compile-time safety
5. **Native UI** - Better integration with macOS

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
