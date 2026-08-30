---
description: Implement a macOS SwiftUI change, proving it compiles against the macOS SDK and does not block the main thread
argument-hint: "[issue number, issue URL, or a description of the change]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(xcrun:*), Bash(xcodebuild:*), Bash(xcodegen:*), Bash(export:*), Bash(find:*), Bash(rg:*), Bash(grep:*), Bash(ls:*), Bash(sample:*), Bash(codesign:*), Bash(plutil:*), Read, Write, Edit, Grep, Glob
---

Implement a macOS SwiftUI change using the shared MagmaMoose macOS SwiftUI workflow.

**First, read the full rubric** — it carries the permission-key list, the concurrency-isolation
traps, the signing and TCC rules, the state-ownership patterns and the project-wiring traps. It
lives at the first of these paths that exists (check in order):

1. `.claude/shared/macos-swiftui.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/macos-swiftui.md` — installed as a plugin
3. `shared/macos-swiftui.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The project file (`project.yml`, `Package.swift`, or the `.xcodeproj`), for the deployment
  target, build settings and file membership

Treat target-repository hard rules as blockers. For tvOS use `/swiftui-build` instead.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Prove it compiles, never assert it.** Run the macOS typecheck sweep before you edit and again
  before you finish, and paste the real output:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcrun --sdk macosx swiftc -typecheck \
    -target arm64-apple-macosx<DEPLOYMENT_TARGET> \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    $(find <SOURCE_ROOT> -name '*.swift' -not -path '*/Tests/*' -not -name '*Tests.swift')
  ```

  `DEVELOPER_DIR` goes in the *same* command as every `xcrun` call, the version in `-target` must
  match the project's deployment target, and the whole tree goes into one invocation. `#Preview`
  fails this sweep under a Command Line Tools toolchain — that is the missing Xcode macro plugin,
  not your code.

- **A green typecheck is not a working app. Ask which thread your IO is on.** `Task.detached` does
  NOT detach when the closure is written inside a `@MainActor` method under the Swift 5 language
  mode — it inherits the isolation and blocks the main thread. Use an explicit `DispatchQueue` hop
  and confirm with `sample <pid>`: `__CFRunLoopRun` on the main thread means idle and drawing.

- **Never do per-item filesystem work before first paint.** On iCloud Drive, 105 directory listings
  measured 13 seconds of wall clock for 0.14 s of CPU. Draw from free data, enrich in the
  background.

- **A denied read of a protected folder hangs rather than failing.** It blocks in `open(2)` with no
  error. Give any first read of a user folder a deadline and offer `NSOpenPanel`, because the user
  picking the folder is what grants access. Never assume a missing usage-description string
  produces a prompt — it produces silent denial.

- **A `static` on a `@MainActor` type is main-actor isolated.** That is a Swift 6 error from a
  nonisolated context and makes the member uncallable from tests. Mark pure members `nonisolated`.

- **TCC grants bind to the code signature.** Ad-hoc signing loses folder, Calendar and automation
  grants on every rebuild. Say so rather than debugging it as a code regression.

- **Regenerate the project when the file set changed.** With XcodeGen, a new file passes the
  filesystem-globbing sweep and is still absent from the target until `xcodegen generate` runs.
  Never hand-edit a `pbxproj`.

- **Behave like a Mac app.** Menu commands, keyboard shortcuts, context menus, `.help(…)` on
  icon-only controls, a `Settings` scene that applies on change, and media presented as what it
  actually is — check for a video track before showing a video player.

- **Never interpolate user text into AppleScript, a shell command or HTML.** Pass it through a file
  or an argument vector. If you must escape, escape backslashes before quotes, and test it
  adversarially.

- **No drive-by upgrades.** Don't bump the Swift language mode, raise the deployment target,
  migrate the observation system, or add a dependency as a side effect of another change.

- **Say what you could not verify** — no run, no test execution, no permission prompt exercised, no
  notarisation check. Don't let a green typecheck imply more.

- **Never append an attribution footer** ("Generated with…", co-author tags) to commits, comments
  or PR bodies. Never commit or push unless asked.

Change request: $ARGUMENTS
