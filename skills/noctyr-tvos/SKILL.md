---
name: noctyr-tvos
description: Implement a GitHub issue in the noctyr tvOS app (SwiftUI, tvOS 17, XcodeGen), avoiding the Swift-language, focus-engine, concurrency and project-wiring traps that have no iOS or web analogue.
---

Use this for any change under `ios/` in `MagmaMoose/noctyr`. Backend (`backend/`, FastAPI) is out
of scope except where the wire contract is shared.

Read and follow:
- The target repository's `README.md`
- `ios/Noctyr/project.yml` — the source of truth for targets, build settings and file membership
- The files neighbouring the one you are editing — noctyr has no `CLAUDE.md`, no `AGENTS.md`, no
  `CONTRIBUTING.md`, no CI and no tests, so this skill plus the existing 18 Swift files **are**
  the conventions
- `backend/src/models/content.py` whenever the change touches `Noctyr/Models/Content.swift`

Treat target-repository hard rules as blockers. Where this skill contradicts your iOS or web
instincts, this skill wins — every rule below was verified against the tvOS SDK, not recalled.

Expected input:
- An issue number, issue URL, or a description of the change. Route on the `ios` label
  ("tvOS / SwiftUI work"). Issues often carry both `ios` and `backend` (#13 is `backend,ios,mvp`);
  when both are present the wire contract moves on both sides, so `Models/Content.swift` and
  `backend/src/models/content.py` change together.

## CRITICAL: prove it compiles for tvOS, never assert it (READ BEFORE ANY OTHER SECTION)

**The end goal is a change that compiles against the tvOS SDK and is reachable with a D-pad.**
About a quarter of SwiftUI is `@available(tvOS, unavailable)`, and a model that has mostly seen
iOS code will reach for those APIs with total confidence.

This is not hypothetical. On `main`, `ios/Noctyr/Noctyr/Views/FilterPanelView.swift:86` uses
`Slider(value:in:step:)` under a comment asserting "Basic Slider init (broadly available incl.
tvOS)". `Slider` is unavailable in tvOS; the app target does not build on `main` today. A false
availability claim, written confidently, shipped past review because nothing checked.

Run this before you write code and again before you finish. No simulator, no installed tvOS
platform, ~2s on the whole tree:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios/Noctyr && xcrun --sdk appletvsimulator swiftc -typecheck \
  -target arm64-apple-tvos17.0-simulator \
  -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
  $(find Noctyr -name '*.swift')
