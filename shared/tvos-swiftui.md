# tvOS SwiftUI workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and
relevant `README.md` files. Treat explicit hard rules from the target repository as blockers: a
stated deployment target, a house view-model pattern, a theme layer, or a "no new dependencies"
rule in the target repo all win over this file.

You are landing a change in a tvOS SwiftUI target that **compiles against the tvOS SDK** and is
**reachable with a D-pad**. Those are two separate bars, and most failures clear the first and
miss the second.

Three failure modes, in the order they bite:

1. **The API does not exist on tvOS.** A hard compile error, so at least you find out — provided
   something actually compiled the change.
2. **The API exists and no gesture can reach it.** `.refreshable` type-checks and can never fire.
   `.onTapGesture` on a `Text` compiles and never runs. No error, no warning, a dead control.
3. **The file compiles and is not in the target.** Project generators and explicit `pbxproj` file
   lists both let a new file pass a filesystem-globbing typecheck while Xcode never sees it.

Where this file contradicts an iOS or web instinct, this file wins. Every availability claim below
was measured against the SDK, not recalled — and the measurement is cheap enough that you should
re-run it rather than trust the list.

## Voice

Binding on commit messages, PR bodies, and any prose you write about the change.

- Contractions, active voice, short sentences. Say what you did and what you could not verify.
- Never claim an API is available "on tvOS" unless a compiler run in *this* session said so.
- Never write "should work", "verified" or "tested" about anything you did not execute. A green
  typecheck is a green typecheck, not a working app.
- No attribution footers of any kind, no robot emojis, no "AI-generated" branding.

## 1. Prove it compiles for tvOS, never assert it

About a quarter of SwiftUI is `@available(tvOS, unavailable)`, and a model that has mostly seen
iOS code will reach for those APIs with total confidence. Measure the numerator yourself against
whichever SDK you have:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$(xcrun --sdk appletvsimulator --show-sdk-path)"
grep -c 'tvOS, unavailable' \
  "$SDK/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-tvos-simulator.swiftinterface"
```

That returns 1,261 on the tvOS 26.5 SDK. Against SwiftUI's public surface it works out at roughly
one declaration in four, and the ratio has been stable across releases.

A confident availability claim in a code comment is how an uncompilable API reaches a main branch:
the comment asserts tvOS support, review reads the comment instead of the compiler, and the target
stops building for everyone. Comments are not evidence. Compiler output is.

### The sweep

No simulator, no installed tvOS platform, a couple of seconds on a whole app tree. Run it before
you write code — so you know whether you inherited a broken branch — and again before you finish:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk appletvsimulator swiftc -typecheck \
  -target arm64-apple-tvos<DEPLOYMENT_TARGET>-simulator \
  -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
  $(find <SOURCE_ROOT> -name '*.swift')
```

- **The version in `-target` is load-bearing and must track the project's deployment target.** At
  `tvos17.0` the sweep correctly rejects `ToolbarItemPlacement.bottomBar`; at `tvos18.0` it does
  not. Raise one without the other and the gate silently stops enforcing what it exists for. Read
  the real value out of the project file rather than guessing.
- **Export `DEVELOPER_DIR` in the same command as every `xcrun` / `xcodebuild` call.** Shell state
  does not survive between tool calls. Where `xcode-select -p` points at
  `/Library/Developer/CommandLineTools`, a bare call fails with `tool 'xcodebuild' requires Xcode`
  or `SDK "appletvsimulator" cannot be located`. Never reach for `sudo xcode-select -s` — it needs
  a password you do not have.
- **Pass the whole tree to one `swiftc` invocation.** Typechecking a single file reports
  `cannot find 'SomeViewModel' in scope` and dozens of other phantom errors, which a model then
  "fixes" by inventing duplicate declarations.
- **A green sweep is the floor, not the ceiling.** It says every symbol exists and every type lines
  up. It says nothing about whether the remote can reach the control you just added.

### When the sweep is not enough, and what it costs

`xcodebuild` needs an installed tvOS platform. If `xcrun simctl list runtimes` is empty and
`-showdestinations` reports the runtime is not installed, the unblock is
`xcodebuild -downloadPlatform tvOS` — multi-GB, and only worth it when you actually need to run
the app. `swift build` / `swift test` are not substitutes: without a `Package.swift` they fail
outright, and with one they target the host platform anyway.

