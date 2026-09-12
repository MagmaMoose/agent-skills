# agent-skills

Shared agent workflows for the MagmaMoose stack, packaged for Claude Code and Codex.

This repository keeps one source of truth for PR review, PR triage, post-gate security and quality review, documentation sync, Kubernetes platform audit, codebase prune, architecture diagrams, tvOS SwiftUI, and context optimisation work. Claude Code uses the `.claude-plugin` marketplace plus `commands/`, Codex uses the `.codex-plugin` manifest plus `skills/`, and the actual workflow logic lives in `shared/`.

Do not fork these workflows per project. Put project-specific rules in the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or relevant `README.md` files. The adapters instruct agents to read those files before acting and to treat explicit hard rules as blockers.

## Workflows

Every workflow is named `{noun}-{verb}`: the thing it acts on, then what it does to it. New workflows follow the same rule.

| Workflow | Claude Code command | Codex skill |
| --- | --- | --- |
| PR review | `/claude-skills:pr-review` | `pr-review` |
| PR triage | `/claude-skills:pr-triage` | `pr-triage` |
| Chargate security review | `/claude-skills:chargate-security-review` | `chargate-security-review` |
| Brimyr quality review | `/claude-skills:brimyr-quality-review` | `brimyr-quality-review` |
| Docs sync | `/claude-skills:docs-update` | `docs-update` |
| Kubernetes audit | `/claude-skills:k8s-audit` | `k8s-audit` |
| Codebase prune | `/claude-skills:codebase-prune` | `codebase-prune` |
| tvOS SwiftUI | `/claude-skills:swiftui-build` | `swiftui-build` |
| macOS SwiftUI | `/claude-skills:macos-swiftui` | `macos-swiftui` |
| Context stack | `/claude-skills:context-optimise` | `context-optimise` |
| MikroTik RouterOS | `/claude-skills:mikrotik-routeros` | `mikrotik-routeros` |
| Architecture diagram | `/claude-skills:diagram-draw` | `diagram-draw` |

`chargate-security-review` runs once the Chargate gate has finished and reviews the same diff Chargate
just scanned — for the things a scanner structurally cannot find. Chargate matches patterns; this reads the
change. Anything Chargate already reported is suppressed as a duplicate, so what it posts is by construction
the additive half: the finding with no rule id behind it. It replies to Chargate's own PR summary comment, in
a comment carrying its own hidden marker so a re-run patches that comment instead of dribbling a second one,
and it carries its findings in a machine-readable block that `pr-triage` reads.

`brimyr-quality-review` does the same job after the Brimyr gate. Brimyr measures two things: whether the
lines a PR changed are covered, and — optionally, report-only unless a threshold is set — how many net-new
quality findings the change introduced. The review reads whether the tests covering those lines actually
assert anything, whether the change is one a maintainer would want to maintain, and which of the net-new
findings the gate counted but blocked on none of are worth acting on here. Brimyr posts its consolidated
comment only when the calling workflow asks it to, so the review degrades on purpose: it finds the gate
comment by marker where there is one and posts its own standalone comment where there is not, and says which
of the two happened rather than assuming.

`docs-update` brings a repository's `./docs` (MkDocs) into agreement with the code. It does both
halves of the job: fixing what the recent changes made wrong, and sweeping the whole codebase
against a 30-surface checklist so gaps that were never documented stop being invisible. Every
run ends with a coverage matrix that gives each surface a status, so "we didn't look there" can't
hide.

`k8s-audit` audits a Kubernetes platform against a world-class bar. It is built on one rule that
most audits get wrong: a repository audit and a live-cluster audit find different things, so it does
both. The repository describes intent, the cluster describes reality, and the gap between them is
where the severe findings live. A repo can be clean, reviewed and fully GitOps-managed while
production has had no alert delivery for a week. The run starts with a single read-only harvest per
cluster so every agent reads the same instant of state, then verifies the load-bearing facts by hand
before fanning out across thirteen dimensions, each found and then adversarially refuted. It ends
with a ranked deliverable that leads with what is genuinely world-class, classifies every finding
(including `falsely-claimed-fixed`, for the ones a document says are done and the cluster says are
not), and lists the merge-ordering hazards among the open remediation PRs.

`swiftui-build` covers changes to a tvOS SwiftUI target. Roughly a quarter of SwiftUI is
`@available(tvOS, unavailable)`, so the workflow is built around a `swiftc -typecheck` sweep
against the tvOS SDK that runs in seconds with no simulator: a change gets proven to compile
instead of asserted. It then covers the quieter tier, where an API compiles on tvOS and no D-pad
gesture can ever reach it.

