# Context optimisation workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and
relevant `README.md` files. Treat explicit hard rules from the target repository as blockers: a
stated file layout, a "no new root-level files" rule, an existing agent-context convention, or a
house documentation system in the target repo all win over this file.

You are installing a layered context stack in one repository so that every future agent session
there starts with less noise and more signal. Five layers, each solving a different problem:

1. **Structural map** — how the agent finds unfamiliar code without reading the tree.
2. **Session context** — what the agent knows before it reads anything.
3. **Noise and access control** — what never reaches the context window at all.
4. **Persistent memory** — what survives the end of a session.
5. **Human docs** — the published surface, kept distinct from the agent surface.

## The one rule that matters most

**A smaller context window is not the goal. A higher signal-to-token ratio is.**

The two get confused constantly, and the confusion is expensive in both directions. Deleting a
200-token footguns file looks like a win on every measurement you can take in this session, and
then the same bug gets rediscovered three times over the next month at thousands of tokens a go.
Meanwhile a 4,000-token `CLAUDE.md` that restates the directory layout, re-explains what
`package.json` already says, and lists every module the agent could have found with one `grep` is
pure tax: it is paid on every single session, forever, and it buys nothing.

So the test for every line you put in the auto-loaded tier is not "is this true?" It is: **would
an agent get this wrong, or spend real tokens finding it out, if the line were not here?** If the
answer is no, the line belongs somewhere else or nowhere.

The corollary, which is the failure mode of this whole workflow: **content that is stale is worse
than content that is absent.** A missing index costs a search. An index that names a module that
was deleted three months ago costs a wrong plan, a confident wrong answer, and the trust of the
next person who reads it.

## Voice

Binding on every file you write here, and on the report at the end.

- Terse. These are agent-facing files, not prose for humans. Fragments, imperatives, bullet lists.
- Every claim is something you verified in this run. No aspirational architecture, no "should be",
  no describing the codebase you expected to find.
- Name real commands with real flags, copied from the repo's own config, not remembered.
- No attribution footers of any kind, no robot emojis, no "AI-generated" branding, in any file you
  write or any commit message you propose.
- `./docs` pages are the exception to the terseness rule and follow the `docs-update` voice
  instead: full sentences, second person, no em-dashes.

## Rules of engagement

- **Never delete a hard-won rule.** An existing `CLAUDE.md` is the accumulated scar tissue of
  everyone who worked here before you. You may move it, split it, or tighten its wording. You may
  not drop its substance, and every move gets reported line by line: what moved, and where to.
- **Never invent a command.** Every build, test, lint and run command in the files you write was
  read out of `package.json`, `Makefile`, `pyproject.toml`, `justfile`, `Cargo.toml`, a CI
  workflow, or the repo's own README in this run. If you cannot find one, say so and leave it out.
- **Idempotent.** Running this a second time must not duplicate sections, re-append the
  maintenance block, or clobber hand-written content. Read what exists, then merge.
- **Never write a secret into a file you create.** Not a token, not an internal hostname, not a
  production URL. Placeholders only.
- **Never add a dependency to the target repository** to make a layer work. If MkDocs is not
  installed, report the install command; don't add it to a lockfile.
- **Write the changes, then show them.** Don't stop mid-run to ask permission for each file. Make
  the edits, verify, then report.
- **Never commit, push, or open a PR** unless explicitly asked. The run ends with a dirty working
  tree and a report.

## 0. Read the repo before you write anything

Everything below is derived from the repo in front of you. A generic stack helps nobody.

```sh
# what this repo actually is
ls -a
git log --oneline -20
```

Establish, from files and not from assumption:

- **Languages and package managers.** `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`,
  `Gemfile`, `pom.xml`, `build.gradle*`, `*.csproj`, `Package.swift`, `mix.exs`.
- **Build / test / lint / run commands.** Read them out of the manifest's script block, the
  `Makefile`/`justfile` targets, and the CI workflow under `.github/workflows/`. CI is the honest
  source: it is what has to pass.
