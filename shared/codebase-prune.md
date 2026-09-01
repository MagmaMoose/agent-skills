# Codebase prune workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and
relevant `README.md` files. Treat explicit hard rules from the target repository as blockers: a
stated file layout, a frozen public API, a "no refactors in feature PRs" rule, a deprecation
policy, a vendored directory that is deliberately not edited, or a commit-trailer ban in the target
repository all win over this file.

You are reducing the amount of code a maintainer has to hold in their head, in a repository that
has accumulated years of it, **without changing what the software does**.

Five classes of work, listed in the order their risk increases, which is also the order you do
them in:

1. **Dead code** — declarations, files, dependencies and configuration nothing reaches.
2. **Dead process** — CI jobs, flags, skipped tests, env vars, manifests for services that are gone.
3. **Duplication** — the same logic implemented two, three, five times.
4. **Over-abstraction** — indirection that costs more to read than the thing it hides.
5. **Structure** — where files live, and whether the layout says what the system does.

## The one rule that matters most (READ BEFORE ANY OTHER SECTION)

**"Unused" is a hypothesis. It becomes a finding only when a second, independent signal agrees.**

Every dead-code tool answers one question: *is this symbol reachable from the entrypoints I was
told about, through the edges I can see?* Both halves of that are usually wrong in a legacy
repository. The entrypoint set is incomplete, because something is invoked by a cron entry, a
Kubernetes `command:`, a queue consumer, a webhook, or a CI step nobody added to the config. And
the edges are invisible, because real systems dispatch on strings: reflection, dependency
injection containers, decorators and annotations, dynamic imports, ORM hooks, template rendering,
serialized class names in a cache or a message, handler names stored in a database, plugin
registries, `__getattr__`, `getattr(module, name)`, `Class.forName`.

The consequence is not that the tools are useless. It is that **tool output is a candidate list,
never a finding list**, and a run that pastes a `knip` report into a document has done nothing a
`npx knip` could not have done in ten seconds.

The failure this produces is worse than doing nothing, and it is a credibility failure rather than
a technical one. Report thirty candidates, have four of them turn out to be live, and nobody will
read the other twenty-six. The dead code then stays in the codebase forever, protected by the
memory of your bad report. **A prune run is judged on its false-positive rate, not on its
coverage.**

So: for every candidate, either corroborate it up the evidence ladder in section 3, or classify it
`unknown` and say why. Never delete on one signal. Never present one signal as a finding.

## The second rule

**Less code is not the goal. Fewer things to hold in your head is.**

They diverge constantly, and the divergence runs in both directions:

- Deleting a test file scores brilliantly on lines removed and makes the codebase worse.
- Collapsing a four-file indirection chain into one direct call often **adds** lines and is one of
  the most valuable changes in this workflow.
- Replacing three near-duplicate functions with one function that takes four boolean parameters
  removes lines and produces something nobody can read, at three call sites that now pass magic
  flags.

So do not report lines deleted as the headline number, and never let it be the success criterion.
Report, per flow: **how many files you have to open, and how many hops you have to follow, to
understand one behaviour.** That number going down is the actual product of this workflow.

The corollary is Sandi Metz's, and it is load-bearing here: **the wrong abstraction costs more than
the duplication it replaced.** In a legacy repository you will find abstractions built on an axis
that turned out to be wrong, now bent by five special cases and three flag parameters. The correct
move on those is frequently to *inline it back into its call sites* and either re-abstract on the
right axis or leave the duplication alone. That is a valid outcome of this workflow, and it is not
a failure.

## Voice

Binding on the deliverable, on every commit message, and on any comment you leave in code.

- Terse. Findings are evidence plus a verdict. No preamble, no "in today's fast-moving codebases".
- Every claim is something you verified in this run, cited as `path:line` or as a command with its
  output. No "this is likely unused".
- Name real tools with real flags, read out of the repo's own config or run in this session, never
  remembered.
- No attribution footers, no robot emojis, no "AI-generated" branding, in any file you write, any
  commit message you propose, or any PR body.
- Never soften a real finding and never inflate a nit. A run that flags formatting alongside a
  never-registered auth handler has told the reader nothing about which one matters.

## Rules of engagement

