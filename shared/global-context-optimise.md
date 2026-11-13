# Global context optimisation workflow

Before acting, read the user's global instruction files end to end: `~/.claude/CLAUDE.md` with its
`@`-imports and every file in `~/.claude/rules/` for Claude Code, and `$CODEX_HOME/AGENTS.override.md`
or `$CODEX_HOME/AGENTS.md` for Codex (`CODEX_HOME` defaults to `~/.codex`). Treat hard rules written
there as blockers: a rule that names a hook, a setting or a file as off limits wins over this file.

You are tuning the user-level setup that every agent session on this machine inherits, in every
repository and every directory. `context-optimise` installs a context stack in one repository. This
workflow installs nothing: it measures what the user-level setup loads into every session, cuts
duplicates, stale entries and noise from it without losing a rule the user wrote, and hands back the
removals that are the user's call.

## The one rule that matters most

**A smaller context window is not the goal. A higher signal-to-token ratio is.** The reasoning is the
same as in `context-optimise`, and the global tier sharpens both sides of it. A line here is paid in
every session in every repository, so noise costs more here than anywhere else. A rule here is also
the only rule that reaches every repository, so cutting one costs more here too.

The test for every line that loads by default: **would an agent get this wrong, or spend real tokens
finding it out, if the line were not here?** If not, it belongs in an on-demand file or nowhere. And
stale content is worse than absent content, here as everywhere.

## Voice

- Terse. Fragments, imperatives, bullet lists in every file you write for the agent.
- Every number in the report is measured in this run and labelled as measured. An estimate is
  labelled as an estimate.
- Real commands with real flags. No attribution footers, no "AI-generated" branding.

## Rules of engagement

- **Never delete a rule the user wrote.** You may move it, split it or tighten its wording. You may
  not drop its substance, and every move gets reported line by line.
- **Ask before removing a capability.** Skills, commands, plugins, MCP servers, account connectors and
  hooks change what the agent can do, not only what it is told. Report each one with its measured
  cost and the exact command or setting that removes it, and act only on the user's yes.
- **Back up before you edit.** Copy every file you change into one dated archive directory outside
  every auto-loaded path, mirroring the original paths, for example
  `~/.claude/archive/<date>-global-context-optimise/`. A removal is a move into that archive.
- **Never touch auth, signing or secret wiring.** `env` entries, hooks and helper scripts that
  authenticate git, sign commits or fetch secrets stay byte for byte as they are, even when they look
  like noise. If a global instruction explains such wiring, the explanation may move on demand. The
  rule not to disable it stays loaded.
- **Never print a secret.** `settings.json`, `~/.claude.json` and MCP configs carry tokens in `env`
  and `headers`. Inventory key names only, never values.
- **Don't edit third-party files in place.** Installed skills and plugin caches are overwritten on the
  next update, and their descriptions are tuned for triggering. Report them instead.
- **Idempotent.** A second run on an already-tuned setup changes nothing.
- **Global config is usually not a repository.** If it is one, leave the edits uncommitted.

## 0. Inventory what loads by default

Claude Code surfaces, and when each one is paid:

| Surface | Where it lives | Paid |
| --- | --- | --- |
| Global instructions | `~/.claude/CLAUDE.md` plus its `@`-imports | every session |
| Global rules | every `~/.claude/rules/*.md` | every session |
| Skill and command listing | name and description of each `~/.claude/skills/*/SKILL.md`, each `~/.claude/commands/**/*.md`, and every enabled plugin's skills, commands and agents | every session |
| Hook output | stdout of `SessionStart` and `UserPromptSubmit` hooks, from `settings.json` and from plugins | every session, every prompt |
| MCP server instructions | each connected server: user scope (`~/.claude.json` `mcpServers`), plugin or account connector | every session |
| MCP tools | schemas of tools that load up front; a deferred tool adds only its name to a listing | every session |
| Auto-memory index | `~/.claude/projects/<project>/memory/MEMORY.md` | every session in that project |
| Ancestor instructions | a `CLAUDE.md` in a parent directory of where sessions start, such as an org folder above many repositories | every session below it |

Nothing else loads until asked for: skill bodies, memory files other than the index, and any file in
a directory no loader reads.

Codex surfaces: `$CODEX_HOME/AGENTS.override.md`, or `$CODEX_HOME/AGENTS.md` when there is no override
(only one of the two loads); MCP servers under `[mcp_servers.<name>]` in `$CODEX_HOME/config.toml`,
where `enabled = false` switches a server off and `enabled_tools` / `disabled_tools` trim its tools;
user skills in `~/.agents/skills/`; custom agents in `$CODEX_HOME/agents/`. Repository `AGENTS.md`
files load from the project root down to the working directory.

List the MCP servers without their secrets:

```sh
python3 - <<'PY'
import json, pathlib
d = json.loads((pathlib.Path.home() / ".claude.json").read_text())
for name, s in d.get("mcpServers", {}).items():
    print(name, s.get("type", "stdio"), s.get("command") or s.get("url"),
          "env:", sorted(s.get("env", {})), "headers:", sorted(s.get("headers", {})))
PY
```

