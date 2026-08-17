# agent-skills

Shared agent workflows for the MagmaMoose stack, packaged for Claude Code and Codex.

This repository keeps one source of truth for PR review, PR triage, documentation sync, Kubernetes platform audit, tvOS SwiftUI, and context optimisation work. Claude Code uses the `.claude-plugin` marketplace plus `commands/`, Codex uses the `.codex-plugin` manifest plus `skills/`, and the actual workflow logic lives in `shared/`.

Do not fork these workflows per project. Put project-specific rules in the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or relevant `README.md` files. The adapters instruct agents to read those files before acting and to treat explicit hard rules as blockers.

## Workflows

Every workflow is named `{noun}-{verb}`: the thing it acts on, then what it does to it. New workflows follow the same rule.

| Workflow | Claude Code command | Codex skill |
| --- | --- | --- |
| PR review | `/claude-skills:pr-review` | `pr-review` |
| PR triage | `/claude-skills:pr-triage` | `pr-triage` |
| Docs sync | `/claude-skills:docs-update` | `docs-update` |
| Kubernetes audit | `/claude-skills:k8s-audit` | `k8s-audit` |
| tvOS SwiftUI | `/claude-skills:swiftui-build` | `swiftui-build` |
| Context stack | `/claude-skills:context-optimise` | `context-optimise` |

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
/claude-skills:docs-update
/claude-skills:k8s-audit
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
Use the docs-update skill to sync ./docs with the code.
Use the k8s-audit skill to audit the production cluster.
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

## License

MIT © Caleb Sargeant
