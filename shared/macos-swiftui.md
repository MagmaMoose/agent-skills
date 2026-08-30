# macOS SwiftUI workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and
relevant `README.md` files. Treat explicit hard rules from the target repository as blockers: a
stated deployment target, a house view-model pattern, a theme layer, or a "no new dependencies"
rule in the target repo all win over this file.

You are landing a change in a macOS SwiftUI app that **compiles against the macOS SDK**, **does
not block the main thread**, and **behaves like a Mac app**. Those are three separate bars, and
most failures clear the first and miss the other two.

Four failure modes, in the order they bite:

1. **It compiles and freezes.** The main thread is doing filesystem or network work. On a local
   disk you never notice; on iCloud Drive or a network volume the window stops redrawing. This is
   the single most common macOS-specific defect and the hardest to see by reading code.
2. **It compiles and is silently denied.** macOS gates folders, Calendar, Reminders, and
   automation. A denial is not always an error — a protected folder read can block in `open(2)`
   and never return.
3. **It works on your machine only.** TCC grants bind to the code signature, so an ad-hoc build
   loses them on every rebuild, and a colleague gets an app that can read nothing.
4. **It compiles and is not in the target.** Project generators let a new file pass a
   filesystem-globbing typecheck while Xcode never sees it.

Where this file contradicts an iOS or web instinct, this file wins.

## Voice

Binding on commit messages, PR bodies, and any prose you write about the change.

- Contractions, active voice, short sentences. Say what you did and what you could not verify.
- Never claim an API is available "on macOS" unless a compiler run in *this* session said so.
- Never write "should work", "verified" or "tested" about anything you did not execute. A green
  typecheck is a green typecheck, not a working app.
- No attribution footers of any kind, no robot emojis, no "AI-generated" branding.

## 1. Prove it compiles, never assert it

### The sweep

No simulator needed. A couple of seconds on a whole app tree. Run it before you write code — so
you know whether you inherited a broken branch — and again before you finish:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk macosx swiftc -typecheck \
  -target arm64-apple-macosx<DEPLOYMENT_TARGET> \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(find <SOURCE_ROOT> -name '*.swift' -not -path '*/Tests/*' -not -name '*Tests.swift')
```

- **The version in `-target` is load-bearing and must track the project's deployment target.**
  Read the real value out of the project file rather than guessing. Raise one without the other
  and the gate silently stops enforcing what it exists for. Note there is no `-simulator` suffix,
  and no `x86_64` unless the project is still universal.
- **Export `DEVELOPER_DIR` in the same command as every `xcrun` / `xcodebuild` call.** Shell state
  does not survive between tool calls.
- **Pass the whole tree to one `swiftc` invocation.** Typechecking a single file reports
  `cannot find 'SomeViewModel' in scope` and dozens of other phantom errors, which a model then
  "fixes" by inventing duplicate declarations.
- **`#Preview` will fail this sweep under Command Line Tools.** The macro plugin ships with Xcode,
  not with the SDK, so a CLT-only toolchain reports
  `external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found`. That is a
  toolchain limit, not a code error. Either use a full Xcode `DEVELOPER_DIR`, or strip previews
  into a temp copy before sweeping, and say which you did.

### Before `xcodebuild` will run at all

`xcodebuild` needs Xcode selected *and* the licence accepted. Both bite in ways worth knowing:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

**`sudo` has its own `xcode-select` state.** If the persistent setting points at
`/Library/Developer/CommandLineTools`, then `sudo xcodebuild -license accept` fails with
`tool 'xcodebuild' requires Xcode` even when your own shell has `DEVELOPER_DIR` exported. Set the
persistent path first, in that order. Neither command is one you can run for the user — both need
a password.

Also: modern Xcode's app bundle is only ~4 GB because simulator runtimes download separately. Do
not treat a 4 GB `Xcode.app` as a truncated install, and do not wait on a `system_installd`
process to exit — check `xcrun --sdk macosx -find swiftc` instead, and check how long the process
has been alive before assuming it is yours.

## 2. The main thread is the whole ballgame

### `Task.detached` does not always detach