## 2. tvOS is a focus engine, not a touchscreen

The user moves focus with a D-pad and presses select. **Anything the user must reach has to be a
`Button` or a `NavigationLink`.**

### Unavailable outright

Hard compile errors, verified at `-target arm64-apple-tvos17.0-simulator` against the tvOS 26.5
SDK:

`Slider`, `Stepper`, `DisclosureGroup`, `GroupBox`, `TextEditor`, `ShareLink`, `.popover`,
`.swipeActions`, `.listRowSeparator`, `.listStyle(.insetGrouped)`, `.navigationBarTitleDisplayMode`,
`DragGesture`, `MagnificationGesture`.

Available and fine: `Form`, `Picker`, `Toggle`, `ProgressView`, `TabView`, `NavigationStack`,
`AsyncImage`, `.sheet`, `.fullScreenCover`, `.alert`, `.confirmationDialog`, `.contextMenu`.
`Menu` is exactly tvOS 17.0, so it is available only where the floor is 17.0 or higher.

For a continuous value, the replacement for a slider is a row of focusable chips over discrete
thresholds — the D-pad has no continuous axis to give you.

### The second, invisible failure tier

- `.refreshable` type-checks and can never fire. tvOS has no pull-to-refresh; give the user a
  Refresh button.
- `.searchable(text:prompt:)` is fine, and so is `placement: .automatic`. The `.toolbar`,
  `.toolbarPrincipal`, `.sidebar` and `.navigationBarDrawer` placements are tvOS-unavailable.
- `.toolbar` itself works, but `ToolbarItemPlacement.bottomBar` and `.status` are tvOS 18. If the
  screen builds its top bar as a plain `HStack`, "modernizing" it into a toolbar invents an
  untested pattern for no gain — leave it alone.
- `.onTapGesture` compiles on a `Text` and never runs, because a `Text` is not focusable. A silent
  dead control with no warning. This is the single most common way a change looks finished and is
  not.

### Focus rules

- **`.focusable()` is the escape hatch** for that last trap, and the wrong answer whenever the
  thing is really a control: a `Button` gets system activation, style hooks and accessibility
  traits for free. Use `.focusable()` only to make something *reachable*, such as a scrollable
  block of copy.
- **Every `ScrollView` needs focusable content.** Scroll position follows focus, so a scroll view
  of plain views cannot be scrolled at all, and everything past the fold is unreachable. A
  horizontal `ScrollView` of `Text` or of non-focusable cards is the usual offender.
- **`.disabled()` removes focusability.** A screen whose only controls are disabled gives the
  remote nothing to land on. Prefer keeping the control enabled, dimming it with `.opacity`, and
  explaining the situation when the user activates it.
- **Wrap off-to-one-side controls in `.focusSection()`** (tvOS and macOS only). Focus moves
  geometrically: from a poster in the left column, Up finds nothing above it, so a button at the
  far right of the top bar is simply unreachable. `.focusSection()` is what makes the jump legal.
- **Leave headroom for the focus scale, and add `.scrollClipDisabled()`** (tvOS 17.0+, no
  `#available` needed) — a scaled cell in the first or last row is otherwise sliced off. SwiftUI
  already applies the tvOS overscan safe area, so screen-edge padding is additive; match the value
  used by the file you are editing rather than inventing a new one. `.ignoresSafeArea()` belongs on
  backdrops, never on anything interactive.
- **Give a screen an explicit focus target when its focusable children are rebuilt from async
  state.** Applying a filter tears down every `NavigationLink` in a grid; if the focused one is
  gone, tvOS has no focused view and the app looks frozen. Use `@FocusState` (tvOS 15+) with
  `.defaultFocus($focus, .first)` (tvOS 16+) — the second argument is *your own* focus value, not
  a sentinel — and re-seed `focus` after the reload. The binding only works on something that is
  already focusable.
- **Do not add `.onExitCommand` unless the handler itself calls `dismiss()`.** Menu is the only
  Back on tvOS; overriding it without dismissing traps the user, which is an App Store rejection.
  Usually the right answer is to omit it entirely.
