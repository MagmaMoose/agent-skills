---
name: macos-swiftui
description: Implement a change in a macOS SwiftUI app, proving it compiles against the macOS SDK and does not block the main thread, avoiding the TCC, concurrency-isolation, signing and project-wiring traps that have no iOS or web analogue.
---

Use the shared MagmaMoose macOS SwiftUI workflow.

Read and follow:
- `shared/macos-swiftui.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The project file (`project.yml`, `Package.swift`, or the `.xcodeproj`) — the source of truth for
  targets, build settings, deployment target and file membership
- The files neighbouring the one you are editing

Treat target-repository hard rules as blockers. Where this skill contradicts your iOS or web
instincts, this skill wins.

For tvOS, use `swiftui-build` instead — the focus-engine and availability rules there do not apply
to macOS, and the rules here do not apply to tvOS.

Expected input:
- An issue number, issue URL, or a description of the change, scoped to the macOS target.

## CRITICAL: prove it compiles, and prove it does not block (READ BEFORE ANY OTHER SECTION)

**The end goal is a change that compiles against the macOS SDK, keeps the main thread free, and
behaves like a Mac app.** Those are three bars. Most failures clear the first.

Run this before you write code and again before you finish:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk macosx swiftc -typecheck \
  -target arm64-apple-macosx<DEPLOYMENT_TARGET> \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(find <SOURCE_ROOT> -name '*.swift' -not -path '*/Tests/*' -not -name '*Tests.swift')
```

Read `<DEPLOYMENT_TARGET>` out of the project file rather than guessing — the version in `-target`
is what makes the gate real. `DEVELOPER_DIR` must be exported in the *same* command as every
`xcrun` / `xcodebuild` call, and the whole tree goes into one invocation. `#Preview` fails this
sweep under a Command Line Tools toolchain, because the macro plugin ships with Xcode; that is a
toolchain limit, not a code error.

## The second failure tier: the frozen window

A green typecheck says every symbol exists. It says nothing about which thread your filesystem work
runs on, and on macOS that is the defect that actually reaches users.

**`Task.detached` does not always detach.** Under the Swift 5 language mode a closure written
inside a `@MainActor` method can inherit that isolation, so the work hops straight back to the main
thread — no error, no warning. Measured on a real app: 1722 of 1722 samples parked in
`contentsOfDirectory` on `com.apple.main-thread`. Use an explicit `DispatchQueue` hop, which
isolation inference cannot undo, and prove it with `sample <pid>`: a main thread in
`__CFRunLoopRun` is idle and drawing; a main thread in your own code is a frozen window.

**Cloud volumes charge a round trip per listing.** 105 folders measured at 13 seconds of wall clock
for 0.14 s of CPU. Draw the list from data that costs nothing, enrich in the background.

## The third failure tier: silent denial

**A denied read of a TCC-protected location does not fail — it blocks inside `open(2)` and never
returns.** No error, no timeout, nothing to catch. The same code listed the same iCloud folder in
0.037 s from a terminal holding Full Disk Access and never returned from an app bundle without it.
Any first read of a user folder needs a deadline and a path forward, and for a non-sandboxed app
that path is `NSOpenPanel` — the user picking the folder *is* the grant.

**TCC grants bind to the code signature**, so an ad-hoc build loses them on every rebuild. That
looks like a regression in your code and is not.

## Expected behavior

Follow `shared/macos-swiftui.md` end to end. It carries the full permission-key list, the EventKit
and AppleScript specifics, the state-ownership rules, the decoding traps, the project-wiring rules,
and the definition of done.

State plainly what you could not verify. A green typecheck is a green typecheck, not a working app.
