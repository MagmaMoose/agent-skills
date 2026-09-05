# MikroTik RouterOS for agents writing code that touches real routers

This reference exists because RouterOS punishes plausible guesses. Its scripting
language returns `nil` instead of raising, its transport silently truncates, its
menus change name between major versions, and several of its defaults are the
opposite of what a reasonable person would assume. Code written from memory
usually *runs*. It just does the wrong thing quietly, on someone's production
router, hours later.

Everything here was researched against MikroTik's own documentation and
changelogs, then independently fact-checked. The check found roughly one error in
four — invented property names, wrong version gates, commands that do not parse.
Those are corrected inline in the deeper files, marked **Review correction**, and
the correction wins over the paragraph above it.

## How to use this

Read this page. Then load only the deeper file you need:

| File | When |
| --- | --- |
| `shared/mikrotik/scripting.md` | Writing RouterOS script, or anything using `/tool fetch` |
| `shared/mikrotik/security.md` | Hardening checks, CVEs, incident indicators |
| `shared/mikrotik/upgrades.md` | RouterOS/RouterBOOT upgrades, licensing, hardware limits |
| `shared/mikrotik/networking.md` | Interfaces, wireless, LTE, firewall, routing, queues |
| `shared/mikrotik/operations.md` | Fleet-scale failure modes and operator practice |

Two standing rules for using any of it:

1. **Never invent a property name, a menu path, an enum value or a CVE.** If it
   is not in these files or in MikroTik's docs, say you do not know. The
   fact-check pass caught invented properties (`http-code-min`, `uicc`), invented
   flags (`duration=` on `/tool/torch`), and invented enum values (`isdn` on
   `/ppp/secret`, `nat` on `cake-flowmode`) — all of which read as completely
   plausible and none of which exist.
2. **State the version gate or do not state the behaviour.** "Recent RouterOS"
   is useless. "7.13 added X, see that release's CHANGELOG" is usable.

---

## The traps that actually cause outages

These are ranked by what they cost when you get them wrong, not by how
interesting they are.

### `check-certificate` defaults to `no`

Every `/tool fetch` that omits it will happily talk to anyone. If the request
carries a token — and a dial-out agent's request always does — that token goes to
whoever answers. Set it explicitly on **every** fetch, without exception.

```routeros
/tool fetch mode=https http-method=post check-certificate=yes url=$u http-data=$body
```

### `:parse` of anything from the network is remote code execution

Same for `/system script add source=$fetchedBody` and `/import` of a downloaded
file. A management agent that can be replaced from the network is not a
management agent, it is a backdoor with a maintenance story. This is not
theoretical: a shipped commercial MikroTik agent fetches a body hourly and runs
it as a script, with the entire validation being "longer than ten characters".

Send **verbs**, match them with `:find`, dispatch with `:if`. Anything that
cannot be a fixed verb is commands the operator pastes themselves.

### The transport has hard size caps, and they differ by major version

* `/tool fetch` `http-data` (the request body): **64 KB**.
* The captured response via `output=user … as-value`: **64 KB on RouterOS 7**.
* **On RouterOS 6 the ceiling is 4096 bytes**, because that is the documented
  limit on a variable's value — nothing to do with fetch.

Base64 inflates by a third, so a payload ceiling of 64 KB is ~48 KB of real
bytes. A whole `/export` from a moderately configured router exceeds that. Chunk
it, and keep any response the device must read well under 4 KB if RouterOS 6 is
in scope.

### Concatenating an array with `.` distributes instead of joining

```routeros
:put ("value is: " . $arr)     # $arr={"a";"b"} prints TWO lines, both prefixed
:put ("value is: " . [:tostr $arr])   # correct
```

Several RouterOS properties are arrays even when they look scalar
(`gateway={"ether1"}`). Any string built by concatenation from `print`/`get`
output must wrap every value in `[:tostr …]`, or a single array-valued property
silently corrupts the whole payload.

### `print as-value` returns a 2-D array for list menus