## 1. Measure before you change anything

Claude Code's context report runs headless. Run it from an empty directory, so no repository
instructions or project memory load and the numbers are the global tier alone:

```sh
probe="$(mktemp -d)" && (cd "$probe" && claude -p "/context") > context-before.txt
```

It prints tokens per category (memory files, skills, MCP tools, MCP server instructions, custom
agents, messages) and per item. Deferred tool categories are listed but not counted in the total.
Hook output is counted under messages. The probe starts a real session, so `SessionStart` hooks run,
which is what you want measured.

Then probe the two or three directories where the user starts most sessions. That adds their
auto-memory index and any ancestor `CLAUDE.md`. Rank them by transcripts from the last 30 days:

```sh
python3 - <<'PY'
import pathlib, time
root = pathlib.Path.home() / ".claude/projects"
now, counts = time.time(), {}
for d in root.iterdir():
    if d.is_dir():
        key = d.name.split("--claude-worktrees-")[0]  # worktree sessions use the main project's memory
        counts[key] = counts.get(key, 0) + sum(
            1 for j in d.glob("*.jsonl") if now - j.stat().st_mtime < 30 * 86400)
for key, n in sorted(counts.items(), key=lambda kv: -kv[1])[:10]:
    index = root / key / "memory" / "MEMORY.md"
    print(n, key, len(index.read_text().split()) if index.exists() else 0, "index words")
PY
```

Desktop and web sessions can also load account connectors that a headless CLI run does not show.
List them from inside such a session (its connector status), count their tools, and report the
deferred-name cost separately, as an estimate: a deferred tool costs its full name, and connector
names prefixed with a UUID cost tens of tokens each.

Without a context report (Codex, older CLIs), estimate words × 1.3 for prose and treat it as a
tripwire only. Identifier-heavy files (paths, hyphenated names, issue numbers, UUIDs) tokenise far
worse: a 2,500-word memory index measured 6.7k tokens.

## 2. Global instructions

Read the file section by section and sort each one into one of three groups:

1. **A rule for every session**, such as git policy, output style or a standing "never". It stays
   loaded. Tighten the wording only where the meaning is unchanged.
2. **A procedure or reference needed only when something happens**, such as how a signing setup works
   and how to fix it when it fails, a ticket format, or a credential rotation. Move it verbatim into an
   on-demand file, and leave the rule plus one pointer line that says when to read the file.
3. **A copy of something already loaded**: the harness's own instructions, a plugin's injected style
   rules, an installed rule file. Keep the user's version and note the overlap in the report.

On-demand files go in a directory nothing auto-loads, such as `~/.claude/reference/`. Never in
`~/.claude/rules/`, where every file loads, and never `@`-imported.

Promote in the other direction too. The same rule saved as a memory in three or more projects, such as
a commit-trailer policy that a global git hook enforces, is a global rule living in the wrong tier.
Add it to the global instructions in one line, and leave the project memories that carry extra detail.

If the user runs both Claude Code and Codex, reconcile the two global files the way `context-optimise`
reconciles `CLAUDE.md` and `AGENTS.md`: one canonical file, the other pointing at it, both saying
which is which.

## 3. Rules directory

Every file in `~/.claude/rules/` loads in every session. Tools add files here at setup time, and those
often restate the tool's own MCP server instructions or skill almost word for word. A rule file that
is fully covered elsewhere is a duplicate: archive it and say in the report what covers each part.

Check authorship before you archive. Signs a tool wrote it: a creation time matching that tool's
skill or config install, wording identical to the server's instructions, punctuation the user's own
style rules ban. A file the user wrote stays, or moves on demand behind a pointer.

## 4. Skill and command listing

From the probe's skills table, list every entry with its source and tokens, then look for:

- **Duplicates.** A personal command or skill that does what an installed plugin's workflow does, or
  an older version of it. Before proposing a deletion, check what still calls the personal name:
  repository `CLAUDE.md` maintenance blocks often name `/<command>`.