**Under the Swift 5 language mode, a closure written inside a `@MainActor` method can inherit that
isolation — including the closure passed to `Task.detached`.** The work then runs on the main
thread and the window stops redrawing. It compiles with no error and no warning.

Measured on a real app: listing 105 folders showed **1722 of 1722 samples parked in
`contentsOfDirectory` on `com.apple.main-thread`**.

An explicit queue hop cannot be undone by isolation inference:

```swift
private nonisolated static let ioQueue = DispatchQueue(
    label: "com.example.app.io", qos: .userInitiated, attributes: .concurrent)

nonisolated static func offMainActor<T: Sendable>(
    _ work: @escaping @Sendable () -> T
) async -> T {
    await withCheckedContinuation { continuation in
        ioQueue.async { continuation.resume(returning: work()) }
    }
}
```

**Verify it, do not assume it.** `sample <pid> 2` on the running app and read the main thread's
stack. A main thread sitting in `__CFRunLoopRun` is idle and drawing; a main thread inside your own
code is a frozen window.

### A `static` on a `@MainActor` type is main-actor isolated

This catches people repeatedly — four separate times in one real project. A `static let` or
`static func` on a `@MainActor` class inherits the isolation, which makes it:

- a warning today and a hard error under the Swift 6 language mode when read from a `Sendable`
  closure or a `nonisolated` context;
- **uncallable from a test**, because test bodies are nonisolated by default.

Mark anything pure `nonisolated`, or mark the test suite `@MainActor` when it genuinely needs the
actor:

```swift
@MainActor @Observable final class Library {
    nonisolated static let cacheURL = …      // read off the actor
    nonisolated static func key(…) -> String // pure, and called from tests
}
```

### Do not do per-item IO before first paint

A cloud or network volume charges a round trip per directory listing. Real measurement: **105
folders took 13 seconds of wall clock for 0.14 s of CPU** — 1% CPU, all of it waiting.

Draw the list from whatever is free (a name, a path component, a cached value), then enrich in a
bounded background pass and let the rows fill in. If your first pass needs the filesystem at all,
it needs a deadline (see §3).

### Other main-thread rules

- **`.task` / `.task(id:)`, never `onAppear { Task { … } }`.** The unstructured task is not
  cancelled on disappear and `onAppear` fires again on every re-navigation.
- **Guard reloads with a generation token, not a mutex.** `@MainActor` serialises property access,
  not method bodies; isolation is released at every `await`. Stamp each load, capture the stamp
  before the first `await`, and discard stale responses.
- **`NSAppleScript` must run on the main thread**, and a script that triggers a consent prompt sits
  there until the user answers. Shell out to `/usr/bin/osascript` instead.

## 3. Permissions deny in ways you would not predict

- **A denied read of a TCC-protected location does not fail — it hangs.** The process blocks inside
  `open(2)` and never returns. There is no error to catch and no timeout. Measured: the same code
  listed the same iCloud folder in **0.037 s** from a terminal holding Full Disk Access and **never
  returned** from an app bundle without it. Give any first read of a user folder a deadline
  (4 seconds is generous) and a user-facing way forward. The blocked thread cannot be cancelled;
  abandon it. One stranded thread beats a window that never draws.
- **`NSOpenPanel` selection *is* the grant.** For a non-sandboxed app, the user choosing a folder
  in an open panel grants access to it. So the fix for "cannot read that folder" is a button that
  opens the panel, not a retry.
- **A missing usage-description string means silent denial, not a prompt.** Check the Info.plist
  against what the code actually touches. The keys that matter:
  `NSCalendarsUsageDescription` and `NSCalendarsFullAccessUsageDescription` (macOS 14+),
  `NSRemindersFullAccessUsageDescription`, `NSMicrophoneUsageDescription`,
  `NSCameraUsageDescription`, `NSAppleEventsUsageDescription`,
  `NSDocumentsFolderUsageDescription` / `NSDesktopFolderUsageDescription` /
  `NSDownloadsFolderUsageDescription`, `NSNetworkVolumesUsageDescription`,
  `NSRemovableVolumesUsageDescription`, `NSFileProviderDomainUsageDescription`.
