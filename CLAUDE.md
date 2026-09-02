# agent-skills

Shared agent workflows for Claude Code (commands/, namespace claude-skills) and Codex (skills/).
Canonical logic lives in shared/; both adapters delegate to it. Breaking shared/ breaks both platforms.

@.claude/ARCHITECTURE_MAP.md
@.claude/COMMON_MISTAKES.md

Before locating unfamiliar code, read ./PROJECT_INDEX.json first.

Read .claude/decisions/ and .claude/sessions/ only when the task relates to them, never by default.

## Commands

```bash
# Docs audit (stdlib Python 3, no install needed)
python3 scripts/docs-audit.py audit --root . --strict

# Cluster harvest for k8s-audit
scripts/k8s-harvest.sh <kube-context> ./harvest/prod

# Repo harvest for codebase-prune
scripts/cruft-harvest.sh . ./harvest/cruft
```

This repo has no build step. Scripts are run directly.

[tooling]
- Prefer targeted line-range reads over whole files; use PROJECT_INDEX.json to find the location.
- grep/find/glob: return matching paths and matched lines only, never whole-file dumps.
- Commands that can flood output: pipe through head/tail/grep, or redirect to .claude/last_output.txt and read ranges. Never paste thousands of lines into the transcript.
- After a successful write or edit, trust it. Don't re-read the file to verify it.

[maintenance]
- Bug that took more than an hour: append it to .claude/COMMON_MISTAKES.md.
- Architectural decision: write it to .claude/decisions/.
- Public behaviour, API, config or setup changed: sync README.md (this repo uses README, not ./docs).
- New workflow added: create all three files (shared/, commands/, skills/) and update README.md workflow table and plugin versions in both .claude-plugin/plugin.json and .codex-plugin/plugin.json.
- PROJECT_INDEX.json stale after a new module or a big refactor: regenerate the affected modules section only, and update "generated".
- Keep CLAUDE.md under ~500 tokens. Push detail into on-demand .claude/ files.

This file is canonical. AGENTS.md points here.