- **Never add a typed username/password form.** `TextField`, `SecureField` and `.keyboardType` all
  compile on tvOS, and entering a password on a D-pad grid takes a minute. There is also no in-app
  browser: `SafariServices` is not in the SDK, though `ASWebAuthenticationSession` *does* compile,
  so say "no in-app web page", not "no web auth". Device pairing — show a code, poll a backend — is
  the pattern that fits the remote.

### `@Environment` on a `ButtonStyle` never installs

**Never store `@Environment` or `@FocusState` on a `ButtonStyle`.** A `ButtonStyle` is not a
`View`, so the property wrapper is never installed, `isFocused` stays `false` forever, and this
compiles with zero errors and zero warnings. Nest a real `View` inside the style:

```swift
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }
    private struct Styled: View {                     // the @Environment must live on a View
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}
```

**A custom `ButtonStyle` replaces the system focus treatment**, so reimplement lift, scale, border
and shadow keyed on `isFocused` or focus goes invisible. `.buttonStyle(.card)` is not a drop-in
alternative: it is a `PrimitiveButtonStyle`, so it cannot compose with a `ButtonStyle` and it
brings its own activation behaviour.

## 3. Concurrency

- **Guard reload and pagination races with a generation token, not a mutex.** `@MainActor`
  serialises access, not method bodies; actors are reentrant and isolation is released at every
  suspension. A reload that clears `items` and resets `page` can be overtaken by an in-flight page
  fetch that resumes afterwards, appends stale rows, and bumps the page counter, so the reload's
  own response lands on the wrong page. A single `guard !inFlight` over both entry points is the
  wrong fix: it silently drops the filter change the user just made. Stamp each reload and discard
  stale responses:

```swift
private var loadID = 0
func reload(filters: Filters) async {
    loadID += 1
    let id = loadID                 // capture before the first await
    page = 1; items = []; phase = .loading
    await fetch(filters: filters, id: id, replacing: true)
}
private func fetch(filters: Filters, id: Int, replacing: Bool) async {
    do {
        let batch = try await api.list(filters: filters, page: page)
        guard id == loadID else { return }   // a newer reload superseded us
        ...
    } catch is CancellationError {
        return                               // must precede the typed-error catch
    } catch let error as APIError {
        if case .transport(let underlying) = error,
           (underlying as? URLError)?.code == .cancelled { return }
        if replacing { phase = .error(error.errorDescription ?? "Something went wrong.") }
    } catch { if replacing { phase = .error("Something went wrong.") } }
}
```

- **Cancelling a `URLSession` request throws `URLError.cancelled` (-999), not `CancellationError`.**
  `.task(id:)` cancels the in-flight load every time the id changes, so a generic catch paints
  "Something went wrong" over a completely normal user action. If your error type wraps the
  underlying error, you must bind the typed error first: `if case .transport(...)` inside a bare
  `catch` fails with `type '_ErrorCodeProtocol' has no member 'transport'`, because `error` is
  `any Error` there. Keep the ordering in the snippet above.
- **Never `try? await` anything whose failure changes what the user sees.** `try?` turns a
  `CancellationError` into `nil` and the loop keeps going. The worst case is a discarded session or
  auth call at launch — `_ = try? await client.ensureSession()` — after which every later request
  silently goes unauthenticated. Let `try await Task.sleep` throw. Where an existing polling loop
  does `try? await Task.sleep(...)` immediately followed by `if Task.isCancelled { return }`, that
  guard is what makes it exit; do not delete it while "fixing" the `try?`.
- **Use `.task` / `.task(id:)`, never `onAppear { Task { ... } }`.** The unstructured task is not
  cancelled on disappear, keeps writing state into a dead screen, and `onAppear` fires again on
  every back-navigation, stacking requests. `Task.detached` from a `@MainActor` type is not itself
  an error — it simply does not inherit the actor, so touching main-actor state inside one is the
  failure, and only language mode 6 reports it. Plain `Task { }` inherits.
- **A per-cell `.task` in a grid fires once per visible cell.** At five columns that is roughly
  fifteen concurrent tasks on first render. It is a legitimate pagination trigger; anything else
  you attach there multiplies by the same factor.