- **Families paid everywhere and used somewhere.** A toolkit installed for one kind of work, such as
  video production or one cloud vendor's skills, costs its whole listing in every session. The user's
  options: keep it, uninstall it, or scope it to the projects that need it (the project's
  `.claude/skills/`, or a plugin enabled only in that project's `.claude/settings.json`).
- **Runbooks invoked by name.** `disable-model-invocation: true` in a skill's frontmatter removes it
  from the listing and keeps `/<name>` working. That fits one-off operational procedures better than
  deletion. Re-run the probe to confirm: such skills drop out of the skills table.
- **Deprecated plugin aliases.** They cost a listing entry until the plugin drops them. Note them;
  don't edit the plugin.

## 5. Plugins

- Compare `enabledPlugins` in `~/.claude/settings.json` with `~/.claude/plugins/installed_plugins.json`
  and with each marketplace's current plugin names. A renamed plugin leaves the old name enabled at an
  old version and the new name missing. Report the swap (uninstall the old name, update the
  marketplace, install the new name) for the user to approve.
- For each enabled plugin, record its listing tokens, its agents, the MCP servers it starts and any
  tools it loads up front, and its hooks by event. `SessionStart` and `UserPromptSubmit` stdout lands
  in the session. Other events usually print nothing into context, but `PreToolUse` and
  `PostToolUse` hooks start a process on every tool call.
- `extraKnownMarketplaces` entries with nothing installed from them are stale config with no context
  cost. Report them.

## 6. MCP servers and connectors

Each connected server costs its instructions in every session, the schemas of any tools that load up
front, and a name per deferred tool. Look for:

- **The same service connected twice**, for example a user-scope server and an account connector.
- **Servers stuck waiting for authentication.** They add a notice to every session and no tools.
- **Servers only one project uses.** They belong in that project's `.mcp.json`
  (`claude mcp add --scope project`).
- **Stdio servers started with `npx -y`**, which download and start a process on every session start.

Account connectors are managed in the account's connector settings, not in local files. Report them
with their tool counts for the user to switch off. In Codex, `enabled = false`, `enabled_tools` and
`disabled_tools` under `[mcp_servers.<name>]` trim a server without deleting it.

## 7. Hook-injected context

`SessionStart` hooks add their stdout to every session and `UserPromptSubmit` hooks add theirs to
every prompt, so the second cost repeats with every message the user sends. Report each hook with its
size and any overlap with the global instructions, such as a style plugin injecting rules the
instructions already state. Never remove a hook without the user's yes, and never touch one that
authenticates, signs or fetches secrets.

## 8. Auto-memory

Each project's `MEMORY.md` index loads into every session there. Weight each index by its sessions
from step 1: a long index in a busy workspace is the largest per-session memory cost there is, and the
index of a project nobody opens costs nothing.

- **Hooks that carry content.** The index holds pointers. The facts belong in the linked file. Rewrite
  each hook to name what the memory is about in a few words and drop dates, figures and outcomes. Keep
  every entry, link and line in order. Keep a prohibition ("don't restore X", "read-only") and an
  expiry or deadline that is near or just past in the hook, because a session can act, or fail to,
  before it opens the file.
- **Copies of global rules.** A memory that only restates a global instruction adds nothing. One that
  carries the why or a per-project exception stays.
- **Broken links and orphans.** An index line pointing at a missing file misleads, and a memory file
  missing from the index is invisible to recall. Fix the index.
- **Stale entries.** Report them. Don't rewrite facts you can't verify.

Other sessions keep writing to these indexes while you work, so a busy one can gain entries between
your backup and your rewrite. Re-read the index right before you write it, and never drop an entry
you did not see in the backup.

Back up each index before rewriting it, and check afterwards that it links the same files in the same
order, plus only the entries other sessions added in the meantime:

```sh
diff <(grep -o '([^)]*\.md)' "$ARCHIVE/projects/$PROJECT/memory/MEMORY.md") \
     <(grep -o '([^)]*\.md)' ~/.claude/projects/"$PROJECT"/memory/MEMORY.md) && echo "links unchanged"
```

## 9. Verify

Run every check and report its real output. Never report a check you did not run.

1. Re-run the same probes, from the empty directory and from each project directory. Report before
   and after per category and per file.
2. Every moved rule exists in its new file, and every pointer names a file that exists.
3. Every rewritten memory index links the same files in the same order as its backup, plus any
   entries other sessions added during the run, and no memory file is left out of its index.
4. Auth, signing and secret wiring is unchanged: diff the `env` and `hooks` blocks of
   `settings.json` against the archive copy.
5. Nothing that removes a capability ran without the user's yes.

## 10. Report

- **Tokens, measured**: before and after, total and per category, for each probe.
- **Edits**: one line each, and every move line by line (what moved, where to, which pointer replaced
  it).
- **The user's call**: each proposed removal or scope change with its measured cost and the exact
  command or setting that applies it, ranked by tokens saved per session times how often those
  sessions run.
- **Archive**: where the backups are and how to restore one.

## How this goes wrong

- **Slimming by deleting.** The user asked for less noise, not fewer rules. A rule cut from the global
  tier is a rule no repository sees.
- **A move without a pointer.** The procedure is still on disk, and no session knows to read it.
- **Measuring from inside a repository.** Project instructions and memory get counted as global, and
  the before and after compare two different things.
- **Reading deferred tools as loaded**, or forgetting that each deferred name still costs tokens.
- **Treating the auth hook as noise.** It prints nothing and looks idle until the day it is removed and
  every push fails.
- **Editing third-party files** that the next update silently reverts.
- **Printing secrets** from `settings.json` or an MCP config while inventorying them.
- **Trimming the quiet project's memory** while the busy workspace's index stays at thousands of
  tokens.

## Definition of done

- The default context measured before and after with the same probes, with the numbers in the report.
- Every rule the user wrote is still loaded, or reachable through a pointer that is loaded.
- Every removal of a capability is either approved by the user or listed for their call with its cost.
- A backup exists for every changed file, and nothing that authenticates, signs or fetches secrets
  changed.
- Every verification check run, with its real output in the report.
