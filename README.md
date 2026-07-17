# agent-skills

Shared agent workflows for the MagmaMoose stack, packaged for Claude Code and Codex.

This repository keeps one source of truth for PR review and PR triage. Claude Code uses the `.claude-plugin` marketplace plus `commands/`, Codex uses the `.codex-plugin` manifest plus `skills/`, and the actual workflow logic lives in `shared/`.

Do not fork these workflows per project. Put project-specific rules in the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or relevant `README.md` files. The adapters instruct agents to read those files before acting and to treat explicit hard rules as blockers.

## Workflows

| Workflow | Claude Code command | Codex skill |
| --- | --- | --- |
| PR review | `/claude-skills:pr-review` | `pr-review` |
| PR triage | `/claude-skills:pr-triage` | `pr-triage` |

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

`scripts/build-review-payload.py` assembles and validates the single GitHub review payload
for `pr-review` (stdlib-only Python 3), so review bodies and inline comments are written as
plain Markdown instead of hand-escaped JSON. The `pr-review` workflow finds it under
`${CLAUDE_PLUGIN_ROOT}/scripts/`, `.claude/scripts/`, or `scripts/`, and falls back to a
hand-written payload when it isn't present.

## License

MIT © Caleb Sargeant