- **Behaviour-preserving by construction.** If a change alters observable behaviour, it is not part
  of this workflow. It is a bug report or a proposal, filed separately. Bugs you find are reported,
  not fixed in the same breath. Fixing a bug inside a "no functional change" PR is how prune runs
  destroy trust.
- **Never delete scar tissue.** A weird guard clause, a retry with an odd sleep, a `+ 1` with no
  explanation, a comment saying "do not remove". Legacy code is the accumulated fix list of
  everyone who was on call before you, and most of those fixes have no test. Before removing
  anything that looks wrong rather than merely unused, run `git log -S` and `git blame` on it. If
  its commit message, PR or linked issue mentions an incident, a customer, or a production
  symptom, it stays, and it gets the comment it never had.
- **Never mix concerns in a commit.** One kind of change per commit and, where possible, per PR.
  Deletions, renames, moves, reformats and refactors are four separate commits. A formatter run
  mixed into a deletion makes the diff unreviewable and the revert impossible.
- **Every deletion must be revertible on its own.** `git revert <sha>` restores it, and the commit
  body says so.
- **Never add a dependency** to make a cleanup work, and never install a tool into the target
  repository. Report the install command instead.
- **Never run a mutating tool implicitly.** No `--fix`, `--write`, formatter, codemod or
  `go mod tidy` until the section that authorises it, and never on a dirty tree.
- **Never touch generated, vendored or third-party trees**, and never edit a lockfile by hand.
  Regenerate it with the repo's own command or leave it.
- **Idempotent.** A second run must find the same repository in a better state, not duplicate its
  own suppressions, re-add a whitelist, or re-report what it already fixed.
- **Never commit, push, or open a PR** unless explicitly asked. The default end state is a
  deliverable plus, if authorised, a dirty tree or a stack of local commits.
- **Never truncate silently.** If you capped a list at fifty, say what was cut and why, and make
  every count in the report reconcile with every other count.

## 0. Orient

Everything below is derived from the repository in front of you. A generic cleanup helps nobody and
a generic cleanup of a legacy repository is actively dangerous.

```sh
git log --oneline -20
git log --format=%as | tail -1          # how old is this
git status --porcelain                  # must be clean before you touch anything
```

Establish, from files rather than assumption:

- **What this software is and who runs it.** A library published to a registry, a service in a
  cluster, a CLI, a batch job, a mobile app. This decides whether "unused here" means anything at
  all.
- **The languages, package managers and workspace shape**, from `02-inventory.txt`.
- **The build, test, lint and typecheck commands**, read out of the manifest's script block, the
  `Makefile`/`justfile` targets, and `.github/workflows/`. **CI is the honest source**: it is what
  has to pass. Anything not in CI is not a gate, whatever the README claims.
- **The entrypoint set**, from `03-entrypoints.txt`, and every root a reachability tool will miss:
  cron and scheduler entries, queue consumers, webhook targets, HTTP route tables, Kubernetes
  `command:`/`args:`, Dockerfile `CMD`, systemd units, Lambda handlers, plugin manifests, and
  scripts invoked only from CI.
- **The safety net**, honestly. Is there a test suite? Does it run in CI? Does it pass right now on
  a clean checkout? What is covered and what is not? A repository whose tests have been red for a
  year has no safety net, whatever its coverage badge says.
- **The dynamic-dispatch surface**, because it determines how much of the tooling you can trust:

```sh
git grep -nE "getattr\(|globals\(\)|locals\(\)|importlib|__import__|eval\(|exec\(" 
git grep -nE "Class\.forName|reflect\.|newInstance|@Autowired|@Inject|@Component|@Bean"
git grep -nE "require\(\`|import\(|require\(.*\+|\[['\"]\w+['\"]\]\(\)"
git grep -nE "@app\.|@router\.|@celery|@task|@handler|@EventListener|addEventListener"
```

Say in the report how large that surface is. In a Spring, Django, Rails, NestJS or Symfony codebase
it is enormous, and it caps how much any static tool can prove.

- **What already exists of this effort**: an open cleanup issue, a `DEPRECATED.md`, a previous
  prune PR that stalled, a `knip.json` or `.vulture_whitelist.py` someone started. You are
  continuing work, not landing on empty ground.

## 1. Harvest

One read-only dump, to files, so every dimension and every subagent reads the same commit:

```sh
scripts/cruft-harvest.sh . ./harvest/cruft
```