- **Do not bump `SWIFT_VERSION` as a drive-by.** Annotate every new singleton `@MainActor` or make
  it `Sendable` regardless. Under language mode 5 the compiler emits nothing for new violations, so
  an unannotated singleton is invisible debt, and raising the setting later turns each one into a
  build failure in someone else's change.

## 4. State ownership and view structure

- **`@StateObject` to own, `@ObservedObject` only for one handed in.** `@ObservedObject private var
  vm = VM()` compiles with no warning and silently rebuilds the view model on every parent
  invalidation, dropping loaded items, page and phase. In an `init` the label is
  `StateObject(wrappedValue:)`, not `initialValue:` — that one is `@State`'s, and using it is a
  hard error.
- **Do not mix `@Observable` and `ObservableObject` in one tree, and never migrate as a drive-by.**
  Both compile on tvOS 17, which is exactly why models mix them, and the mix does not work:
  `@StateObject` over an `@Observable` type errors with `requires that 'VM' conform to
  'ObservableObject'`. `@Observable` needs `@State`, `@Bindable` and `@Environment(VM.self)` — a
  different wrapper at every call site. A whole-codebase migration is a legitimate change on its
  own; a drive-by is not. Match whichever system the target repo already uses.
- **Mark any branching computed property `@ViewBuilder`, and use `ForEach`, not `for`.** Without
  the builder every branch must return the identical concrete type, and you get `function declares
  an opaque return type 'some View', but the return statements in its body do not have matching
  underlying types [#OpaqueTypeInference]`. Return `some View`, never `any View` (`type 'any View'
  cannot conform to 'View' [#ProtocolTypeNonConformance]`), and never type a property as a bare
  protocol: take a generic parameter, or apply `.buttonStyle(...)` at the call site.
- **Do not bind to `@Published private(set)`** — `setter is inaccessible`. Copy into local `@State`
  (`_draft = State(initialValue: value)`) and commit through a closure. `private(set)` is the
  convention *for view models the view must not mutate*; removing it to make a binding compile
  destroys the single write path, which is usually also what persists the value and what other
  screens observe. Some view models deliberately expose plain `@Published var` for two-way
  binding — do not "fix" those either.
- **`@State` seeded from an init parameter is a one-shot snapshot per view identity.** If the
  parent can swap the value in place, add `.id(...)` or the screen keeps showing the old one.

## 5. Decoding and the wire contract

- **With `.convertFromSnakeCase`, `CodingKeys` cases are plain camelCase with no raw value.**
  `case someId = "some_id"` compiles and then fails at runtime with `keyNotFound`, because the
  strategy has already rewritten the incoming key to `someId`. Nothing offline catches it, and it
  is the single most likely way a model breaks a wire contract while believing it made the mapping
  more explicit.
- **A hand-written `init(from:)` means adding a field is three edits**: the `CodingKeys` case, the
  decoder body, and the memberwise init. Only *Decodable* synthesis is suppressed by writing
  `init(from:)` — `encode(to:)` is still synthesized from `CodingKeys`, so do not go looking for
  one. Giving the new property a default to silence "returns from initializer without initializing
  all stored properties" turns a compile error into silent data loss.
- **Set a `dateDecodingStrategy` in the same change that adds the first `Date`.** The default is
  `.deferredToDate`, so the first ISO-8601 string the backend emits tries to decode as a `Double`
  and fails. Check the decoder before you add a timestamp; a codebase with no dates today has no
  strategy today.
- **Build URLs with `appendingPathComponent` plus `URLComponents`.** `URL(string: "/path",
  relativeTo: base)` drops the base path. Keep networking behind the existing client type; view
  models should take it as an injected default parameter, which is also the test seam.
- **A base URL read from `Info.plist` fails silently, not loudly.** The usual shape is
  `Bundle.main.object(forInfoDictionaryKey:) as? String` with a hardcoded fallback and a force
  unwrap. A typo in the *key* falls back to the hardcoded URL with no crash, so a staging build
  quietly talks to production; only an unparseable *value* crashes at launch. Verify the key
  spelling against the plist, not against the code that reads it.
- **Session tokens live in the Keychain, never in `UserDefaults`.** tvOS caps app-local defaults at
  500 KB and does not guarantee local storage survives, so nothing large or unrecoverable belongs
  there either. Use `kSecAttrAccessibleAfterFirstUnlock` unless the repo says otherwise.