Even with one match. `[/ip/route/print as-value where gateway="ether1"]->"gateway"`
returns nothing, because the result is an array *containing* one dictionary.

```routeros
:put ([:pick [/ip/route/print as-value where gateway="ether1"] 0]->"gateway")
:foreach r in=[/ip/service/print as-value] do={ :put ($r->"name") }
```

Settings menus (`/system resource`, `/ip dns`, `/snmp`) are 1-D and `get` works
directly. Which you get depends on the menu, not the match count — check once per
menu rather than assuming.

### Referencing a menu whose package is absent aborts the WHOLE script

Not just that line. `/interface wireless`, `/ppp active`, `/ip dhcp-server`,
`/ipv6`, `/mpls` are all optional. On a stripped install an unguarded reference
kills every subsequent statement — which, in a telemetry agent, means a slice of
the fleet silently stops reporting after a release that touched one line.

```routeros
:if ([:len [/system package find where name="wireless" disabled=no]] > 0) do={ ... }
```

Wrap optional reads in `:do { ... } on-error={ }`. Note `:do/on-error` works on
both v6 and v7; `:onerror` is 7.13+ and `:retry` is 7.4+, so neither belongs in a
script that must run on RouterOS 6.

### `:tonum` returns `nil` rather than failing

A malformed value does not raise — it produces a value whose type is `nil`, and
every comparison against it silently takes the false branch. Check
`[:typeof $n] = "nil"` before branching on anything parsed from outside.

### Policy applies to the scheduler, not only the script

`on-event="/system script run NAME"` runs with the **scheduler's** policy; a bare
script name runs with the script's own. Set the same policy on both. `/tool fetch`
needs `test` on every version, and additionally `ftp` from 7.13.

### `monitor` commands never return without `once`

There is no `as-value` and no `get` for them. Without `once` the command runs
forever and the scheduled job never finishes — so the agent stops permanently,
not just this cycle.

```routeros
/interface ethernet monitor ether1 once do={ :set s $"status" }
```

### `:put` writes to a terminal a scheduled script does not have

Its output is discarded, not logged. A scheduled script reports by `:log`, by
`/tool fetch`, or not at all.

### device-mode gates `scheduler` and `fetch`, and needs physical presence to undo

RouterOS 7 `device-mode` (`advanced` | `home` | `basic` | `ros` — the CLI value is
`ros`, not `rose`) gates a feature list that includes both of the things a
dial-out agent depends on entirely. A customer who tightens it kills their own
monitoring, and re-enabling requires someone at the router with the reset button.
Read it, display it, warn before it bites.

### Health sensor values are scaled for scripts, and voltage is not documented

Temperature: "Using scripts/API/SNMP this value will be shown in CLI/Winbox
multiplied by 10" — 41.5 °C arrives as 415. A naive threshold either never fires
or always fires. Voltage scaling is *commonly* decivolts but MikroTik does not say
so; calibrate per model rather than assuming. Sensor rows are per-model, and the
`type` enum includes empty values whose `value` is a status word (`ok`, `fail`,
`not-present`), not a number.

### `/ip cloud set ddns-enabled=no` does not parse on current RouterOS

The enum is `auto | yes` from 7.17. `no` is correct on RouterOS 6 and pre-7.17
only. This is version-gated and must be branched, not stated flatly.

### Logging topics are ANDed, not ORed

`topics=info,error,warning,critical` matches a message carrying *all four*, which
is none of them. Emit one rule per topic.

---

## The hardware and version facts that change what you may offer

* **RouterOS 7 needs 64 MB of RAM.** MikroTik: "We do not recommend running v7 on
  hardware that does not have at least 64 MB of RAM." That pins a large installed
  base of cheap CPE (32 MB hAP lite, RB951) to the 6.49.x long-term line
  permanently. A console that nags those devices to upgrade is worse than one
  that says nothing.