`mikrotik-routeros` covers any code that touches a MikroTik router — a script that runs on the
device, a service that collects from one, a check that scores it, or an operation performed on it.
It exists because RouterOS punishes plausible guesses in a way that is hard to catch: the scripting
language returns `nil` rather than raising, so a wrong property name yields an empty string and
reads as "the device did not report that"; `/tool fetch` truncates at 64 KB, and at 4 KB for a
response read on RouterOS 6; concatenating an array-valued property with `.` distributes across the
elements instead of joining, silently corrupting whatever payload was being built; and
`check-certificate` defaults to `no`, so a fetch that omits it hands its bearer token to whoever
answers. The reference was researched against MikroTik's own documentation and changelogs and then
independently fact-checked, which found roughly one claim in four to be wrong — invented property
names, invented command flags, version gates with nothing behind them — all of them plausible
enough to ship. Those corrections are inline. The skill also carries the rules that keep a remote
router reachable: every mutating command gets a lockout rating, the commit-confirm pattern is
preferred over an instruction to be careful, and nothing the network sends is ever executed.

`macos-swiftui` covers changes to a macOS SwiftUI target, and exists because the tvOS workflow's
hard-won rules are the wrong ones here: there is no focus engine, and almost nothing is
unavailable. What bites on macOS instead is the frozen window. `Task.detached` does not detach when
its closure is written inside a `@MainActor` method under the Swift 5 language mode, so filesystem
work runs on the main thread with no error and no warning — measured at 1722 of 1722 samples parked
in `contentsOfDirectory`. Underneath that sits a permission model that denies by hanging: a read of
a TCC-protected folder blocks inside `open(2)` and never returns, so there is nothing to catch. The
workflow pairs the `swiftc -typecheck` sweep with `sample <pid>` as the cheap proof that the main
thread is free, and carries the permission keys, the signing rules that make grants evaporate on
every ad-hoc rebuild, and the native-app expectations an iOS habit skips.

`codebase-prune` reduces the amount of code a maintainer has to hold in their head, in a repository
that has accumulated years of it, without changing what the software does. It is built on the rule
every cleanup gets wrong: **"unused" is a hypothesis, not a finding.** A dead-code tool only answers
"is this reachable from the entrypoints I was told about, through the edges I can see", and in a
legacy repo both halves are wrong. The entrypoint list misses cron entries, queue consumers, webhook
targets, Dockerfile `CMD` and CI-only scripts; the edges are invisible wherever the system dispatches
on strings, which is every DI container, decorator, dynamic import, ORM hook and handler name stored
in a database. So tool output is a candidate list, and every candidate climbs an evidence ladder,
from the compiler through a full-text sweep of *every* tracked file to git history and external
consumers, before anything is deleted. The run is judged on its false-positive rate rather than its
coverage, because four wrong findings out of thirty means nobody reads the other twenty-six and the
real dead code then survives forever.

Its highest-value output is not a deletion at all. `wiring-bug` is the verdict for code that was
*meant* to be reachable and is not: a route never registered, a flag branch that can never be true,
an authorisation check nothing calls. Those are bugs, sometimes vulnerabilities, and they only turn
up because someone went looking for dead code. The workflow also refuses the usual scoreboard: lines
deleted is never the headline, because deleting a test file wins on that metric and collapsing a
four-file indirection chain into one direct call often adds lines while being worth far more. It
reports hop chains per flow instead, carries the list of abstractions it deliberately did **not**
collapse (test seams, vendor boundaries, security boundaries), and ships everything as ranked,
independently revertible slices with the restore recipe in each commit body.

`context-optimise` installs a five-layer context stack in a repository so later agent sessions
there start with more signal and fewer wasted tokens: a `PROJECT_INDEX.json` structural map loaded
on demand, a `CLAUDE.md` tier held under a measured token budget, noise and access control that
acts before output reaches the context window, somewhere for session memory to land, and a `./docs`
skeleton that `docs-update` fills later. It is built on the distinction most context cleanups miss:
the goal is signal per token, not fewer tokens. Deleting the footguns file measures as a win in the
current session and costs the same bug three more times next month, so an existing `CLAUDE.md` is
never trimmed away, only folded in, and the run reports line by line what moved where.

The Claude command namespace remains `claude-skills` for backward compatibility with existing users and headless installs.

### Renamed workflows

`update-docs` is now `docs-update` and `tvos-swiftui` is now `swiftui-build`, so every workflow reads `{noun}-{verb}`. The old names still resolve as deprecated aliases that forward to the new ones, so existing headless installs and scripts keep working. They will be removed in a future release; move to the new names.