Resolve it from `${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`. If it isn't
there, run the equivalent commands by hand and say so in the report.

Read `90-tooling.txt` **first**. It says which dimensions were covered by a real analyser and which
were covered by grep alone. That distinction goes in the deliverable, because a grep-only dimension
has a false-negative rate you cannot estimate, and claiming "no dead Python found" when `vulture`
was never installed is a lie by omission.

Where a tool is missing, report its install command; never install it into the target repository.

| Language / concern | Tool | Invocation |
| --- | --- | --- |
| JS/TS files, exports, deps | `knip` | `npx knip --no-exit-code`, then `--production` for the honest set |
| JS/TS deps only | `depcheck` | `npx depcheck` |
| JS/TS cycles | `madge` | `npx madge --circular --extensions ts,tsx .` |
| Python symbols | `vulture` | `vulture --min-confidence 60 .` (see confidence note below) |
| Python imports/args | `ruff` | `ruff check --select F401,F811,F841,ARG,ERA` |
| Python deps | `deptry` | `deptry .` |
| Go functions | `deadcode` | `go install golang.org/x/tools/cmd/deadcode@latest && deadcode ./...` |
| Go unexported | `staticcheck` | `staticcheck -checks=U1000 ./...` |
| Go deps | `go` | `go mod tidy -diff` (Go >= 1.23; read-only) |
| Rust deps | `cargo-machete` | `cargo machete` |
| Rust deps, precise | `cargo-udeps` | `cargo +nightly udeps` (needs nightly) |
| Swift | `periphery` | `periphery scan` |
| Java/Kotlin deps | Gradle dep-analysis | `./gradlew buildHealth` |
| C# | Roslyn IDE0051/IDE0052 | `dotnet build /p:EnforceCodeStyleInBuild=true` |
| Duplication, any language | `jscpd` | `npx jscpd --min-lines 12 --min-tokens 70 .` |
| Complexity, any language | `lizard` | `lizard -C 15 -w .` |
| Size and shape | `scc` | `scc --by-file --sort complexity` |

Two calibration notes that decide whether you trust the output:

- **`vulture` confidence is not a probability of deadness.** 100% means the fact is syntactic
  (an unused argument, code after a `return`). 90% is an unused import. 60% covers attributes,
  classes, functions, methods and variables, and it is the band where every framework false
  positive lives. Read the 100% band as near-fact and the 60% band as a question.
- **`knip --production` is the number that matters** for a service. The default run includes test
  files and config as consumers, so an export used only by a deleted test still counts as used.
  Run both and report the gap, because that gap is "code kept alive only by its own tests", which
  is a specific and very common legacy pattern: the tests are the only caller, so deleting the code
  and its tests together is correct, and deleting the code alone breaks the build.

## 2. Establish the safety net before you delete anything

The order here is not negotiable. In a legacy repository the safety net is usually the thing that
is missing, and building it is most of the work.

### 2a. Capture a baseline, to files, on a clean tree

```sh
git status --porcelain                                   # must be empty
<build cmd>   > ../baseline/build.txt   2>&1; echo "rc=$?"   >> ../baseline/build.txt
<test cmd>    > ../baseline/test.txt    2>&1; echo "rc=$?"   >> ../baseline/test.txt
<lint cmd>    > ../baseline/lint.txt    2>&1; echo "rc=$?"   >> ../baseline/lint.txt
<typecheck>   > ../baseline/types.txt   2>&1; echo "rc=$?"   >> ../baseline/types.txt
cp harvest/cruft/10-public-surface.txt ../baseline/surface.txt
```

Write it **outside** the working tree so it survives every branch you touch.

Record the **counts**, not just the exit codes: tests passed, tests skipped, lint warnings by rule,
type errors. "Tests still pass" is not a verification when the suite silently ran 40 fewer tests
than before, and that is exactly what happens when you delete a file that a test-discovery glob was
picking up.

If the baseline is already red, stop and say so at the top of the deliverable. You cannot prove a
change is behaviour-preserving against a broken baseline, and the correct first PR is the one that
makes it green or quarantines the failure.

`surface.txt` is the one people forget. At the end of the run, diff the public surface against it.
An unintended deletion from the public API shows up there and nowhere else.

### 2b. Prove the test is a safety net before you trust it