* **RouterOS 7.13 split the radio drivers out.** Legacy `/interface wireless`
  support moved into a separate `wireless` package. A device with legacy radios
  that crosses 7.13 without it comes back with **no radios**. It fires on 7.12 →
  7.13, not only on the v6 → v7 jump — the mechanism is the package split, not the
  major version.
* **RouterBOOT is upgraded separately from RouterOS** and people forget. There is
  a better fix than an alert: `/system routerboard settings set auto-upgrade=yes`
  applies the bundled firmware after each RouterOS upgrade and eliminates the
  whole class. Note `/system/routerboard/settings` **is** device-mode gated;
  `/system/routerboard/upgrade` is not.
* **A CHR that cannot renew its licence stops accepting upgrades** and keeps
  routing. So the visible symptom of a licence problem is a box quietly falling
  behind on security patches, which looks like negligence rather than licensing.
* **Connection tracking fails as a cliff.** `max-entries` is RAM-dependent with a
  documented ceiling of 1,048,576. A busy CCR at 60% looks fine right up until it
  starts dropping packets. Read the ceiling from the device.
* **`/export` redaction flipped between major versions.** RouterOS 7 hides
  sensitive values **by default**; `show-sensitive` is the opt-in that produces a
  restorable file. RouterOS 6 was the other way round. Getting this backwards
  means either storing secrets you did not mean to, or storing a backup that
  cannot restore.
* **7.21 hides sensitive settings in `print` output by default**, and **7.20
  started including flags in `as-value` results**. Both change what a telemetry
  collector receives on upgrade without any change on your side.

---

## Security: what to check, and what not to bother reporting

The full catalogue with detection commands, fixes and lockout ratings is in
`shared/mikrotik/security.md`. Three framing rules matter more than the list:

**Do not report a device's known default state as a finding.** A factory RouterOS
box has telnet, ftp and www enabled. Reporting that on every device produces a
wall of "yes, I know" and trains the operator to skim. Fire on *exposure* — a
management service with no source restriction — not on the service existing.

**Hardening and compromise are different questions.** "You left a door open"
versus "someone came through it". Separate them, and rank compromise first
regardless of count: one router with `/ip socks` enabled matters more than thirty
with an open bandwidth-test server. MikroTik's own Mēris advisory names the exact
artefacts — scheduler entries that run a fetch script, and SOCKS.

**Every fix needs a lockout rating.** Applying a default-deny input rule to a
remote router, over the path you manage it with, is the classic way to lose a
device permanently. Rate every remediation, and prefer a mechanism that undoes
itself over one that asks the operator to be careful.

### The commit-confirm pattern

Operators build this by hand with the scheduler, and it is what makes remote
hardening sellable at all: schedule the undo, apply the change, and cancel the
undo only once the device proves it survived.

```routeros
/system scheduler add name=rollback interval=5m on-event="<the undo>; /system scheduler remove [find name=rollback]"
# apply the change here
# then, after the device checks in alive, the server tells it to:
/system scheduler remove [find name=rollback]
```

Note what this does and does not cover. It reverses a *configuration* change. It
cannot reverse a reboot or a firmware upgrade — those are gated instead: a fresh
backup, an explicit action, one device at a time. And the restore-from-backup
variant of this pattern is **not** validated: `/system/backup/load` prompts and
reboots, so a scheduler cannot drive it unattended. Treat any "auto-restore on
failure" design as unproven until it is demonstrated on a lab device.

---

## Where the authoritative answers live

* `https://help.mikrotik.com/docs/` and `https://manual.mikrotik.com/docs/` — the
  current documentation. The older `wiki.mikrotik.com` is frozen and describes
  RouterOS 6.
* `https://mikrotik.com/supportsec` — security advisories, each naming its fixed
  versions. This is the feed to consume for vulnerability state; do not maintain
  a private CVE list.
* `https://download.mikrotik.com/routeros/<version>/CHANGELOG` — the only
  reliable way to date a behaviour change. Cite it whenever you assert a version
  gate.

When these disagree with anything in this reference, they win. Say so, and fix
the reference.
