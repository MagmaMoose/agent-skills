---
name: swiftui-build
description: Implement a change in a tvOS SwiftUI app, proving it compiles against the tvOS SDK and is reachable with a D-pad, avoiding the availability, focus-engine, concurrency and project-wiring traps that have no iOS or web analogue.
---

Use the shared MagmaMoose tvOS SwiftUI workflow.

Read and follow:
- `shared/swiftui-build.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The project file (`project.yml`, `Package.swift`, or the `.xcodeproj`) — the source of truth for
  targets, build settings, deployment target and file membership
- The files neighbouring the one you are editing

Treat target-repository hard rules as blockers. Where this skill contradicts your iOS or web
instincts, this skill wins.

Expected input:
- An issue number, issue URL, or a description of the change, scoped to the tvOS target.

## CRITICAL: prove it compiles for tvOS, never assert it (READ BEFORE ANY OTHER SECTION)

**The end goal is a change that compiles against the tvOS SDK and is reachable with a D-pad.**
About a quarter of SwiftUI is `@available(tvOS, unavailable)`, and a model that has mostly seen
iOS code will reach for those APIs with total confidence. A confident availability claim written
into a code comment is how an uncompilable API reaches a main branch: the comment asserts tvOS
support, review reads the comment instead of the compiler, and the target stops building.

Run this before you write code and again before you finish. No simulator, no installed tvOS
platform, a couple of seconds on a whole app tree:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk appletvsimulator swiftc -typecheck \
  -target arm64-apple-tvos<DEPLOYMENT_TARGET>-simulator \
  -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
  $(find <SOURCE_ROOT> -name '*.swift' -not -path '*/Tests/*' -not -path '*Tests.swift')
```

Read `<DEPLOYMENT_TARGET>` out of the project file rather than guessing — the version in `-target`
is what makes the gate real. At `tvos17.0` the sweep correctly rejects
`ToolbarItemPlacement.bottomBar`; at `tvos18.0` it does not.

`DEVELOPER_DIR` must be exported in the *same* command as every `xcrun` / `xcodebuild` call, and
the whole tree goes into one invocation. Details, and the reason a single-file typecheck invents
phantom errors, are in `shared/swiftui-build.md`.

## The second failure tier

A green typecheck is the minimum bar for opening a PR, not proof of a working app. tvOS is a focus
engine: plenty of SwiftUI compiles and then has no gesture behind it. `.refreshable` can never
fire. `.onTapGesture` on a `Text` never runs, because a `Text` is not focusable — a dead control
with no error and no warning. Anything the user must reach has to be a `Button` or a
`NavigationLink`, and `.disabled()` removes focusability entirely.

## Expected behavior

1. **Read the issue, then read the neighbours** — the file you are editing and the two nearest
   files beside it. Idiom-matching beats idiom-importing here.
2. **Typecheck the tree before you edit**, so you know whether you inherited a broken branch.
3. **Check availability before writing any control or modifier** — and when it does compile, ask
   separately whether a D-pad can trigger it. Never assert availability from memory.
4. **Trace the D-pad path end to end** — what is focusable, what has focus on first render, what
   has focus after an async reload, and how Menu gets the user out.
5. **Match the established idioms** — the repo's view-model system, phase enum, theme layer and
   networking client. No new dependency, no second networking path, no invented colours or
   spacing.
6. **Regenerate the project and stage it** whenever the file set changed. If the project uses
   XcodeGen, a new file on disk passes the filesystem-globbing sweep and is still absent from the
   target until `xcodegen generate` runs. Never hand-edit a `pbxproj`.
7. **Typecheck the whole tree and paste the real result** — zero errors, or the exact error text.
8. **State plainly what you could not verify** — no simulator run, no test execution, no deep-link
   check, no asset-catalog or `Info.plist` validation. Don't let a green typecheck imply more.
9. **Never bump the Swift language mode, raise the deployment target, or migrate the observation
   system** as a side effect of another change. Keep credentials and session ids in the Keychain.
10. **Commit in the target repo's format**, branch `<type>/<description>`, and no attribution
    trailer of any kind. Never commit or push unless asked.