A test that passes after you delete the code it covers is not protecting anything, and legacy
suites are full of them: tests that construct an object and assert nothing, tests whose only
assertion is `assertTrue(True)` after the interesting call, tests mocked so completely that the
subject never runs.

Before you rely on a test to authorise a change, break the thing it covers on purpose:

```sh
# comment out the body / return early / change a constant
<test cmd> -k <the test>        # MUST go red
git checkout -- <file>          # restore
<test cmd> -k <the test>        # MUST go green
```

If it never went red, the test is decoration. Say so in the report, treat the region as untested,
and go to 2c.

`harvest/cruft/08-tests.txt` gives you the free half of this: test files containing no assertion
token at all, and tests that have been skipped for years. A test skipped since 2019 is dead code
with a misleading name, and it belongs in the deletion list along with whatever it "covers".

### 2c. Where there is no test, write a characterization test first

A characterization test pins **what the code does now**, not what it should do. Bugs included. Its
only job is to fail if you change behaviour while pruning.

1. Call the code from a test with realistic inputs.
2. Assert something you know is wrong, so the failure prints the actual value.
3. Paste the actual value into the assertion.
4. Repeat until the branches you are about to touch are covered.

For an untestable tangle, pin the outside instead: golden-master the CLI's stdout, the HTTP
response body, the generated file, the SQL emitted, the log lines. A `diff` of before-and-after
output is a perfectly good safety net and is usually available in an hour.

Characterization tests are **commits of their own**, merged before any deletion, and they carry a
comment saying what they are. Otherwise the next reader assumes the pinned behaviour is intended
and defends a bug forever.

### 2d. The class that needs no test

Some changes are provable by construction, and demanding a test for them is what makes cleanup
work stall. A change qualifies only if the compiler or type-checker sees the entire world of the
symbol and the language has no dynamic path to it:

- Removing an unused import, an unused local variable, or code after an unconditional return.
- Deleting a private/unexported/file-local symbol in a statically typed language with no
  reflection over it, where build, typecheck and lint all pass.
- Deleting a whole file that `git grep` proves nothing references, in a language with static
  imports.

Everything else needs 2b or 2c. In Python, Ruby, PHP and JavaScript, *nothing* is in this class
above local-variable scope, because attribute access is string-keyed at runtime. Say that plainly
in the report for dynamic-language repositories rather than pretending the type checker covered it.

## 3. The evidence ladder

Run every candidate up this ladder. The tier it reaches decides its verdict, and the verdict goes
in the report next to it.

**Tier 0 — syntactic.** The compiler, type-checker or linter proves it within one compilation unit:
unused import, unused local, unreachable statement. No corroboration needed.

**Tier 1 — whole-program reachability.** A real analyser says nothing reaches it from the declared
entrypoints (`deadcode`, `knip`, `periphery`, `vulture`, `staticcheck -checks=U1000`). This is a
hypothesis whose weakest link is your entrypoint list from section 0.

**Tier 2 — the full-text corroboration, across every tracked file, not just source.** String
dispatch lives in configuration:

```sh
git grep -n "exactName"                       # everywhere, including yaml, json, sql, html, md
git grep -in "exact_name\|exact-name\|ExactName\|EXACT_NAME"   # config keys transform case
git grep -n "exactName" -- '*.yaml' '*.yml' '*.json' '*.tf' '*.sql' '*.html' '*.env*' 'Dockerfile*' '.github'
```

Check the name's **fragments** too. A handler registered as `"users.create"` never matches a grep
for `create_user`, and a Django setting pointing at `myapp.tasks.CleanupTask` is a string a
reachability tool cannot follow.

**Tier 3 — the external-consumer check.** Ask whether "unused in this repository" can mean anything:

- Is this repository **published**? A package on npm/PyPI/crates.io/Maven, a Go module others
  import, a container image with a documented entrypoint, a Helm chart. `10-publish-surface.txt`
  answers this. If yes, every exported symbol is potentially load-bearing and removing one is a
  breaking change requiring a deprecation cycle, not a prune.
- Is it a **stable interface**: an HTTP route, a GraphQL field, a queue message type, a database
  column, a CLI flag, a public config key, a webhook payload field?
- Does another repository in the organisation import it? Search the org if you have access
  (`gh search code`), and say explicitly in the report when you could not.
- Is it referenced by something **outside version control**: an operator runbook, a dashboard
  query, a Terraform state, a scheduled job in a SaaS console? You cannot grep those. Name the
  ones you could not check.

