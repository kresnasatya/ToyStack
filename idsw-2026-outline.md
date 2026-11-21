# IDSW 2026 Talk Plan

## Title options

1. **Building a Browser Engine with AI Is Harder Than You Think** (recommended)
2. **AI Can Write a Browser Engine. It Can't Keep One Alive.**
3. **Programming Is Not Dead: Lessons from Building a Browser Engine with AI**
4. **Code Is Cheap Now. Understanding Is Not.** (subtitle: a browser engine in Swift)
5. **Where AI Stops: Building a Browser Engine in Swift**

Keep "Swift" and "browser engine" in the title or subtitle so it still matches the accepted CFP abstract.

## Terms

- Code style = how code is written (AGENTS.md: max 4 parameters, max 4 stored properties, one concept per file, explicit types).
- Code architecture = how pieces are split and connected (Domain Architecture in README).
- Data shape / paradigm = enum, struct, class or protocol (plans/refactoring/oop-findings.md).
- Umbrella word: "guardrails".

## Main message

AI removes the cost of typing code. It does not remove the cost of deciding the
shape of the code, finding why it is slow, or understanding what it does.

## Outline

1. Hook: the myth ("programming is dead") and the bet: build a browser engine.
2. Why Swift, why a browser engine (CFP abstract).
3. Journey of a page: URL -> network -> HTML parse -> DOM -> CSS -> style -> layout -> paint -> raster -> screen. One diagram; mark what was easy and hard for AI.
4. Guardrails, layer 1: code style (two rules, and what went wrong before them).
5. Guardrails, layer 2: code architecture (one concept per file, domain folders, tests first).
6. Story A: smooth scrolling (Canvas used in the wrong place). Before/after with numbers from browser.trace.
7. Story B: the paradigm was wrong, not just the code. Invalidation and smooth resize. "Everything is object" -> closed sets as enums, flat display list, declared inputs.
   Slogan: protocols for open seams, sum types for closed data, flat arrays for hot passes.
8. Working with AI: you write tests and decide the shape, AI drafts, you type the code yourself to understand it.
9. Takeaway in three sentences. Q&A.

## Open questions

- Slot length (20 / 30 / 45 min)?
- Story A: what exactly went wrong with Canvas, and what was the fix?
- Where did AI default to a wrong pattern (e.g. class hierarchy)? Concrete examples.
- Audience: web developers or Swift developers?
