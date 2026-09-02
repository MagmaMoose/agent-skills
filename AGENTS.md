# agent-skills

CLAUDE.md is the canonical agent context file for this repository.
Read CLAUDE.md in full. Every rule there applies equally to all agents.

This file exists so agents that auto-load AGENTS.md instead of CLAUDE.md start from the same rules.
Edit CLAUDE.md; edit this file to match. They must not drift.

## What this repo is

Shared agent workflows for Claude Code (commands/, namespace claude-skills) and Codex (skills/).
Canonical logic lives in shared/; both adapters delegate to it.

## Three-layer pattern

Every workflow spans three files:
- shared/{workflow}.md — canonical logic (edit this)
- commands/{workflow}.md — Claude Code adapter (/claude-skills:{workflow})
- skills/{workflow}/SKILL.md — Codex adapter (invoke by skill name)

## Key rules

- Edit shared/ first. commands/ and skills/ are thin adapters with no logic of their own.
- Every new workflow needs all three files and a README.md table update.
- Never @-import PROJECT_INDEX.json. Reference it by path only.
- Deprecated aliases: tvos-swiftui -> swiftui-build, update-docs -> docs-update.
- Bump both plugin versions (.claude-plugin/plugin.json and .codex-plugin/plugin.json) on release.
- No build step. Scripts run directly; stdlib-only Python 3.

Before locating unfamiliar code, read ./PROJECT_INDEX.json first.