**Tier 4 — history and runtime.** The strongest evidence and the most often skipped:

```sh
git log -S "symbolName" --oneline -- .        # every commit that added or removed the string
git log -1 --format='%as %an %s' -- path/to/file
```

- **Recently added and unreferenced is not dead code.** It is almost always half-finished work or a
  wiring bug. Check the date before you propose deleting it.
- **Removed-then-restored** in history means someone already tried this and it broke something.
  Read that revert commit before you repeat it.
- Where the environment gives you coverage from a real deployment, feature-flag evaluation
  timestamps, APM traces, or route-level request counts, that beats every static signal in this
  list. Use it if it exists and say when it does not.

### Verdicts

Every candidate gets exactly one, and the counts must reconcile in the report:

- `delete` — cleared every applicable tier. Goes into a slice.
- `delete-with-tests` — the code's only callers are its own tests. Both go, together.
- `deprecate-then-delete` — reachable only from outside the repository, or on a published surface.
  Needs an announced deprecation and a release cycle. Propose the deprecation, not the deletion.
- `keep-and-annotate` — live via a dynamic edge you found. The valuable half: record the edge where
  the tool will read it, so the next run does not re-litigate it. A `knip.json` entry, a
  `vulture` whitelist line, a `# noqa` with a reason, a `//nolint:unused // called by X`. Every
  suppression carries **why**, with the `path:line` of the dynamic reference. A suppression without
  a reason is worse than the false positive.
- `wiring-bug` — it was *meant* to be reachable and is not. A route never registered, a flag branch
  that can never be true, an error handler after an early return, a migration never applied, a
  validator never called. **This is the highest-value output of the entire workflow.** These are
  bugs, often security-relevant (an authorisation check nothing calls is a vulnerability, not
  cruft). File them, do not delete them, and lead the deliverable with them.
- `unknown` — you could not corroborate it. Say what you could not check and what would settle it.

## 4. The cruft catalogue

Work these dimensions. For each: what to look for, and the specific way it goes wrong.

**1. Unreferenced symbols and files.** Section 3 governs. The trap is cascades: deleting a caller
makes its callee dead, and its callee's callee. That is legitimate, but each round must be
**re-derived by re-running the analyser**, never chained by hand, and the cascade stops at any
tier-3 boundary.

**2. Unused dependencies.** `knip`, `depcheck`, `deptry`, `cargo machete`, `go mod tidy -diff`.
Three traps: a dependency used only by a build step or a config file looks unused to a source
analyser; a transitive dependency that your code imports directly but does not declare is a latent
break, not cruft, and it is the more urgent finding; and removing a dependency changes the lockfile,
so it is its own commit with its own build verification.

**3. Dead configuration.** `09-env-vars.txt` gives both directions. Variables **declared but never
read** are dead config. Variables **read but never declared** are a config bug and rank higher.
Also: config keys with no reader, `.env.example` drift from what the code loads, and settings whose
value is identical in every environment (that is a constant wearing a config costume; inline it).

**4. Dead infrastructure and process.** CI workflows whose triggers can never fire, jobs behind
`if: false`, matrix entries for runtimes you dropped, Dockerfile stages nothing targets, compose
services nothing depends on, Kubernetes manifests for deleted workloads, Terraform variables and
outputs nothing consumes, cron entries pointing at scripts that no longer exist. This dimension is
frequently the largest and the safest, and almost nobody looks at it.