- **macOS 14 split the EventKit requests.** `requestFullAccessToReminders()` and
  `requestFullAccessToEvents()` replace `requestAccess(to:)`, which now returns denied on newer
  systems. Check `authorizationStatus(for:)` first — it never prompts, so it is safe to poll.
- **Under the hardened runtime, sending Apple events needs
  `com.apple.security.automation.apple-events` as well as the usage-description string.** Without
  it the call fails with `errAEEventNotPermitted` (-1743) even after the user says yes. Notarisation
  requires the hardened runtime, so an app that works ad-hoc can break on the way to distribution.
- **Some device state needs no permission at all.** `kAudioDevicePropertyDeviceIsRunningSomewhere`
  and `AVCaptureDevice.isInUseByAnotherApplication` report whether a device is running, not what it
  captures, so they can be polled without prompting. Prefer them over anything that opens a stream.

### TCC grants bind to the code signature

**Ad-hoc signing produces a new signature on every build, so every rebuild loses per-folder,
Calendar and automation grants.** During development this looks like a regression in your code and
is not. Full Disk Access, granted once, survives it; a stable Developer ID fixes it properly. Say
which of these the project relies on, in the README, because the next person will hit it.

## 4. Behave like a Mac app

- **Menu commands and keyboard shortcuts are not optional.** An app with no `.commands` and no
  `.keyboardShortcut` is an iOS app in a window. `.commands` is attached to the `Scene`, so it
  cannot reach a view's `@State`: either use `@FocusedValue`, or keep the shared stores in the
  `App` and have the command raise a token the window observes.
- **Right-click menus.** `.contextMenu` on a row is where a Mac user looks for anything acting on
  one item.
- **`.help(…)` on every control that is not self-evident**, especially icon-only toolbar buttons.
  Two toolbar buttons with the same SF Symbol doing different things is a real defect.
- **`Settings` scene, not a window you rolled.** `TabView` of `Form { }.formStyle(.grouped)`, a
  fixed width, and no Save button — settings apply on change. A Save button is a way to leave
  settings half-applied.
- **`ContentUnavailableView` for every empty state**, and make it say what to do next, not just
  that there is nothing there.
- **Present media as what it is.** An audio-only file in a video-sized `AVPlayerView` is a large
  black rectangle. Ask the asset:
  `let tracks = try await asset.load(.tracks); tracks.contains { $0.mediaType == .video }`. Load
  `.isPlayable` in the same call — two `await`s let a newer open interleave between them.
- **`AVPlayerView` (via `NSViewRepresentable`), not SwiftUI's `VideoPlayer`,** when anything else
  needs to drive the player: `VideoPlayer` gives you no handle on the `AVPlayer` it makes.
- **Reveal in Finder** is `NSWorkspace.shared.activateFileViewerSelecting([url])`;
  `NSWorkspace.shared.open(url)` opens the folder itself. They are different actions and users
  expect both.

## 5. State ownership and view structure

- **Pick one observation system and keep it.** `@Observable` needs `@State`, `@Bindable` and
  `@Environment(Type.self)`; `ObservableObject` needs `@StateObject` / `@ObservedObject`. Mixing
  them compiles until it does not: `@StateObject` over an `@Observable` type errors with
  `requires that 'VM' conform to 'ObservableObject'`. Match whatever the repo already uses, and
  never migrate as a drive-by.
- **`@StateObject` to own, `@ObservedObject` only for one handed in.** `@ObservedObject private var
  vm = VM()` compiles with no warning and silently rebuilds the model on every parent invalidation.
- **Mark any branching computed property `@ViewBuilder`, and use `ForEach`, not `for`.** Return
  `some View`, never `any View`.
- **`@State` seeded from an init parameter is a one-shot snapshot per view identity.** If the
  parent can swap the value, add `.id(…)` or the screen keeps showing the old one.
- **`await` cannot appear on the right of `||` or `&&`.** Restructure into an `if`; the error
  (`'await' cannot appear to the right of a non-assignment operator`) is easy to misread as an
  actor problem.
- **`defer` runs after the return value is computed.** Using it to append a footer to an array you
  are returning appends to a copy nobody sees. Restructure instead.

## 6. Decoding and the wire contract

