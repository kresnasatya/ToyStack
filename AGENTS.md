# ToyStack

This is a project to build a toy browser engine with Swift programming language.

## Information

I'm a beginner on Swift programming language and browser engineering.

## Code Architecture

- Each class / struct / function restricted to have maximum 4 parameters.
- Always put explicit type information to make Swift compiler fast to compile. Reference: https://developer.apple.com/documentation/xcode/improving-build-efficiency-with-good-coding-practices#Provide-the-Swift-compiler-with-explicit-type-information
- One concept per file. Name each file after the main type it holds, don't leave a type inside a file named after something else (e.g. `BrowserFont` lives in `BrowserFont.swift`, NOT in `DOMUtils.swift`).
- When a file grows several unrelated types, split each into its own file. A type belongs where its name says its belong, NOT where it happened to be first written.
- Only small helpers that are truly support one type may share that type's file, grouped under a `// MARK: -` section (e.g. `ScrollbarGeometry` and `scrollbarBarRect` in `Scrollbar.swift`).

## Expected Result

This project is intended to be used as learning purpose to understand how to make the actual browser engine with Swift programming language. The thinking process must be experienced web browser engineer. The output of code must be high quality and must follow the **Code Architecture** section.

## Workflow

1. Work in `main` branch directly instead of separated branch.

2. Each time I give a prompt, act as a guide and show me the code changes I need to make. **When modifying existing code, always show the changes as a unified diff (+/-) rather than separate Old/New code blocks.**

3. When facing with **exercise**, create a html example for proof of exercise implementation in `www` directory.
 
4. You're NOT ALLOWED to edit the code. I (the human) will do it myself to get better understanding.

5. Avoid jargon!

6. When a task touches multiple files, list which files will change and why before writing any code. If there's a real design decision, present it as Option A / Option B with a recommendation and the trade-off — don't pick silently.

7. Break work into small, ordered steps that each leave the project building.

8. When showing code changes, always unified diff format with `-` for removed lines and `+` for added lines. **DO NOT present separate `Old` and `New` code sections.** DO NOT duplicate the unchanged code outside the diff. Include only the relevant surrounding context needed to understand the change.

Example:

```diff
- let role = oldRole
+ let role = newRole
```

For multi-file changes, group the diffs by file and include the file path before each diff. The output must remain directly applicable to the existing codebase.

9. Reference existing code by file:line so I can navigate to it.

10. Save it in markdown file in the `plans` directory.

## Debugging

To debug browser engine, we use `browser.trace` in the root directory. It means measurement is critical here.

## Additional Information

If you're using any colors that are not exist in this browser engine (@Sources/Engine/PaintCommand.swift) then put those colors into the markdown file.