**5. Feature-flag debt.** Every flag is a branch. A flag on 100% for a year has one dead branch and
a permanently-true condition; a flag never enabled has a dead **feature**. Removal is mechanical
(delete the flag, inline the winning branch, delete the loser, delete the flag's tests) and
absolutely must be its own commit. Check the flag platform's last-evaluated timestamp where one
exists; never infer a flag's state from the default in the code.

**6. Dead tests.** Long-skipped tests, tests that assert nothing (2b), snapshots with no test,
fixtures nothing loads, `expect` blocks with no matcher, and helpers only other dead tests use.
Deleting a skipped test is a real improvement: it converts a lie about coverage into an honest gap.
Say in the report that the gap is now visible.

**7. Commented-out code and lying comments.** `08-commented-code.txt`. Commented-out code goes,
always: version control is the archive, and the commit message says where it went. A comment that
contradicts the code beneath it is worse than no comment, and each one is a decision: fix the
comment or fix the code, and if you cannot tell which is right, that is a `wiring-bug` candidate.
TODOs older than a couple of years with no issue link are not a plan, they are litter; either link
them to a tracked issue or delete them.

**8. Duplication.** `jscpd` finds the literal copies. The expensive ones it cannot find are the
*semantic* duplicates: two HTTP clients with different retry policies, three date formatters, two
config loaders, a second logging wrapper written because nobody found the first. Look for them by
concept, not by text:

```sh
git grep -lE "class .*Client|def .*_client|http\.(Client|request)|axios\.create|new RestTemplate"
git grep -lE "strftime|DateFormatter|toISOString|moment\(|dayjs\("
git grep -lE "log(ger)?\s*=|createLogger|getLogger|zap\.|logrus\."
```

Merging duplicates is **not** a tier-0 change: the copies have usually drifted, and the drift is
sometimes a fix that only landed in one of them. Diff them line by line and say in the commit which
behaviour won and why.

**9. Over-abstraction.** Section 5.

**10. Version and compatibility debt.** Polyfills for runtimes you dropped, branches on versions no
longer supported, compatibility shims for a migration that finished, vendored copies of packages
now available upstream, deprecated APIs still called. `git log -S` on the shim finds the migration
it was for; if the migration is done, the shim is dead.

**11. Committed artefacts.** `11-artefacts.txt`: build output, coverage reports, `.DS_Store`,
minified bundles, binaries, files tracked despite matching `.gitignore`. Deleting them shrinks
clones and removes a class of merge conflict, but check first that no build step reads the
committed copy, which happens more than it should.

## 5. Structure and abstraction

The half of the workflow with no tool. Everything here is judgement, so everything here needs
evidence and a stated trade-off.

### 5a. Measure indirection before you touch it

Pick the three or four flows that matter (a request, a build, the auth path, the main job). For
each, walk it and write down the hop chain:

```text
POST /orders
  -> routes/orders.ts:12          (router)
  -> OrderController.create:31    (thin passthrough, no logic)
  -> OrderService.create:88       (thin passthrough, no logic)
  -> OrderManager.handle:140      (validation + 1 call)
  -> OrderRepositoryImpl.save:52  (the only implementation of OrderRepository)
  = 5 files, 4 hops, 2 of them adding nothing
```

This chain is the before-and-after measurement for the whole workflow, and it is the number the
deliverable leads with. It is also the argument: nobody approves "remove an abstraction layer", and
everybody approves "five files to two, no behaviour change, here is the test".

### 5b. The abstraction smells, each with its test

- **Single-implementation interface.** An interface, protocol or abstract base with exactly one
  concrete implementation, and no test double that needs it. *Test:* does anything else implement
  it, including in tests? If not, inline it.
- **Passthrough wrapper.** A function or class whose body is one call with the same arguments.
  *Test:* delete it and call through. If nothing else changes, it was noise.
- **Constant parameter.** A parameter that is the same literal at every call site. *Test:*
  `git grep` the call sites. Remove the parameter, not the value.
- **Config that never varies.** A setting with one value in every environment, ever. *Test:* grep
  every env file, every CI file, every manifest. Inline the constant.
- **One-instantiation generic.** A generic or type parameter used with exactly one type.
- **The single-plugin plugin system.** A registry, strategy set, event bus or factory with one
  registered thing, one strategy, one subscriber, one product.
- **The grab bag.** `utils`, `helpers`, `common`, `misc`, `Manager`, `Handler`, `Base`. These are
  not abstractions, they are the absence of a name. Look at what is inside: unrelated functions
  that belong next to their callers, usually one caller each.
- **Inheritance used for reuse.** A hierarchy three deep where no call site is polymorphic. *Test:*
  does any caller hold the base type and get different behaviour? If not, that is composition
  written wrong.

### 5c. What you never collapse

The rule that keeps this section from doing damage. Leave it alone, and say in the report that you
deliberately did, when the abstraction is:

- **A seam a test depends on.** The one interface with a single production implementation and a
  fake in the tests is doing its job perfectly.
- **A boundary around a volatile dependency.** A vendor SDK, a payment provider, a cloud API, a
  third-party format. That abstraction exists to make the swap survivable, and it pays on the day
  it is needed and never before.
- **A published or cross-team API.** Tier 3 applies to shape as well as existence.
- **A security or trust boundary.** Auth, tenancy, input validation, sanitisation. Collapsing an
  indirection here means someone can now call the inner function directly and skip the check.
- **Genuinely polymorphic**, with three or more real implementations selected at runtime.
- **Concurrency or transaction scoping.** A wrapper that looks pointless is often the only thing
  establishing a lock, a span, a retry or a transaction boundary.

### 5d. Structure moves, last and alone

Structure is the highest-risk, lowest-urgency dimension, so it goes last, and it never shares a
commit with anything.

What to look for: package-by-layer (`controllers/`, `services/`, `models/`) where the directory
listing says nothing about what the system does; a module imported by exactly one distant module;
import cycles (`madge --circular`, `12-imports.txt`); god files; and files whose location
contradicts their name.

The bar for proposing a move is high. **Moving files destroys `git log` follow-ability and
everyone's muscle memory, and it conflicts with every open PR in the repository.** Propose a move
only when the current location actively misleads, count the open PRs it will conflict with, and
check the target repository's conventions first: a house layout in `CLAUDE.md` outranks
package-by-feature every time.

When a move is authorised:

```sh
git mv old/path new/path        # pure move, no content edits
git commit                      # commit the move ALONE
# then a second commit for imports and references
```

Pure-move commits keep `git log --follow` and `git blame` working. A move plus an edit in one
commit is how a decade of history gets thrown away.

## 6. Rank, then slice

A legacy repository yields hundreds of candidates. A report of hundreds of candidates gets read
once and actioned never, so ranking is the deliverable, not the list.

Rank by **risk-adjusted value**: what a maintainer stops tripping over, divided by the chance of
breaking something. In practice the order comes out:

1. `wiring-bug` findings. Not cleanup at all. Ship first, separately, as bug fixes with tests.
2. Tier-0 mechanical deletions across the repository. Enormous, boring, provable, no risk.
3. Dead infrastructure, CI and configuration. Large, safe, invisible to the runtime.
4. Dead tests and long-skipped tests. Makes the true coverage honest, which everything later needs.
5. Tier-1+2 corroborated symbol and file deletions, in dependency order, leaves first.
6. Unused dependencies. Own commit, own build check, lockfile regenerated by the repo's own command.
7. Duplication merges. Needs tests; each merge is its own commit stating which behaviour won.
8. Abstraction collapses. Needs tests and the before/after hop chain in the PR body.
9. Structure moves. Last, alone, only if authorised.
10. `deprecate-then-delete` items. A deprecation PR now, deletion in a later release.

Slice rules:

- **One kind of change per PR.** Mixed PRs get reviewed by nobody.
- **Reviewable size.** Aim under ~400 lines of *judgement* diff. Mechanical deletions can be far
  larger when the commit message states exactly how they were derived and how to reproduce it, so
  the reviewer verifies the method rather than the lines.
- **Each slice is independently revertible** and does not depend on the previous one merging.
- Order slices so the risky ones land while the team is watching, never as the last merge on a
  Friday, and never bundled behind a release.

## 7. Execute a slice

Only after the user authorises execution. Per slice, in this order, every time:

1. Branch from a clean tree, on a branch named `<type>/<description>` in Conventional-Commit style,
   respecting the target repository's naming rules.
2. Make **one kind** of change.
3. Re-run build, test, lint and typecheck. Compare **counts** against the baseline from 2a, not
   just exit codes. A drop in the number of tests executed is a failure, not a rounding error.
4. Diff the public surface against `baseline/surface.txt`. Any unintended change is a stop.
5. Re-run the harvest's relevant detector. It should report fewer candidates and no new ones.
6. Commit, with a body that carries the evidence:

```text
refactor: remove unreferenced OrderLegacyExporter

Unreferenced since 2021-03 (git log -S OrderLegacyExporter).
Evidence: deadcode ./... (tier 1); git grep across all tracked files
including yaml/json/tf/sql found no reference (tier 2); repo publishes
no package and the symbol is unexported (tier 3).
No behaviour change: build, test (412 passed, same as baseline), lint
and typecheck all match the pre-change baseline.
Restore with: git revert <this sha>
```

7. Report what happened, including anything you did not do and why.

Mechanical `--fix` runs (`ruff --fix`, `knip --fix`, `eslint --fix`, an IDE optimise-imports) are
allowed **only** for tier-0 issues, **only** on a clean tree, **only** as their own commit, and the
commit message names the exact tool and flags so the reviewer can reproduce it. Read the resulting
diff before committing it. `knip --fix` in particular will remove exports that a dynamic edge uses.

## 8. The deliverable

One document. Structure it in this order, because the order is the argument.

1. **What this repository is**, in a paragraph, and the honest state of its safety net: does the
   suite pass, what fraction of the code it covers, which tests turned out to assert nothing.
2. **Wiring bugs and security-relevant unreachable code.** Lead with these. They are the reason
   this run was worth doing, and they are not cleanup.
3. **The measurement.** Hop chains for the flows in 5a, tracked-file count, the tier-0 candidate
   count, and, if any slices were executed, before-and-after for each. Never lead with lines
   deleted.
4. **The ranked plan**, as slices, each with: what it removes, evidence tier, the verification that
   proves it safe, rough diff size, and its blast radius.
5. **The full candidate table**, one row per candidate: `path:line`, what it is, verdict, tiers
   cleared, and the corroboration that settled it. Sorted by verdict, then by value.
6. **What was deliberately left alone**, and why. The abstractions that pay their way, the scar
   tissue with an incident behind it, the vendored tree. This section is what makes the rest
   credible.
7. **Coverage of the run itself.** Which dimensions had a real analyser and which had grep only
   (from `90-tooling.txt`), which tier-3 checks you could not perform (other repositories,
   dashboards, runbooks, SaaS consoles), and what would settle each.
8. **Actions taken**, if any, with the verification output for each.

Every count in the document reconciles with every other. If a list was capped, say so and say what
was cut.

## Named failure patterns

Each of these has sunk a real cleanup. Check yourself against them before you report.

- **The confident scanner.** Tool output pasted as findings. `knip` says 240 unused exports, the
  document says "240 unused exports", four of them are the plugin API, and the whole document dies.
- **The big-bang PR.** One 12,000-line change nobody can review and nobody can revert. It sits open
  until it conflicts with everything, then gets merged unread or closed.
- **The LOC scoreboard.** Optimising for lines removed. Deleting the test suite wins by that
  metric.
- **The drive-by reformat.** A formatter or `--fix` folded into a real change, burying it and
  destroying `git blame` across the file.
- **The hand-chained cascade.** Deleting a caller, then its callee, then the next, by eye, without
  re-running reachability. Three levels down you are outside what any tool ever checked.
- **The public-API amputation.** Removing an export that another repository, a plugin, or a
  customer imports. Tier 3 exists entirely to prevent this.
- **The whitelist that only grows.** Suppressions added to quieten the tool rather than to record a
  real dynamic edge, with no reason attached. Two runs later nobody knows which suppressions are
  facts and which are surrender.
- **The four-boolean abstraction.** Three duplicated functions replaced by one function with four
  flag parameters. Fewer lines, more cognitive load, and now every call site is a puzzle.
- **Deleting the scar tissue.** The odd retry, the strange guard, the magic `+ 1`. It has no test
  because the incident that produced it happened at 3am. `git log -S` before you touch it.
- **The stale suppression.** A `knip.json` ignore or a vulture whitelist entry that outlived the
  code it protected, now hiding real dead code from every future run. Verify every existing
  suppression still points at something that exists.

## Boundaries

- **Never change behaviour.** Bugs found are reported, never fixed inside a prune commit.
- **Never delete without corroboration.** One signal is a candidate, never a finding.
- **Never commit, push, or open a PR** unless explicitly asked.
- **Never run a mutating command on a dirty tree**, and never one the user has not authorised.
- **Never install anything** into the target repository, including a dev dependency that would make
  a check possible. Report the command.
- **Never rewrite history**, force-push, or delete a branch or tag.
- **Never delete a test to make a change pass.** If a test breaks, the change was not
  behaviour-preserving, and the test is the finding.
- **Never remove a security control** because nothing appears to call it. Nothing calling an
  authorisation check is a vulnerability report, not a deletion.
- **Never claim a dimension is clean** when the tool for it was missing. Say it was covered by grep
  only.
- **Never inflate severity.** If everything is critical, nothing is, and the run gets ignored.