- **Entrypoints.** `main`, `cmd/`, `src/index.*`, `app/`, `__main__.py`, a `bin` block, a
  `console_scripts` entry, a Dockerfile `CMD`/`ENTRYPOINT`.
- **Where the source actually lives**, as opposed to vendored, generated and fixture directories.
- **What already exists of this stack**: `CLAUDE.md`, `AGENTS.md`, `.claude/`, `PROJECT_INDEX.json`,
  `.cursor/rules`, `.github/copilot-instructions.md`, `docs/`, `mkdocs.yml`. You are extending
  what is there, not landing on empty ground.

If a `CLAUDE.md` or `AGENTS.md` already exists, read it end to end now, before you plan anything.
Its content is an input, not an obstacle.

## 1. Layer 1 - The structural map

**Problem it solves:** locating unfamiliar code currently costs a tree walk, several greps, and a
few speculative file reads, every time, in every session.

Write `PROJECT_INDEX.json` at the repo root:

```json
{
  "generated": "<ISO-8601 date>",
  "summary": "<2-3 sentences: what this repo is and what it does>",
  "entrypoints": ["<file>:<symbol>"],
  "modules": {
    "<name>": { "path": "", "purpose": "", "exports": [], "depends_on": [] }
  },
  "callgraph_highlights": [ { "caller": "", "calls": [], "note": "" } ],
  "hotspots": ["<5-10 files touched in most tasks>"]
}
```

Rules that make the difference between an index and a liability:

- **Meaningful modules only.** Not every file. If a directory has no purpose you can state in one
  clause, it is not a module.
- **Under ~300 lines.** A map you have to search is not a map.
- **Load it on demand, by path.** Put this line in `CLAUDE.md`: `Before locating unfamiliar code,
  read ./PROJECT_INDEX.json first.` **Never `@`-import it** — an `@`-import puts the whole file in
  context on every session and converts your index into exactly the tax it was built to avoid.
- **`depends_on` names other modules in this file**, not third-party packages. The point is the
  internal graph.
- **`callgraph_highlights` covers the three or four flows that matter** (request lifecycle, build
  pipeline, auth path), not the whole graph.
- **If a repo-map MCP server is configured** (CodeGraph or similar), prefer it and keep this file
  as the fallback. Say in the report which one is authoritative.

Derive `hotspots` from history rather than instinct:

```sh
git log --since="6 months ago" --name-only --pretty=format: \
  | grep -v '^$' \
  | grep -vE '(lock|\.lock|-lock\.json|\.min\.|dist/|build/|vendor/)' \
  | sort | uniq -c | sort -rn | head -20
```

Then check the index does not already lie:

```sh
python3 - <<'PY'
import json, pathlib
idx = json.loads(pathlib.Path("PROJECT_INDEX.json").read_text())
paths = [m.get("path", "") for m in idx.get("modules", {}).values()]
paths += [e.split(":")[0] for e in idx.get("entrypoints", [])]
paths += idx.get("hotspots", [])
missing = sorted(p for p in paths if p and not pathlib.Path(p).exists())
print("missing paths:", missing or "none")
PY
```

Any missing path is a bug in the index, not a rounding error. Fix it before moving on.

## 2. Layer 2 - The session context

**Problem it solves:** the agent starts every session either knowing nothing about house rules, or
knowing 4,000 tokens of things it did not need.

Two tiers, and the split is the entire point:

- **Auto-loaded**: the root `CLAUDE.md` plus everything it `@`-imports. Paid on every session.
  Target the whole tier at **under ~1,000 tokens**.
- **On demand**: everything else under `.claude/`, read by path only when the task calls for it.
  Free until used.

### 2a. Create the on-demand files

```text
.claude/ARCHITECTURE_MAP.md   ~150 tokens, prose: the shape of the system and why
.claude/COMMON_MISTAKES.md    ~200 tokens: footguns, gotchas, the bugs that cost hours
.claude/QUICK_START.md        ~100 tokens: the ~10 most-run commands
.claude/decisions/            ADRs, on demand only
.claude/sessions/             session summaries, on demand only
```