- **`.iso8601` rejects a timestamp with no timezone offset.** A producer writing local wall-clock
  time (`2026-08-27T11:05:56`) fails to decode entirely. Know your producer's format and write a
  custom `dateDecodingStrategy` for it.
- **With `.convertFromSnakeCase`, `CodingKeys` cases are plain camelCase with no raw value.**
  `case someId = "some_id"` compiles and then fails at runtime with `keyNotFound`. Prefer explicit
  `CodingKeys` with the real wire spelling and no conversion strategy — then a renamed key is a
  compile-time conversation, not a silent nil.
- **Decode optional collections with `decodeIfPresent(…) ?? []`.** A producer that omits a key for
  an empty list otherwise fails the whole record.
- **An unrecognised enum value should not fail the file.** Give the enum a custom `init(from:)`
  that falls back.

## 7. Project wiring

- **If the project uses XcodeGen, run `xcodegen generate` after adding, renaming, moving or
  deleting any Swift file, and commit the regenerated `.xcodeproj`.** A new file on disk passes the
  `swiftc` sweep, which globs the filesystem, and is still absent from the target. Never hand-edit
  a `pbxproj`.
- **A test target needs a declared `scheme:` with `testTargets:`.** Without it the autocreated
  scheme runs zero tests and reports success.
- **macOS app icons are an `AppIcon.appiconset`** of 16/32/128/256/512 at 1x and 2x — not the
  `.brandassets` that tvOS uses. Getting it wrong is not a build error: `actool` emits a notice, the
  build stays green, and the app ships with no icon. Check for `AppIcon.icns` in the built bundle.
- **Set `LSApplicationCategoryType`, `LSMinimumSystemVersion` and `NSHumanReadableCopyright`.**
  They are free and their absence is the difference between an app and a build artefact.
- **The SDK is far ahead of the deployment target.** Anything newer than the floor needs an
  `if #available(macOS N, *)` gate.

## 8. Tests

- **macOS test targets run with no simulator**, which makes them cheap and worth having:
  `xcodebuild -project X.xcodeproj -scheme X -destination 'platform=macOS' test`.
- **Test bodies are nonisolated.** Anything on a `@MainActor` type needs that type's members
  `nonisolated`, or the suite marked `@MainActor`. See §2.
- **Scope tests to pure logic** — parsing, decoding, path handling, string escaping, sorting. A
  view is not worth a test; the function behind it is.
- **Test the escaping.** If the app interpolates user text into AppleScript, a shell command, HTML
  or SQL, that is a security boundary and it needs adversarial cases, not happy paths. Better
  still, do not interpolate: pass the payload through a file or an argument vector so there is no
  quoting problem to get wrong.
- **`#Preview { … }` does typecheck under a full-Xcode sweep.** Add one alongside any new view
  unless the repo says otherwise.

## 9. Definition of done

1. **Read the issue, then read the neighbours** — the file you are editing and the two nearest
   files beside it. Idiom-matching beats idiom-importing here.
2. **Typecheck the tree before you edit**, so you know whether you inherited a broken branch.
3. **Check availability before writing any API**, and never leave a comment claiming availability
   the compiler has not confirmed in this run.
4. **Ask what happens on a slow volume.** Any filesystem work reachable from a view is suspect
   until you know which thread it runs on.
5. **Ask what happens when permission is denied** — including the case where it hangs instead of
   failing.
6. **Match the established idioms** — the repo's observation system, its phase enum, its theme
   layer. No new dependency, no second networking path.
7. **Regenerate the project and stage it** whenever the file set changed.
8. **Typecheck the whole tree again and paste the real result** — zero errors, or the exact error
   text.
9. **Run the app and sample it** if you touched anything that reads the filesystem or the network.
   `sample <pid>` is the only cheap proof that the main thread is free.
10. **State plainly what you could not verify** — no run, no test execution, no permission prompt
    exercised, no asset-catalog validation. Do not let a green typecheck imply more.
11. **Never bump the Swift language mode, raise the deployment target, or migrate the observation
    system** as a side effect of another change.
12. **Commit in the target repo's format**, branch `<type>/<description>`, and no attribution
    trailer. Never commit or push unless asked.