## 6. Project wiring

- **If the project uses XcodeGen, run `xcodegen generate` after adding, renaming, moving or
  deleting any Swift file, and commit the regenerated `.xcodeproj`.** A classic-style `pbxproj`
  carries an explicit `PBXFileReference` per file rather than a synchronized group, so a new file
  on disk is simply not in the target and its type does not exist at Xcode build time — even
  though the `swiftc` sweep, which globs the filesystem, passes. Regeneration is reproducible
  against the committed `pbxproj`, so it is always safe to run. Never hand-edit a `pbxproj`.
- **The sweep never sees `Assets.xcassets`.** String-based `Color("…")` and `Image("…")` lookups
  typecheck clean and fall back at runtime with only a console warning. Prefer statically typed
  constants from the repo's theme layer, and never invent colours, spacing scales or typography
  outside it.
- **App icons on tvOS are an `AppIcon.brandassets` collection** of layered `.imagestack`s
  (front/middle/back, for the focus parallax) plus Top Shelf imagesets, never an `.appiconset`.
  Getting it wrong is not a build error: `actool` emits a notice, the build stays green, and the
  app ships with no icon.
- **If `Info.plist` is hand-maintained** (`GENERATE_INFOPLIST_FILE NO`), any new deep-link scheme
  must be added to `LSApplicationQueriesSchemes` or `canOpenURL` returns false with no other
  diagnostic. Deep links only open on real hardware — never claim a launcher button is verified
  from a simulator.
- **The SDK is far ahead of the deployment target.** Anything newer than the floor needs an
  `if #available(tvOS N, *)` gate. That class of mistake is caught at compile time, which is
  exactly why the unavailable-on-tvOS class matters more.

## 7. Tests and previews

- **Test bodies cannot be typechecked by the sweep, in either framework.** `import XCTest` fails
  with `no such module 'XCTest'` — it ships in
  `Platforms/AppleTVSimulator.platform/Developer/Library/Frameworks`, not in the SDK — and
  `import Testing` fails the same way; adding `-F` for it then dies on `external macro
  implementation type 'TestingMacros.TestDeclarationMacro' could not be found`. Pick a framework on
  other grounds and say plainly that the bodies are unverified.
- **Adding a test target to an XcodeGen project needs a declared `scheme:` with `testTargets:`.**
  Where a repo has no committed `.xcscheme` files, an autocreated scheme runs zero tests and
  reports success.
- **Scope tests to pure logic** — query building, model decoding, enum mapping. Running them needs
  a booted tvOS simulator. In CI, build with `-destination 'generic/platform=tvOS Simulator'` and
  test with `OS=latest`; never pin a specific `OS=` version, which exists on no runner image.
- **`#Preview { … }` does typecheck under the sweep.** With no simulator and no tests it is the
  only structured way to exercise a view offline. Add one alongside any new view unless the repo
  says otherwise.

## 8. Definition of done

1. **Read the issue, then read the neighbours** — the file you are editing and the two nearest
   files beside it. Idiom-matching beats idiom-importing here.
2. **Typecheck the tree before you edit**, so you know whether you inherited a broken branch.
3. **Check availability before writing any control or modifier**, and when it does compile, ask
   separately whether a D-pad can trigger it. Never assert availability from memory, and never
   leave a comment claiming availability the compiler has not confirmed in this run.
4. **Trace the D-pad path end to end** — what is focusable, what has focus on first render, what
   has focus after an async reload, and how Menu gets the user out.
5. **Match the established idioms** — the repo's view-model system, its phase enum, its theme
   layer, its networking client. No new dependency, no second networking path.
6. **Regenerate the project and stage it** whenever the file set changed.
7. **Typecheck the whole tree again and paste the real result** — zero errors, or the exact error
   text. Where the repo has no CI, this is the only evidence on the PR.
8. **State plainly what you could not verify** — no simulator run, no test execution, no deep-link
   check, no asset-catalog or `Info.plist` validation. Do not let a green typecheck imply more.
9. **Never bump the Swift language mode, raise the deployment target, or migrate the observation
   system** as a side effect of another change. Keep credentials and session ids in the Keychain.
10. **Commit in the target repo's format**, branch `<type>/<description>`, and no attribution
    trailer. Never commit or push unless asked.