`COMMON_MISTAKES.md` is the highest-value file in the stack and the one most likely to be written
badly. It is not a style guide. Every entry is a specific thing that has actually gone wrong here,
in the form *symptom, cause, what to do instead*. Seed it from evidence you can find in this run:
`git log --grep='^fix' --oneline -30`, revert commits, and any `HACK`/`XXX`/`WORKAROUND` comment
with a real explanation attached. If you find nothing, create the file with a one-line header and
say in the report that it starts empty, rather than padding it with generic advice.

### 2b. Write the root CLAUDE.md

Under ~500 tokens on its own. Contents, in order:

1. One paragraph: what this repo is, who uses it, what breaking it costs.
2. Build / test / lint / run commands, verbatim from the repo, or `@.claude/QUICK_START.md`.
3. `@.claude/ARCHITECTURE_MAP.md`
4. `@.claude/COMMON_MISTAKES.md`
5. `Before locating unfamiliar code, read ./PROJECT_INDEX.json.`
6. `Read .claude/decisions/ and .claude/sessions/ only when the task relates to them, never by
   default.`
7. The `[tooling]` block from section 3c.
8. The `[maintenance]` block from section 6.

Do **not** `@`-import `PROJECT_INDEX.json`, `.claude/decisions/`, or `.claude/sessions/`.

If a `CLAUDE.md` already exists, fold it in: keep every rule, move the long-form material into the
on-demand files, and record the mapping for the report. Never start by deleting.

### 2c. Two agents, one truth

Claude Code auto-loads `CLAUDE.md`. Codex and several other agents auto-load `AGENTS.md`. A repo
with both, drifting apart, is worse than a repo with one, because the two agents then disagree
about the rules and neither is wrong.

Pick one canonical file and make the other a pointer:

- If the repo already has an `AGENTS.md`, keep it canonical and make `CLAUDE.md` a short file whose
  substance is `@AGENTS.md` plus anything genuinely Claude-specific.
- If the repo has neither, or only a `CLAUDE.md`, keep `CLAUDE.md` canonical and write `AGENTS.md`
  as a thin file that carries the same rules in full. `AGENTS.md` has no `@`-import mechanism, so
  a pointer in that direction has to restate rather than reference — keep it short enough that
  restating is cheap, and say in the report that the two files must be edited together.

Whichever way round, say explicitly in both files which one is canonical.

## 3. Layer 3 - Noise and access control

**Problem it solves:** output that should never have entered the context window in the first
place, and files the agent should never read at all.

**There is no `.claudeignore` in Claude Code. Do not create one.** A file by that name does
nothing, and leaving one behind tells the next person a control exists when it does not. The real
levers are these three.

### 3a. .gitignore

Generated and heavy directories, because anything git ignores is largely invisible to search
tooling too: `node_modules/`, `dist/`, `build/`, `target/`, `__pycache__/`, `.venv/`, `coverage/`,
`site/`, `*.log`, plus whatever this repo's toolchain actually generates. Read the build config to
find out; don't paste a generic list.

### 3b. .claude/settings.json

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./**/*.pem)",
      "Read(./**/secrets/**)"
    ],
    "ask": ["Bash(git push:*)"]
  }
}
```

- Tool names are capitalised: `Read`, `Bash`, `Edit`, `WebFetch`.
- Precedence is `deny` > `ask` > `allow`, and the first matching rule wins.
- `.claude/settings.json` is checked in and shared with the team. Personal overrides belong in
  `.claude/settings.local.json`, which must be gitignored.
- Deny secrets and credentials. Do **not** deny paths the repo's own tooling has to read, and do
  not deny a whole tool because one of its uses is risky — a deny on `Bash(curl:*)` in a repo whose
  test suite shells out to `curl` breaks the test suite. Check before you add each rule.

### 3c. The [tooling] block

These act **before** output enters the context window, which is what makes them worth more than
any amount of trimming afterwards. Add verbatim to `CLAUDE.md`:

```text
[tooling]
- Prefer targeted line-range reads over whole files; use PROJECT_INDEX.json to find the location.
- grep/find/glob: return matching paths and matched lines only, never whole-file dumps.
- Commands that can flood output: pipe through head/tail/grep, or redirect to
  .claude/last_output.txt and read ranges. Never paste thousands of lines into the transcript.