## Compatibility

| Agent | Uses | Install source |
| --- | --- | --- |
| Claude Code | `.claude-plugin` + `commands/` | `claude plugin marketplace add magmamoose/agent-skills` |
| Codex | `.codex-plugin` + `skills/` | `codex plugin marketplace add magmamoose/agent-skills` |
| Shared logic | `shared/*.md` | same repo |

If you installed this repository before it was renamed from `claude-skills`, update your marketplace reference to `magmamoose/agent-skills`.

## Install

### Claude local install

```bash
claude plugin marketplace add magmamoose/agent-skills
claude plugin install claude-skills@magmamoose
```

Invoke the Claude commands with:

```text
/claude-skills:pr-review 123
/claude-skills:pr-triage 123
/claude-skills:chargate-security-review 123
/claude-skills:brimyr-quality-review 123
/claude-skills:docs-update
/claude-skills:k8s-audit
/claude-skills:codebase-prune
/claude-skills:swiftui-build 42
/claude-skills:context-optimise
```

### Claude headless / in-cluster install

The same two CLI calls work non-interactively at image-build time, after the `claude` CLI is installed:

```Dockerfile
RUN npm install -g @anthropic-ai/claude-code \
 && claude plugin marketplace add magmamoose/agent-skills \
 && claude plugin install claude-skills@magmamoose
```

Then the worker can run, for example:

```bash
claude -p "/claude-skills:pr-review 123"
```

### Codex marketplace install

```bash
codex plugin marketplace add magmamoose/agent-skills
codex plugin add agent-skills@magmamoose
```

Codex invocation examples:

```text
Use the pr-review skill on PR 123.
Use the pr-triage skill on PR 123.
Use the chargate-security-review skill on PR 123.
Use the brimyr-quality-review skill on PR 123.
Use the docs-update skill to sync ./docs with the code.
Use the k8s-audit skill to audit the production cluster.
Use the codebase-prune skill on this repo.
Use the swiftui-build skill on issue 42.
Use the context-optimise skill to set up the context stack in this repo.
```

## Repository layout

```text
.
├── .claude-plugin/
├── .codex-plugin/
├── commands/
├── skills/
├── shared/
├── scripts/
├── README.md
├── LICENSE
└── .gitignore
```

Every script is resolved by its workflow under `${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`,
or `scripts/`, with a documented fallback when it isn't present. The two Python scripts are
stdlib-only Python 3.

`scripts/build-review-payload.py` assembles and validates the single GitHub review payload
for `pr-review`, so review bodies and inline comments are written as plain Markdown instead of
hand-escaped JSON. `pr-review` falls back to a hand-written payload when it's missing.

`scripts/docs-audit.py` does the mechanical half of `docs-update`: nav and page parity, broken
relative links, dead heading anchors, source-anchor staleness (pages whose code moved on without
them), stub pages, missing code-fence languages, banned filler phrases and em-dashes, and
credential-shaped strings that must never reach a published page.

```bash
python3 scripts/docs-audit.py audit --root . --strict
```

`scripts/k8s-harvest.sh` does the evidence half of `k8s-audit`: one read-only dump of a cluster to
files, covering nodes and their capacity-versus-allocatable gap, pod state and container-level
failure reasons, rendered placement, requests/limits/QoS, networking, storage, backups, admission
webhooks and their failure policies, RBAC, GitOps reconciliation, running images, and an
object-count-per-kind table for spotting datastore bloat. Absent CRDs are recorded rather than
fatal, and secret values are never harvested.

```bash
scripts/k8s-harvest.sh <kube-context> ./harvest/prod
```

`scripts/cruft-harvest.sh` does the evidence half of `codebase-prune`: one read-only dump of a
repository to files, covering the inventory and entrypoint set, churn and the date each file was
last touched, unused dependencies and unreferenced symbols from whichever analysers are installed,
duplication and complexity, TODO and commented-out-code markers, skipped tests and tests that assert
nothing, env vars read but never declared (and declared but never read), feature-flag references,
a public-symbol snapshot to diff after the prune, and committed build artefacts. The file universe
is `git ls-files`, so `.gitignore`, vendored trees and build output are excluded for free. It never
writes inside the repo, never installs anything, and never runs a `--fix`; a missing tool is
recorded in `90-tooling.txt` rather than being fatal, because which dimensions had a real analyser
and which had only grep is itself a finding.

```bash
scripts/cruft-harvest.sh . ./harvest/cruft
```

## License

MIT © Caleb Sargeant
