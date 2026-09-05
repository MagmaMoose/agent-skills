---
name: mikrotik-routeros
description: Write, review or debug code that touches MikroTik RouterOS devices — scripting, /tool fetch telemetry, hardening checks, upgrades and fleet operations — without inventing property names, missing a version gate, or shipping a command that locks an operator out of a remote router.
---

Use the shared MagmaMoose MikroTik RouterOS reference.

Read and follow:
- `shared/mikrotik-routeros.md` — read this ALWAYS, before writing a line
- Then only the deeper file the task needs:
  - `shared/mikrotik/scripting.md` — RouterOS script, `/tool fetch`, schedulers, policy
  - `shared/mikrotik/security.md` — hardening, CVEs, incidents, indicators of compromise
  - `shared/mikrotik/upgrades.md` — RouterOS/RouterBOOT upgrades, licensing, hardware limits
  - `shared/mikrotik/networking.md` — interfaces, wireless, LTE, firewall, routing, queues
  - `shared/mikrotik/operations.md` — fleet-scale failure modes and operator practice
- The target repository's `CLAUDE.md`, `AGENTS.md` and `CONTRIBUTING.md`
- The files neighbouring the one you are editing

Treat target-repository hard rules as blockers.

Expected input: a change, review or bug involving RouterOS — a script that runs on
a router, a service that collects from routers, a check that scores them, or an
operation performed on them.

## Why this skill exists

RouterOS punishes plausible guesses. The scripting language returns `nil` instead
of raising, the transport truncates silently, menus rename between major versions,
and several defaults are the opposite of the sensible assumption. Code written
from memory usually *runs* — it just does the wrong thing quietly, on production
hardware, hours later.

The reference was researched against MikroTik's own documentation and changelogs
and then independently fact-checked. The check found roughly one error in four:
invented property names (`http-code-min`, `uicc`), invented flags (`duration=` on
`/tool/torch`), invented enum values (`isdn` on `/ppp/secret`), version gates
asserted with nothing behind them. All of them read as completely plausible.

## Hard rules

**Never invent a property name, menu path, enum value, command flag or CVE.** If
it is not in the reference or in MikroTik's current docs, say you do not know and
go and look. A wrong property name produces an empty string, not an error, so it
reaches production and reads as "the device did not report that".

**State the version gate or do not state the behaviour.** "Recent RouterOS" is
useless. `7.13 added X` with the CHANGELOG behind it is usable. RouterOS 6 and 7
differ enough that a claim without a version is a claim about neither.

**Rate the lockout risk of anything that changes a device.** These are routers
managed remotely, often the only path to the site. Applying a default-deny input
rule over the link you manage the device with is how a router is lost
permanently. Before proposing any mutating command, say what happens if it goes
wrong and whether the operator can still reach the device.

**Prefer a mechanism that undoes itself over an instruction to be careful.** The
scheduler-based commit-confirm pattern in the reference is what makes remote
hardening defensible: schedule the undo, apply, cancel the undo only once the
device proves it survived. Note its limits — it reverses configuration, not a
reboot or a firmware upgrade, and the restore-from-backup variant is documented
as unvalidated.

**Never write code that executes what the network sends it.** `:parse` of a
response body, `/system script add source=$fetched`, `/import` of a downloaded
file — each is remote code execution into the router, and one shipped commercial
MikroTik agent does exactly this hourly. Send verbs, match literals, dispatch with
`:if`.

**Guard every optional menu.** Referencing `/interface wireless` or `/ppp active`
on an install without that package aborts the entire script, not just that line —
so one unguarded line silently stops all telemetry on part of a fleet.

## Before you finish

- Every fetch sets `check-certificate=yes` explicitly.
- Every value concatenated from `print`/`get` output is wrapped in `[:tostr …]`
  (array-valued properties distribute across `.` instead of joining).
- Every payload fits the transport: 64 KB request body, 64 KB response on v7,
  **4 KB response on v6**.
- Every `monitor` call uses `once` and a `do={}` block.
- Policy is set on both the script and the scheduler, and includes `test` (plus
  `ftp` on 7.13+) for `/tool fetch`.
- Anything parsed with `:tonum` is checked for `nil` before it is compared.
- Any version-gated command is branched, not stated flatly.