- After a successful write or edit, trust it. Don't re-read the file to "verify" it.
```

Add `.claude/last_output.txt` to `.gitignore` if you reference it.

## 4. Layer 4 - Persistent memory

**Problem it solves:** everything learned in a session dies with the session.

Create `.claude/sessions/TEMPLATE.md`:

```markdown
# <date> - <one-line topic>

## What we did
## Key decisions
## Files changed
## Gotchas hit
## Next steps
```

Make sure `.claude/decisions/` and `.claude/sessions/` both exist, so the commands that write into
them have somewhere to land.

**Do not recreate session or ADR commands per repo.** Check what already resolves before you name
anything in `CLAUDE.md`:

```sh
ls ~/.claude/commands/ 2>/dev/null
ls .claude/commands/ 2>/dev/null
```

Name a command in the maintenance block **only if it exists** in one of those, or is provided by an
installed plugin. A `CLAUDE.md` that tells the next agent to run `/adr` in a repo where `/adr`
resolves to nothing is a broken instruction that will be followed anyway.

If a memory MCP server is configured, prefer it and keep the files as the fallback. Say which is
authoritative.

## 5. Layer 5 - Human docs

**Problem it solves:** agent context and human documentation get written into the same files, and
then one of the two audiences is always being served badly.

Keep the surfaces distinct, and say so in `CLAUDE.md`:

- `.claude/*.md` — terse, agent-facing, not published.
- `./docs` — full human documentation, published.

Scaffold only, and never clobber an existing page: `./docs/index.md`, `./docs/architecture.md`,
`./docs/setup.md`, and a `mkdocs.yml` using the Material theme, with a nav listing those pages and
`markdown_extensions: admonition, pymdownx.superfences, toc: {permalink: true}`.

**Stop there.** Filling those pages is the `docs-update` workflow's job, and it does it against a
30-surface sweep this workflow has no business duplicating. Scaffold the skeleton, then say in the
report that `docs-update` is the next run.

Add `mkdocs serve` and `mkdocs build` to `QUICK_START.md` (dependency: `mkdocs-material`), and add
`site/` to `.gitignore`.

If the repo already has a docs system — Docusaurus, Sphinx, a wiki, anything — use it. Do not
introduce a second one.

## 6. The maintenance block

The stack decays without this, and a decayed stack is the failure mode from the top of this file.
Add verbatim to `CLAUDE.md`, adjusted so every command named actually resolves (section 4):

```text
[maintenance]
- Bug that took more than an hour: append it to .claude/COMMON_MISTAKES.md.
- Architectural decision: write it to .claude/decisions/ (run /adr if installed).
- Public behaviour, API, config or setup changed: sync ./docs (run /claude-skills:docs-update).
- PROJECT_INDEX.json stale after a new module or a big refactor: regenerate the affected modules
  section only, and update "generated".
- Keep CLAUDE.md under ~500 tokens. Push detail into on-demand .claude/ files.
```

## 7. Verify

Run every check, report pass or fail with the real output, and fix the failures before you finish.
Never report a check you did not run.

**1. The auto-loaded tier is actually small.** Measure `CLAUDE.md` plus its `@`-imports:

```sh
FILES="CLAUDE.md"
NEXT="$(grep -ohE '@[^[:space:]]+\.md' CLAUDE.md 2>/dev/null | sed 's/^@//')"
DEPTH=0
while [ -n "$NEXT" ] && [ "$DEPTH" -lt 5 ]; do
  FILES="$FILES $NEXT"
  NEXT="$(grep -ohE '@[^[:space:]]+\.md' $NEXT 2>/dev/null | sed 's/^@//')"
  DEPTH=$((DEPTH + 1))
done
wc -w $FILES
```

Words × ~1.3 is a rough token estimate for English prose, not a measurement; treat it as a
tripwire. Target under ~1,000 tokens for the total. Over budget means moving detail into on-demand
files, not deleting it. In an interactive Claude Code session, `/context` gives the real number.

**2. The index is true.** Re-run the missing-paths check from section 1. Zero missing paths, every
major module present, hotspots derived from `git log` and not from guesswork.

**3. Access control is real and not self-defeating.** `.gitignore` covers what the build generates;
`settings.json` denies secrets; `settings.local.json` is gitignored; no `.claudeignore` exists; no
deny rule blocks a command the repo's own test or build path needs.

**4. Memory has somewhere to land.** `.claude/sessions/TEMPLATE.md`, `.claude/decisions/` and
`.claude/sessions/` exist, and every command named in `[maintenance]` resolves.

**5. Docs build.** `./docs` and `mkdocs.yml` exist, `site/` is gitignored, and `mkdocs build`
succeeds. If MkDocs is not installed, report the exact missing dependency and its install command
rather than adding it to the repo.

**6. The commands are the repo's real commands.** Run the read-only ones from `QUICK_START.md`
(`--help`, `--version`, a lint in check mode) and confirm they exist. Never run anything that
mutates state, deploys, or spends money to verify a doc line.

## 8. Report back

- **Files created and files modified**, one line each.
- **What moved out of an existing `CLAUDE.md`, and where it went.** Line by line. This is the part
  the user will check hardest, and rightly.
- **The token budget**: measured words, estimated tokens, against the ~1,000 target, per file.
- **Every verification check** with its real result. Quote failures, don't summarise them.
- **What you deliberately left out**, and why: layers already covered by existing tooling, commands
  you could not find, an MCP server that supersedes a layer.
- **The next run**: usually `docs-update`, to fill the docs skeleton this workflow only scaffolded.

## How this goes wrong

The failure modes, in the order they actually show up:

- **The index that lies.** Written once, never regenerated, and by month three it names deleted
  modules. Agents trust it, because it is the file that told them to trust it. This is why the
  maintenance block is not optional and why `generated` is in the schema.
- **The `CLAUDE.md` that restates the repo.** Directory listings, the framework's own conventions,
  a paraphrase of `package.json`. All true, all discoverable in one command, all paid for on every
  session forever.
- **Optimising the measurable thing.** Token count is easy to measure; rediscovery cost is not.
  Cutting `COMMON_MISTAKES.md` shows up as a win in the only number you can see, and as a loss
  everywhere you cannot.
- **The scar tissue deleted in a tidy-up.** An odd-looking rule in an existing `CLAUDE.md` is
  usually an incident someone had to live through. Move it, don't drop it.
- **`@`-importing the index.** Undoes the entire point of Layer 1 in one character.
- **A `.claudeignore` that does nothing**, or a deny list so aggressive the agent cannot run the
  test suite. Both look like security and are neither.
- **Two files of record.** `CLAUDE.md` and `AGENTS.md` drifting apart until the agents disagree.
- **Docs written twice.** This workflow scaffolding pages that `docs-update` then rewrites, or
  worse, refuses to touch because they look hand-written.

## Definition of done

- Five layers present or explicitly and justifiably skipped, each one reported.
- Auto-loaded tier measured and under budget, with the measurement shown.
- `PROJECT_INDEX.json` names every major module, every path in it resolves, and it is loaded on
  demand rather than imported.
- Every existing rule from a prior `CLAUDE.md` still exists somewhere, with the mapping reported.
- Every command written into a file was read out of this repo in this run.
- No `.claudeignore`, no secrets in any file created, no dependency added to the repo.
- Every verification check run, with its real output in the report.
- Working tree dirty, nothing committed, nothing pushed.