```

The `17.0` in `-target` is load-bearing and must track `deploymentTarget` in `project.yml`: at
`tvos17.0` the sweep correctly rejects `ToolbarItemPlacement.bottomBar`, at `tvos18.0` it does
not. Raise one without the other and the gate silently stops enforcing what it exists for.

There is no CI anywhere in the repo — `.github/workflows/` does not exist, backend included
(issues #37/#38 add it; both already have open `ci/…` branches, so this line may go stale). Until
then the typecheck output you paste is the **only** evidence on a PR. A green typecheck is the
minimum bar for opening one, not proof of a working app — see "the second failure tier" below.

## Build and target wiring

- **Export `DEVELOPER_DIR` in the same command as every `xcrun`/`xcodebuild` call.** Shell state
  does not survive between tool calls. `xcode-select -p` here is `/Library/Developer/
  CommandLineTools`, so a bare call fails with `tool 'xcodebuild' requires Xcode` or `SDK
  "appletvsimulator" cannot be located`. Never try `sudo xcode-select -s` — it needs a password.
- **Pass the whole tree to one `swiftc` invocation.** Typechecking a single file reports
  `cannot find 'CatalogViewModel' in scope` and dozens of other phantom errors that a model then
  "fixes" by inventing duplicate declarations.
- **`xcodebuild` cannot build here.** `-showdestinations` returns nothing and reports `tvOS 26.5
  is not installed`; `xcrun simctl list runtimes` is empty. The unblock is `xcodebuild
  -downloadPlatform tvOS`, multi-GB — only worth it to actually run the app.
- **There is no Swift package.** `swift build` / `swift test` fail with `Could not find
  Package.swift` and would target macOS anyway. The iOS half is one XcodeGen-generated
  `Noctyr.xcodeproj`; there is no `.xcworkspace`.
- **Run `xcodegen generate` after adding, renaming, moving or deleting any Swift file, and commit
  the regenerated `.xcodeproj`.** The pbxproj is classic-style with an explicit `PBXFileReference`
  per file — not a synchronized group — so a new file on disk is simply not in the target and its
  type does not exist at Xcode build time, even though the `swiftc` sweep (which globs the
  filesystem) passes. Regeneration is byte-for-byte reproducible against the committed pbxproj, so
  it is always safe. Never hand-edit the pbxproj.
- **The SDK is tvOS 26.x, the deployment target is 17.0.** Anything newer needs `if #available(
  tvOS 18, *)`. That class of mistake is caught at compile time, which is why the
  unavailable-on-tvOS class matters more.
- **The sweep never sees `Assets.xcassets`, and there is a live mismatch.**
  `Theme/Color+Noctyr.swift` defines five `noctyr*` constants; the catalog holds three colorsets
  (`AccentColor`, `noctyrBackground`, `noctyrSurface`), so the file's own comment is already wrong.
  Keep using the static `Color.noctyr*` constants — never introduce string-based `Color("…")` /
  `Image("…")` lookups, which typecheck clean and fall back at runtime with only a console warning.

## tvOS is a focus engine, not a touchscreen

The user moves focus with a D-pad and presses select. **Anything the user must reach has to be a
`Button` or `NavigationLink`.**

- **Unavailable outright** (hard compile errors, so at least you find out): `Slider`, `Stepper`,
  `DisclosureGroup`, `GroupBox`, `TextEditor`, `ShareLink`, `.popover`, `.swipeActions`,
  `.listRowSeparator`, `.listStyle(.insetGrouped)`, `.navigationBarTitleDisplayMode`,
  `DragGesture`, `MagnificationGesture`. Available and fine: `Form`, `Picker`, `Toggle`,
  `ProgressView`, `TabView`, `NavigationStack`, `AsyncImage`, `.sheet`, `.fullScreenCover`,
  `.alert`, `.confirmationDialog`, `.contextMenu`. `Menu` is exactly tvOS 17.0 — available only
  because the floor is 17.0. For "add a slider for minimum rating", use a row of focusable chips
  over discrete thresholds.
- **The second, invisible failure tier: compiles, but no gesture exists behind it.**
  `.refreshable` type-checks and can never fire — tvOS has no pull-to-refresh; give the user a
  Refresh button. `.searchable(text:prompt:)` is fine and so is `placement: .automatic`, but the
  `.toolbar`, `.toolbarPrincipal`, `.sidebar` and `.navigationBarDrawer` placements are
  tvOS-unavailable. `.toolbar` itself works, but `ToolbarItemPlacement.bottomBar` and `.status`
  are tvOS 18 — and the repo builds its top bar as a plain `HStack` (`HomeView.topBar`), so
  "modernizing" it into a toolbar invents an untested pattern. `.onTapGesture` compiles on a
  `Text` and never runs, because a `Text` is not focusable — a silent dead control, no warning.
- **`.focusable()` (tvOS 15+) is the escape hatch** for that last trap, and the wrong answer
  whenever the thing is really a control: a `Button` gets system activation, style hooks and
  accessibility traits for free. Use `.focusable()` only to make something *reachable*, e.g. a
  scrollable block of copy.
- **Every `ScrollView` needs focusable content.** Scroll position follows focus, so a scroll view
  of plain views cannot be scrolled at all and everything past the fold is unreachable. Live
  instances: `HomeView.chips` (50-64) and `DetailView.castRow`, both horizontal `ScrollView`s of
  non-focusable `Text` / `CastCard`.
- **`.disabled()` removes focusability.** A screen whose only controls are disabled gives the
  remote nothing to land on, and only Menu escapes. `DetailView.watchButton` is
  `.disabled(content.services.isEmpty)`. Prefer keeping the control enabled, dimming it with
  `.opacity`, and explaining on activation.
- **Never store `@Environment` or `@FocusState` on a `ButtonStyle`** — it is not a `View`, so the
  wrapper is never installed, `isFocused` stays `false` forever, and this compiles with zero errors
  and zero warnings. `PosterButtonStyle`, `ChipButtonStyle` and `PrimaryButtonStyle` in
  `Views/Components.swift` already use the nested-`Styled`-view pattern — copy one of the three:

```swift
struct PosterButtonStyle: ButtonStyle {
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

- **A custom `ButtonStyle` replaces the system focus treatment** — reimplement lift, scale, border
  and shadow keyed on `isFocused`, or focus goes invisible. `.buttonStyle(.card)` is *not* a
  drop-in alternative: it is a `PrimitiveButtonStyle` (tvOS 14+), so it cannot compose with the
  three styles above and it supplies its own activation behaviour.
- **Wrap off-to-one-side controls in `.focusSection()`** (tvOS/macOS only). Focus moves
  geometrically: from a left-column poster, Up finds nothing above, so a Filters button at the far
  right of the top bar is unreachable. `HomeView.topBar` (33-48) is exactly this, with no
  `.focusSection()`.
- **Leave headroom for the focus scale and add `.scrollClipDisabled()`** (tvOS 17.0+, no
  `#available` needed) — a scaled poster in the first or last row is otherwise sliced off. SwiftUI
  already applies the tvOS overscan safe area, so screen-edge padding is additive and there is no
  single repo value (`HomeView` 60, `FilterPanelView` 70, `DetailView` 80); match the file you are
  in. The rule that matters: `.ignoresSafeArea()` belongs on backdrops, never on anything
  interactive.
- **Give a screen an explicit focus target when its focusable children are rebuilt from async
  state.** Applying a filter tears down every `NavigationLink` in the grid; if the focused one is
  gone, tvOS has no focused view and the app looks frozen. Use `@FocusState` (tvOS 15+) plus
  `.defaultFocus($focus, .first)` (tvOS 16+) — the second argument is *your own* focus value, not
  a sentinel — and re-seed `focus` after the reload. The binding only works on something already
  focusable.
- **Do not add `.onExitCommand` unless the handler itself calls `dismiss()`.** Menu is the only
  Back on tvOS; overriding it without dismissing traps the user, which is an App Store rejection.
  Usually the right answer is to omit it entirely.
- **Never add a typed username/password form.** `TextField`, `SecureField` and `.keyboardType` all
  compile, and entering a password on a D-pad grid takes a minute. There is also no in-app browser
  on tvOS — `SafariServices` does not exist in the SDK (`ASWebAuthenticationSession` *does*
  compile, so claim "no in-app web page", not "no web auth"). That is why the repo pairs via
  `QRCodeView` + `plexAuthURL` / `traktAuthURL` + polling. Reuse `Views/OnboardingView.swift`
  (`GET /auth/plex/start` → poll `/callback`).
- **App icons are an `AppIcon.brandassets` collection** of layered `.imagestack`s (front/middle/
  back, for the focus parallax) plus Top Shelf imagesets, never an `.appiconset`. Getting it wrong
  is not a build error — `actool` emits a notice, the build stays green, and the app ships with no
  icon. `ASSETCATALOG_COMPILER_APPICON_NAME` is *deliberately unset* in `project.yml` today
  ("leaving APPICON_NAME unset keeps the simulator build green until then"); set it only in the
  icon issue (#19/#26), together with the artwork.

## Concurrency

- **Guard reload/pagination races with a generation token, not a mutex.** `@MainActor` serialises
  access, not method bodies; actors are reentrant and isolation is released at every suspension.
  `HomeView` drives both a `.task(id: filterStore.revision)` reload and per-cell pagination against
  the same `CatalogViewModel`. `loadMoreIfNeeded` already checks `!isLoadingMore`, but `reload`
  ignores it entirely — so an in-flight page-2 fetch can resume *after* `items = []` and
  `page = 1`, append stale rows and bump `page`, and the reload's own response then lands on page 3.
  A single `guard !inFlight` over both entry points is the wrong fix: it silently drops the filter
  change the user just made. Stamp each reload and discard stale responses:

```swift
private var loadID = 0
func reload(filters: CatalogFilters) async {
    loadID += 1
    let id = loadID                 // capture before the first await
    page = 1; items = []; phase = .loading
    await fetch(filters: filters, id: id, replacing: true)
}
private func fetch(filters: CatalogFilters, id: Int, replacing: Bool) async {
    do {
        let batch = try await api.catalog(filters: filters, page: page)
        guard id == loadID else { return }   // a newer reload superseded us
        ...
    } catch is CancellationError {
        return                               // must precede the APIError catch
    } catch let error as APIError {
        if case .transport(let underlying) = error,
           (underlying as? URLError)?.code == .cancelled { return }
        if replacing { phase = .error(error.errorDescription ?? "Something went wrong.") }
    } catch { if replacing { phase = .error("Something went wrong.") } }
}
```

- **Cancelling a `URLSession` request throws `URLError.cancelled` (-999), not `CancellationError`.**
  `.task(id:)` cancels the in-flight load on every filter apply, so a generic catch paints
  "Something went wrong" for a completely normal user action. `APIError` wraps it in `.transport`,
  so you must bind the typed error first: `if case .transport(...)` in a bare `catch` fails with
  `type '_ErrorCodeProtocol' has no member 'transport'`, because `error` is `any Error` there.
  Thread this through the existing `catch let error as APIError` / `catch` pair in
  `CatalogViewModel.fetch`, keeping the ordering above.
- **Never `try? await` anything whose failure changes what the user sees.** `try?` turns
  `CancellationError` into `nil` and the loop keeps going. `ContentView.swift:23` ships the worst
  case already — `_ = try? await APIClient.shared.ensureSession()`, so every later request silently
  goes unauthenticated. Let `try await Task.sleep` throw. Note `OnboardingViewModel.pollPlex` /
  `pollTrakt` do `try? await Task.sleep(...)` followed immediately by `if Task.isCancelled
  { return }` — that guard is what makes them exit; do not delete it while "fixing" the `try?`.
- **Use `.task` / `.task(id:)`, never `onAppear { Task { ... } }`.** The unstructured task is not
  cancelled on disappear, keeps writing `@Published` state into a dead screen, and `onAppear` fires
  again on every back-navigation, stacking requests. `Task.detached` from a `@MainActor` type is
  *not* itself an error — it simply does not inherit the actor, so touching `@Published` state
  inside one is the failure, and only language mode 6 reports it. Plain `Task { }` inherits.
- **The per-cell `.task` in `HomeView.grid` (90-94) is the pagination trigger** and fires once per
  visible cell — ~15 concurrent tasks on first render at 5 columns. It is the one place cell-level
  async work is expected; anything else you attach there multiplies by the same factor.
- **Leave `SWIFT_VERSION` at 5.9 (language mode 5) and annotate every new singleton `@MainActor`
  or make it `Sendable`.** The tree type-checks clean under `-swift-version 6` except one error
  (`APIClient.shared`). Mode 5 emits nothing for new violations, so an unannotated singleton is
  invisible debt; bumping the setting as a drive-by turns each one into a build failure.

## State ownership and view structure

- **`@StateObject` to own, `@ObservedObject` only for one handed in.** `@ObservedObject private
  var vm = VM()` compiles with no warning and silently rebuilds the view model — dropping `items`,
  `page` and `phase` — on every parent invalidation. In an init the label is
  `StateObject(wrappedValue:)`, not `initialValue:` (that is `@State`'s label and a hard error).
- **Do not introduce `@Observable`.** This tree has zero `@Observable`, zero `@ObservedObject` and
  three Combine `ObservableObject` view models. Both systems compile on tvOS 17, which is why
  models mix them, and the mix does not: `@StateObject` over an `@Observable` type errors with
  `requires that 'VM' conform to 'ObservableObject'`. `@Observable` needs `@State`, `@Bindable` and
  `@Environment(VM.self)` — a different wrapper at every call site. A whole-codebase migration is
  legal; a drive-by is not.
- **Mark any branching computed property `@ViewBuilder`, and use `ForEach`, not `for`.** Without
  the builder each branch must return the identical concrete type, and you get `function declares
  an opaque return type 'some View', but the return statements in its body do not have matching
  underlying types [#OpaqueTypeInference]`. `HomeView.results` already does this — match it. Return
  `some View`, never `any View` (`type 'any View' cannot conform to 'View'
  [#ProtocolTypeNonConformance]`), and never type a property as a bare protocol; take a generic
  parameter or apply `.buttonStyle(...)` at the call site.
- **Do not bind to `@Published private(set)`** (`setter is inaccessible`). Copy into local `@State`
  — `_draft = State(initialValue: filters)` — and commit through a closure, as `FilterPanelView`
  does. `private(set)` is the convention *for view models the view must not mutate* (`FilterStore`,
  `CatalogViewModel`); `OnboardingViewModel`'s five are deliberately plain `@Published var` and
  `OnboardingView` writes them — do not "fix" those. Removing `private(set)` where it exists
  destroys the single write path: `FilterStore.apply` is what bumps `revision` (driving
  `HomeView`'s `.task(id:)`) and persists to `UserDefaults`.
- **`@State` seeded from an init parameter is a one-shot snapshot per view identity.**
  `DetailView.init` does `_content = State(initialValue: summary)`; if the parent can swap the
  value in place, add `.id(...)`.

## The FastAPI contract, plist and Keychain

- **With `.convertFromSnakeCase`, `CodingKeys` cases are plain camelCase with no raw value.**
  `case tmdbId = "tmdb_id"` compiles and then fails at runtime with `keyNotFound` — the strategy
  has already rewritten the incoming key to `tmdbId`. Nothing offline catches it, and it is the
  single most likely way a model breaks the wire contract while believing it made the mapping more
  explicit.
- **Adding a field to `Content` means three edits:** `CodingKeys`, the hand-written `init(from:)`
  (`decodeIfPresent(...) ?? []`, deliberately, so lean payloads still decode), and the memberwise
  init. Only *Decodable* synthesis is suppressed — `encode(to:)` is still synthesized from
  `CodingKeys`, so do not go looking for one. Giving the property a default to silence "returns
  from initializer without initializing all stored properties" turns a compile error into silent
  data loss. Keep it in lockstep with `backend/src/models/content.py`.
- **Build URLs with `appendingPathComponent` plus `URLComponents`, as `APIClient.makeRequest`
  does.** `URL(string: "/catalog", relativeTo: base)` drops the base path. No networking outside
  `APIClient`; view models take `init(api: APIClient = .shared)`, which is the test seam.
- **There is no `dateDecodingStrategy` today** — `APIClient.swift:67-69` sets only
  `.convertFromSnakeCase`, so the default is `.deferredToDate`, and no model on either side
  currently carries a timestamp. If you add a `Date`, set a strategy in the same change or the
  first ISO string pydantic emits will try to decode as a `Double` and fail.
- **`NOCTYR_API_BASE_URL` fails silently, not loudly.** `APIClient.swift:63-64` reads
  `Bundle.main.object(forInfoDictionaryKey:) as? String` and force-unwraps `URL(string: configured
  ?? "https://api.noctyr.magmamoose.com")!`. A typo in the **key** falls back to the hardcoded
  production URL with no crash — a staging build quietly talks to prod. Only an unparseable
  **value** crashes at launch.
- **Session token lives in the Keychain only** (`KeychainStore`,
  `kSecAttrAccessibleAfterFirstUnlock`), never `UserDefaults`. Filters persist under
  `noctyr.filters.v1`; tvOS caps app-local defaults at 500 KB and does not guarantee local storage
  survives — nothing large or unrecoverable there.
- **`Info.plist` is hand-maintained** (`GENERATE_INFOPLIST_FILE NO`). Any new deep-link scheme must
  be added to `LSApplicationQueriesSchemes` or `canOpenURL` returns false and `DeepLinkService`
  reports `.failed` with no other diagnostic. Deep links only open on real Apple TV hardware —
  never claim the Watch button is verified from a simulator.

## Tests and previews

There is no test target and no workflow (issues #37/#38). Adding one is a `project.yml` edit plus
`xcodegen generate`, and it needs a declared `scheme:` with `testTargets:`, because the repo has
zero committed `.xcscheme` files and an autocreated scheme runs zero tests while reporting success.
**Test bodies cannot be typechecked by the sweep above in either framework**: `import XCTest` fails
with `no such module 'XCTest'` (it ships in
`Platforms/AppleTVSimulator.platform/Developer/Library/Frameworks`, not the SDK), and
`import Testing` fails the same way — adding `-F` for it then dies on `external macro
implementation type 'TestingMacros.TestDeclarationMacro' could not be found`. Pick a framework on
other grounds and say plainly that the bodies are unverified. Scope tests to pure logic
(`CatalogFilters.queryItems`, `Content` decoding, `Service` mapping); running them needs a booted
tvOS simulator this machine does not have. In CI, build with `-destination 'generic/platform=tvOS
Simulator'` and test with `OS=latest` — never pin `OS=17.0`, which exists on no runner image.

`#Preview { … }` *does* typecheck under the sweep, and the repo has zero previews. With no
simulator and no tests it is the only structured way to exercise a view offline — add one
alongside any new view unless the issue says otherwise.

## Expected behavior

1. **Read the issue, then read the neighbours** — the file you are editing and the two nearest
   files in `Views/`, `ViewModels/` or `Models/`. Idiom-matching beats idiom-importing here.
2. **Export `DEVELOPER_DIR` in every shell call** — and typecheck the tree once before you edit,
   so you know whether you inherited a broken branch.
3. **Check availability before writing any control or modifier** — and when it does compile, ask
   separately whether a D-pad can trigger it. Never assert availability from memory, and never
   leave a comment claiming availability the compiler has not confirmed in this run.
4. **Trace the D-pad path end to end** — what is focusable, what has focus on first render, what
   has focus after an async reload, and how Menu gets the user out.
5. **Match the established idioms** — Combine `ObservableObject` + `@StateObject`, the `Phase` enum
   switched in a `@ViewBuilder`, `Color.noctyr*` from `Theme/Color+Noctyr.swift`, `APIClient` for
   every request. Never invent colours, spacing scales or typography outside `Theme/`, and never
   add a Swift package, a third-party dependency, or a networking path outside `APIClient`.
6. **Run `xcodegen generate` and stage the regenerated project** whenever the file set changed.
   Never hand-edit `Noctyr.xcodeproj/project.pbxproj`.
7. **Typecheck the whole tree and paste the real result** — zero errors, or the exact error text.
   With no CI, this is the only evidence on the PR.
8. **State plainly what you could not verify** — no simulator run, no test execution, no deep-link
   check, no asset-catalog or Info.plist validation. Do not let a green typecheck imply more.
9. **Never bump `SWIFT_VERSION`, raise the deployment target, or migrate to `@Observable`** as a
   side effect of another change. Keep credentials, tokens and the session id in the Keychain only.
10. **Commit in the house format** — Conventional Commits with an `ios` scope and the issue number
    in the subject (`feat(ios): add rating filter chips (#22)`), branch `<type>/<description>`, and
    no AI co-author trailer. Never commit or push unless asked. The run ends with a dirty tree, a
    typecheck result, and a summary of what remains unverified.
