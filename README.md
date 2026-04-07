# ToyStack

A toy browser engine with Swift. Motivated from [Browser Engineering book](https://browser.engineering).

This project comes from curiosity to make a browser engine with Swift programming language. We have browser engines that built with programming languages like C/C++ that used in real-world use case. In 2012 (according to Wikipedia), the browser engine called Servo is built in Rust programming language.

There are three reasons why I want to make the toy browser engine with Swift programming language:

1. Curiosity - as I mention above.

2. Everything is object.
Everything is object. The web has Document Object Model (DOM). Swift has Object Oriented Programming. That’s it! I don’t want to explain it more detail. Ask Claude!

> How does the DOM relate to Swift’s OOP model in the context of building a browser engine?

3. SwiftUI

In the end, to show the result of the browser engine that build with Swift, we need to wrap it into the desktop app. Luckily, I’m using Apple product like MacBook (macOS) and it has access to the SwiftUI. I don’t need to waste my time to seeking the GUI desktop engine. :)

## What It Covers

The ToyStack follows the Browser Engineering chapters. I have made the project called [Brownie](https://github.com/kresnasatya/brownie). It's a browser engine with Python (the code provided by Browser Engineering book - I just follow and make some fixes). Thanks to the Artificial Intelligence - LLM, I can port the Python code into Swift much easier step by step.

The process divided into 4 chapters:

[X] ch01-10 - It covers Chapter 1 (Downloading Web Pages) to Chapter 10 (Keeping Data Private)
[X] ch11-14 - It covers Chapter 11 (Adding Visual Effects) to Chapter 14 (Making Content Accessible)
[ ] ch15 - It covers Chapter 15 (Supporting Embedded Content)
[ ] ch16 - It covers Chapter 16 (Reusing Previous Computation)

## NOTE

To run this project, use the command `swift run`.

To run the `right-to-left` text mode, use this command below.

```sh
swift run ToyStack -- --rtl
```
