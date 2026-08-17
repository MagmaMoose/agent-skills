---
description: Deprecated alias for /claude-skills:swiftui-build. Runs the same tvOS SwiftUI workflow under the old name
argument-hint: "[issue number, issue URL, or a description of the change]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(xcrun:*), Bash(xcodebuild:*), Bash(xcodegen:*), Bash(export:*), Bash(find:*), Bash(rg:*), Bash(grep:*), Bash(ls:*), Read, Write, Edit, Grep, Glob
---

`/claude-skills:tvos-swiftui` has been renamed to `/claude-skills:swiftui-build`, so every
workflow here reads `{noun}-{verb}`. This alias exists so existing headless installs and scripts
keep working, and it will be removed in a future release.

Say once, before you start, that the command is deprecated and the new name is
`/claude-skills:swiftui-build`. Then run the tvOS SwiftUI workflow exactly as the new command
defines it. Read the first of these that exists and follow it in full:

1. `${CLAUDE_PLUGIN_ROOT}/commands/swiftui-build.md` — installed as a plugin
2. `.claude/commands/swiftui-build.md` — headless runs (installed into the clone)
3. `commands/swiftui-build.md` — working inside the agent-skills checkout

If none of them exist, go straight to the rubric instead, at the first of
`.claude/shared/swiftui-build.md`, `${CLAUDE_PLUGIN_ROOT}/shared/swiftui-build.md`, or
`shared/swiftui-build.md`, and follow that.

Do not duplicate or reinterpret the workflow here. This file only forwards.

Change request: $ARGUMENTS
