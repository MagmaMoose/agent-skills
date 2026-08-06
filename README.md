# agent-skills

Shared agent workflows for the MagmaMoose stack, packaged for Claude Code and Codex.

This repository keeps one source of truth for PR review, PR triage, and documentation sync. Claude Code uses the `.claude-plugin` marketplace plus `commands/`, Codex uses the `.codex-plugin` manifest plus `skills/`, and the actual workflow logic lives in `shared/`.

Do not fork these workflows per project. Put project-specific rules in the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or relevant `README.md` files. The adapters instruct agents to read those files before acting and to treat explicit hard rules as blockers.

## Workflows

| Workflow | Claude Code command | Codex skill |
| --- | --- | --- |
| PR review | `/claude-skills:pr-review` | `pr-review` |
| PR triage | `/claude-skills:pr-triage` | `pr-triage` |
| Docs sync | `/claude-skills:update-docs` | `update-docs` |

`update-docs` brings a repository's `./docs` (MkDocs) into agreement with the code. It does both
halves of the job: fixing what the recent changes made wrong, and sweeping the whole codebase
against a 30-surface checklist so gaps that were never documented stop being invisible. Every
run ends with a coverage matrix that gives each surface a status, so "we didn't look there" can't
hide.

The Claude command namespace remains `claude-skills` for backward compatibility with existing users and headless installs.

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
/claude-skills:update-docs
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
Use the update-docs skill to sync ./docs with the code.
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

Both scripts are stdlib-only Python 3, and both are resolved by their workflow under
`${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`, with a documented fallback
when they aren't present.

`scripts/build-review-payload.py` assembles and validates the single GitHub review payload
for `pr-review`, so review bodies and inline comments are written as plain Markdown instead of
hand-escaped JSON. `pr-review` falls back to a hand-written payload when it's missing.

`scripts/docs-audit.py` does the mechanical half of `update-docs`: nav and page parity, broken
relative links, dead heading anchors, source-anchor staleness (pages whose code moved on without
them), stub pages, missing code-fence languages, banned filler phrases and em-dashes, and
credential-shaped strings that must never reach a published page.

```bash
python3 scripts/docs-audit.py audit --root . --strict
```

## License

MIT © Caleb Sargeant
