---
description: Write, review or debug code that touches MikroTik RouterOS, using the verified reference rather than recall
argument-hint: "[the change, review or bug — a script, a collector, a check, or an operation]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(find:*), Bash(ls:*), Read, Write, Edit, Grep, Glob, WebFetch, WebSearch
---

Work on MikroTik RouterOS using the shared MagmaMoose reference.

**First, read `shared/mikrotik-routeros.md` in full.** It is short and it carries the traps that
actually cause outages. It lives at the first of these paths that exists (check in order):

1. the newest-versioned match of `~/.claude/plugins/cache/magmamoose/claude-skills/*/shared/mikrotik-routeros.md` — the installed plugin (source of truth)
2. `.claude/shared/mikrotik-routeros.md` — headless runs
3. `shared/mikrotik-routeros.md` — working inside the agent-skills checkout

**Then read only the deeper file the task needs**, from `shared/mikrotik/` alongside it:
`scripting.md`, `security.md`, `upgrades.md`, `networking.md`, `operations.md`.

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- The files neighbouring the one you are editing

Treat target-repository hard rules as blockers.

**Hard rules — these hold even if the reference cannot be found:**

- **Never invent a property name, menu path, enum value, command flag or CVE.** A wrong property
  name in RouterOS produces an empty string rather than an error, so it reaches production and
  reads as "the device did not report that". If it is not in the reference or in MikroTik's current
  documentation, say so and go and look.
- **State the version gate or do not state the behaviour.** RouterOS 6 and 7 differ enough that an
  unqualified claim is a claim about neither. Cite the release CHANGELOG.
- **Rate the lockout risk of anything that changes a device.** These are routers managed remotely,
  often the only path to the site. Say what happens if the change goes wrong and whether the
  operator can still reach the box.
- **Prefer a mechanism that undoes itself** — the scheduler commit-confirm pattern — over an
  instruction to be careful. Know its limits: it reverses configuration, not a reboot or a firmware
  upgrade, and the restore-from-backup variant is documented as unvalidated.
- **Never execute what the network sends.** No `:parse` of a response, no `/system script add` from
  a fetched body, no `/import` of a download. Send verbs; match literals; dispatch with `:if`.
- **Guard every optional menu.** An unguarded `/interface wireless` on an install without that
  package aborts the whole script, so one line silently stops telemetry across part of a fleet.
- **`check-certificate=yes` on every fetch, explicitly.** RouterOS defaults it to `no`.

**Before finishing:**

- Every value concatenated from `print`/`get` output is wrapped in `[:tostr …]`.
- Every payload fits: 64 KB request body, 64 KB response on v7, 4 KB response on v6.
- Every `monitor` call uses `once` with a `do={}` block.
- Policy is on both the script and the scheduler, including `test` (and `ftp` on 7.13+) for fetch.
- Anything parsed with `:tonum` is checked for `nil` before comparison.

Where the reference disagrees with MikroTik's current documentation, the documentation wins — say
so, and fix the reference in the same change.

Input: $ARGUMENTS
