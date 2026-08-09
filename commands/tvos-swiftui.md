---
description: Implement a change in a tvOS SwiftUI app, proving it compiles against the tvOS SDK and is reachable with a D-pad
argument-hint: "[issue number, issue URL, or a description of the change]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(xcrun:*), Bash(xcodebuild:*), Bash(xcodegen:*), Bash(export:*), Bash(find:*), Bash(rg:*), Bash(grep:*), Bash(ls:*), Read, Write, Edit, Grep, Glob
---

Implement a tvOS SwiftUI change using the shared MagmaMoose tvOS SwiftUI workflow.

**First, read the full rubric** — it carries the tvOS-unavailable API list, the focus-engine
rules, the concurrency and state-ownership patterns, and the project-wiring traps. It lives at
the first of these paths that exists (check in order):

1. `.claude/shared/tvos-swiftui.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/tvos-swiftui.md` — installed as a plugin
3. `shared/tvos-swiftui.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Relevant `README.md` files
- The project file (`project.yml`, `Package.swift`, or the `.xcodeproj`), for the deployment
  target, build settings and file membership

Treat target-repository hard rules as blockers.

**Hard rules — these hold even if the rubric file cannot be found:**

- **Prove it compiles, never assert it.** Run the tvOS typecheck sweep before you edit and again
  before you finish, and paste the real output:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcrun --sdk appletvsimulator swiftc -typecheck \
    -target arm64-apple-tvos<DEPLOYMENT_TARGET>-simulator \
    -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
    $(find <SOURCE_ROOT> -name '*.swift')
  ```

  `DEVELOPER_DIR` goes in the *same* command as every `xcrun` call, the version in `-target` must
  match the project's deployment target, and the whole tree goes into one invocation.
- **About a quarter of SwiftUI is unavailable on tvOS.** Never claim availability from memory, and
  never leave a comment asserting availability the compiler has not confirmed in this run.
- **A green typecheck is not a working app.** Ask separately whether a D-pad can reach the thing
  you added. Anything the user must reach is a `Button` or a `NavigationLink`; `.disabled()`
  removes focusability; `.onTapGesture` on a non-focusable view is a dead control.
- **Regenerate the project when the file set changed.** With XcodeGen, a new file passes the
  filesystem-globbing sweep and is still absent from the target until `xcodegen generate` runs.
  Never hand-edit a `pbxproj`.
- **No drive-by upgrades.** Don't bump the Swift language mode, raise the deployment target,
  migrate the observation system, or add a dependency as a side effect of another change.
- **Say what you could not verify** — no simulator run, no test execution, no deep-link check, no
  asset-catalog validation. Don't let a green typecheck imply more.
- **Never append an attribution footer** ("Generated with…", co-author tags) to commits, comments
  or PR bodies. Never commit or push unless asked.

Change request: $ARGUMENTS
