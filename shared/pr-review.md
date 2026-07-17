# PR review workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

You are performing a **thorough code review** of a pull request — someone else's or
your own — and landing it as **one consolidated GitHub review**: inline comments
anchored to the exact `file:line`, a summary body, and a verdict. The end state is a
single, high-signal review the author can act on (ideally by running
`/address-pr-comments`) — not a wall of nitpicks and not a vague "looks good".

## Voice: write like a human

These rules are binding on every review body, every inline comment, and every prose
summary. The review should read as if a senior engineer wrote it, not a model.

- Use contractions: "don't", "it's", "there's", "you'll".
- Vary sentence rhythm. Mix short, blunt sentences with longer ones. Don't march through
  identical sentence shapes.
- **Never use an em-dash or an en-dash ("—", "–") in review text.** This is the biggest
  tell. Use a comma, a colon, parentheses, or just a period and a new sentence instead.
  (Rewrite "the code is clean — but the test is missing" as "the code is clean, but the
  test is missing" or "The code is clean. The test is missing.")
- Ban these AI-tell phrases outright: "it's worth noting", "in summary", "delve",
  "leverage", "utilize" (write "use"), "let's explore", "furthermore", "additionally",
  "moreover", "it's important to note", "seamlessly", "elevate", "unpack", "meticulously",
  and "robust" / "comprehensive" used as filler.
- No sycophantic openers ("Great work!", "Excellent PR!") and no hedging filler ("perhaps
  you might want to consider"). Say the thing directly. And no severity-undercutting hedges:
  on a ⛔ or 🟡, don't call the problem "practically safe for now", "probably fine", or "only
  theoretical" — name the concrete failure mode and the fix. If the honest read is that
  nothing actually needs to change, it's a 💬 nit, not a 🟡 (see the severity-honesty rule
  in section 3).
- Skip decorative headings when a short paragraph does the job. Cut trailing boilerplate
  like "Let me know if you have any questions".
- Substance beats style. Never drop a specific `file:line` finding or a concrete fix just
  to sound casual. Precision first, voice second.

Write the section headers and structure the review as the steps below describe, but keep
the prose inside them in this voice.

**Run fully autonomously — do not ask the user anything.** No clarifying questions, no
"would you like me to…", no stopping for approval. When intent is ambiguous, make the
best-judgment read of what the PR is trying to do (from its title, body, linked issues,
and the diff itself), review against that, and state any assumption in the review body.
The only thing that ends the run is posting the review or a hard external blocker you
cannot work around (e.g. the PR doesn't exist, or the API refuses the review) — and even
then you report it, you don't ask.

**Post exactly ONE review per run — and never a second one.** Gather everything, form every
finding, then submit a single review that carries all the inline comments and the summary
together. Do **not** dribble out one comment per API call (that spams the author with
notifications). The submit in step 5 is a **one-shot**: once that `POST .../reviews` returns
an `id`, you are **DONE** — do **not** call the reviews endpoint again for any reason (not to
"double-check", not to re-post, not a follow-up). The only exception is the explicit `422`
retry in step 5, which replaces a *rejected* POST (no review was created), never adds a
second one. Before posting, check whether you've already left a review on the current head
commit — if an equivalent one exists, don't duplicate it; report that instead (see step 6).

**Verdict policy.** Pick exactly one `event`:
- Not your own PR, **no** blocking (`⛔`) findings and **no** should-fix (`🟡`) findings →
  **`APPROVE`**. Approve only when the change is genuinely clean.
- Any **blocking** (`⛔`) finding → **`REQUEST_CHANGES`**.
- Otherwise (should-fixes present but nothing blocking) → **`COMMENT`**.

A lone should-fix means `COMMENT`, not `APPROVE`; when in doubt, `COMMENT`. (A downstream
gate may key a required status check off this verdict, so it must reflect real mergeability.)

**Your own PR is a special case.** GitHub does not let you approve *or* request changes on
a PR you authored — only `COMMENT` is accepted. So when the PR author is you, always submit
as `COMMENT`, and surface any blocking findings under a **`### ⛔ Blocking`** heading in the
body so they're impossible to miss.

**Signal over noise.** Spend your attention on correctness, security, contract drift, this
repo's `CLAUDE.md` hard rules, and missing tests. Don't comment on things a formatter/linter
already enforces (spacing, import order, quote style) — those are Ruff/Prettier's job, not a
review comment's. Every inline comment must be specific and, where the fix is small and
obvious, carry a one-click `​```suggestion`​` block. Praise is fine but keep it to one line in
the summary; don't leave "nice!" inline comments.

**Presentation.** The review reads as a code review, not as tool output. The body follows
the step-5 template exactly — it starts at `## Review summary`, with no robot emojis, no
"AI review" branding, and **never any attribution footer** ("Generated with …",
"Reviewed by …", co-author tags). The only emoji are the severity markers (⛔ / 🟡 / 💬).

Target PR: the PR input supplied by the invoking agent (if empty, use the PR for the current branch).

---

## 0. Resolve the PR and repo coordinates

```bash
# PR number: explicit arg, else the PR for the current branch
gh pr view "$ARGUMENTS" --json number,headRefName,headRefOid,baseRefName,author,url,isDraft 2>/dev/null \
  || gh pr view --json number,headRefName,headRefOid,baseRefName,author,url,isDraft
```

Capture `OWNER`, `REPO`, `PR` (number), `HEAD` (head branch), `HEAD_SHA`
(`headRefOid` — the commit you'll pin the review to), `BASE` (`baseRefName`), and
`AUTHOR` (`author.login`). Get owner/repo robustly:

```bash
gh repo view --json owner,name -q '.owner.login + " " + .name'
```

**Detect whether this is your own PR** — it changes the allowed verdict (see the policy
above):

```bash
VIEWER=$(gh api user -q .login)
# own PR  ⇔  "$VIEWER" == "$AUTHOR"   → verdict is forced to COMMENT later
```

This repo may live on **github.com** or **pinkroccade.ghe.com**; `gh` auto-selects the
right host from the remote, so the commands below work as-is.

You do **not** need to check out the branch — review reads the diff and the tree through
`gh`/`git`, it doesn't modify code. If you want to read full files for context beyond the
diff, `git fetch origin "$HEAD"` first so `origin/$HEAD` is local, then read at that ref.
(Checking out is optional and only worth it for a very large PR you want to navigate
locally; if you do, don't leave the user's working tree dirty.)

---

## 1. Gather everything you need to review

A good review reads the change **and its intent**, then checks the change against that
intent and against the repo's rules. Pull all of it before forming opinions.

**a) The change itself — the diff.** The per-file `patch` is also what tells you which
lines are inline-commentable (step 4), so prefer the API form:

```bash
gh pr diff "$PR"                                   # full unified diff, quick read
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate \
  -q '.[] | {path:.filename, status, additions, deletions, patch}'
```

**b) Intent — what the PR claims to do, and what it's linked to:**

```bash
gh pr view "$PR" --json title,body,additions,deletions,changedFiles,labels,closingIssuesReferences \
  -q '{title, body, additions, deletions, changedFiles, labels:[.labels[].name], closes:[.closingIssuesReferences[].number]}'
```

Read the body and any linked issue so you review against the *stated* goal — a change can
be locally clean but wrong for what it was supposed to do.

**c) Existing feedback — so you don't repeat what's already been said.** Reviewing is
additive; if another reviewer (or a bot) already flagged something, don't re-flag it.

```bash
# inline review threads (humans, Copilot, code-quality bots) + resolution state
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviews(first:50) { nodes { author { login } state submittedAt } }
      reviewThreads(first:100) {
        nodes { isResolved path line comments(first:20){ nodes { author{login} body } } }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR"

# top-level conversation comments (many bots post here)
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate -q '.[] | {user:.user.login, body}'
```

**d) CI / checks — context for your verdict** (a red required check is itself a reason not
to approve, and may point you at what to scrutinize):

```bash
gh pr checks "$PR" || true
```

**e) GHAS code-scanning alerts on this branch** (CodeQL/secret findings; ignore 403/404 if
GHAS isn't enabled) — fold any open ones into your review as security findings:

```bash
gh api "repos/$OWNER/$REPO/code-scanning/alerts?ref=refs/heads/$HEAD&state=open" --paginate \
  -q '.[] | {rule:.rule.id, severity:.rule.severity, path:.most_recent_instance.location.path, line:.most_recent_instance.location.start_line, message:.most_recent_instance.message.text}' \
  2>/dev/null || echo "no code-scanning access / none open"
```

For anything in the diff whose surrounding context you can't judge from the patch alone
(does this break a caller? is there already a helper for this?), **read the actual files**
with Read/Grep/Glob. The diff shows what changed; the repo tells you whether it's correct.

---

## 2. What to review — dimensions, in priority order

Work top-down; a blocker in an earlier dimension matters more than a polish note in a later
one. For each finding, note: `file:line`, severity (step 3), what's wrong, and the concrete
fix.

1. **Correctness & logic** — off-by-ones, null/None handling, wrong conditionals, unhandled
   error paths, race conditions, resource leaks (unclosed sessions/handles), broken caller
   contracts. Does the code do what the PR says it does?
2. **Security** — injection (SQL/shell/template), authn/authz gaps, secrets or tokens in
   code, unsafe deserialization, missing input validation at trust boundaries, SSRF/path
   traversal, dependency with a known CVE. Treat every GHAS alert from step 1e as a finding.
3. **This repo's `CLAUDE.md` hard rules — these are blockers when violated** (see step 2a).
4. **Contract integrity** — any request/response shape must be defined once in
   `packages/schemas` and consumed from there. Flag a shape redefined inside an app, or a
   **zod ↔ Pydantic mismatch** (the two halves of the contract drifting apart).
5. **Tests** — does new behavior come with tests (pytest / Vitest / Playwright as fits the
   layer)? Are bug-fixes accompanied by a regression test? Are critical edge cases covered?
   Missing tests for non-trivial new logic is at least a *should-fix*.
6. **API & data design** — migration present and reversible for every model change (Alembic),
   sensible status codes, pagination/filtering where lists can grow, backward-compatible
   changes to shared shapes.
7. **Performance** — N+1 queries, unbounded fetches, work inside hot loops, missing
   indexes for new query patterns, needless re-renders / unmemoized expensive work on the
   client.
8. **Readability & maintainability** — naming, dead code, duplicated logic that wants a
   helper, comments that explain *why*. Keep these to genuinely useful notes; don't pad the
   review.

### 2a. Repo-specific rule checks (grep the diff for these — each is a blocker)

This stack has non-negotiable conventions from `CLAUDE.md`. A PR that breaks one should be
`REQUEST_CHANGES`:

- **SQLAlchemy 2.0 only** — flag any legacy `session.query(...)`; it must be `select()` +
  `session.execute()`.
- **Async psycopg 3 on the backend** — the API runs on an async psycopg 3 session
  (`create_async_engine` + `AsyncSession`). Flag a synchronous `Session` / `create_engine`,
  a missing `await` on `session.execute(...)` inside an async route (a blocking DB call in
  an async path is a correctness bug, not just a style nit), or a connection string that
  isn't `postgresql+psycopg://…` (e.g. a bare `postgresql://` or a `+psycopg2` driver).
- **Pydantic v2 only** — flag v1's `@validator` or inner `class Config`; must be
  `@field_validator` / `model_config`.
- **uv only for Python deps** — flag a new `requirements.txt`, or pip/poetry usage.
- **Ruff only** — flag any newly-added Black, Flake8, or isort config/dep.
- **pnpm only** — flag a `package-lock.json` / `yarn.lock` or npm/yarn invocations.
- **Turborepo orchestration** — flag a `Makefile`/`justfile` added as the task *orchestrator*
  (a thin one that only shells out to `turbo` as a human catalog is fine).
- **Version pinning** — dependency declarations must pin **exact** versions: the
  `dependencies` / `devDependencies` / `optionalDependencies` of `package.json` and the
  `[project]` dependencies / `[dependency-groups]` of `pyproject.toml`. Flag a
  newly-introduced `^`/`~`/range *there*. Do **not** flag ranges in `peerDependencies`,
  `engines`, `volta`, or `packageManager` — those are meant to be ranges. Node + Python
  versions themselves belong in `mise.toml`.
- **Web UI ≠ mobile UI** — shadcn/DOM components must not be imported into `apps/mobile`,
  and visual components must not be shared across web/mobile. Sharing types / schemas /
  api-client / query hooks is correct; sharing a rendered component is not.
- **Client-agnostic backend** — flag any per-client fork of the API (a web-only vs
  mobile-only endpoint doing the same thing).
- **New dependency not in the approved `CLAUDE.md` list** — flag it; the rule is "ask before
  adding any dependency not listed". Call it out so the human can approve or reject.

---

## 3. Severity → verdict

Tag every finding with one of:

- **⛔ Blocking** — a failure the reader can hit now, on this diff: a correctness/security
  bug, a `CLAUDE.md` hard-rule violation, contract drift, or a missing migration. Litmus:
  someone hits this with the code as merged. Any one → `REQUEST_CHANGES`.
- **🟡 Should-fix** — not merge-blocking, but a real gap the author should close: EITHER a
  concrete failure still reachable in the code as it stands (point to the input or path that
  hits it today), OR missing tests for non-trivial new logic, OR a likely-but-unconfirmed
  perf issue. A fragile or defensive pattern counts ONLY if that fragility is reachable now;
  if the existing code already prevents the failure and the point is future-proofing ("if
  someone removes X later", "if a new caller feeds this"), it's a 💬 nit, not a 🟡. On their
  own, should-fixes → `COMMENT`.
- **💬 Nit / optional** — nothing breaks if the author ignores it: style, readability, or
  defensive hardening they can take or leave. Litmus: nothing breaks if they skip it. Prefix
  the inline comment with `nit:`. Never block on a nit.

**Severity honesty.** The label and the prose must agree. If your text for a 🟡 says the
current code makes the failure "practically safe", "probably fine", or "only theoretical",
and the only failure you can name is hypothetical ("if someone removes X later"), it's a 💬
nit — relabel it. (Missing coverage for non-trivial logic stays a 🟡 even though nothing
"fails today".) Keep a true mitigation note if it's real; just don't label take-it-or-leave-it
hardening as a should-fix. If relabeling leaves no ⛔ and no 🟡, the verdict is `APPROVE` per
the policy above — that's the honest call for a mergeable PR, so don't inflate a nit to avoid
it. A 🟡 must name either a failure reachable today or missing coverage for non-trivial logic.

**Verdict** (from the policy at the top):
- own PR → **`COMMENT`** always (blockers go under `### ⛔ Blocking` in the body).
- not own PR, ≥1 **⛔ blocking** finding → **`REQUEST_CHANGES`**.
- not own PR, ≥1 **🟡 should-fix** but no blocking → **`COMMENT`**.
- not own PR, no ⛔ and no 🟡 findings (clean) → **`APPROVE`**.

---

## 4. Anchor each finding to the diff (line rules)

Inline comments only stick on lines GitHub considers part of the diff. Get this right or the
whole review POST fails (422). The per-file `patch` from step 1a is your source of truth —
read its hunk headers `@@ -old,+new @@` and classify each line:

- **Added (`+`) or unchanged context line** → comment on its **new** line number with
  `"side": "RIGHT"`.
- **Removed (`-`) line** → comment on its **old** line number with `"side": "LEFT"`.
- **Multi-line span** → include `"start_line"` + `"start_side"` **and** `"line"` + `"side"`,
  with `start_line` ≤ `line`, both on lines inside the diff.
- **A line that is NOT in any hunk** (untouched code, a whole-file or architectural concern,
  or a "this should have changed too but didn't" point) **cannot take an inline comment** —
  put it in the review **body** instead, citing `path:line` in prose so it's still precise.

**A concrete fix belongs on a diff line, not in the body.** Before concluding a finding is
body-only, check whether it's actually about a line inside a hunk. If a finding is about any
in-diff line (added, removed, or an adjacent line it interacts with), make it an INLINE
comment on the nearest in-diff line it's actually about, and carry a `suggestion` when the
fix target is itself an in-diff line and the change is small. Re-anchor when the line you
first named sits just outside the diff: a guard finding might name the `if` on line 500 (one
above the hunk) while the `.slice(0, 10)` it's really about sits on the added line 504, so the
comment rides 504 and spells out the fix. If the exact line to change is out of diff, a
one-click `suggestion` can't apply to it: say so and give the exact replacement to paste. The
body is only for findings with NO anchorable line: a whole-file or architectural concern, a
cross-file test-coverage gap, or a "this should have changed too but didn't" point. Every
anchorable finding goes inline, and a should-fix in particular must never be demoted to the
body while a lower-severity nit rides inline.

When the fix is small and unambiguous, make the inline comment a GitHub suggestion so the
author can apply it in one click:

````
This drops the session without closing it on the error path.

```suggestion
        async with session.begin():
            result = await session.execute(select(Item))
```
````

### Suggestion safety — a broken suggestion is worse than no suggestion

GitHub applies a suggestion by replacing EXACTLY the commented line range with the block.
Three hard rules keep one-click Apply from committing broken code:

1. **Span the whole syntactic unit.** If your replacement touches any part of a
   multi-line statement (a `re.compile(` call, a function signature, a dict literal, a
   YAML mapping), the comment MUST be a multi-line comment anchored from the statement's
   first line to its last (`start_line`..`line`), and the suggestion must contain the
   complete replacement statement. Anchoring to just the opening line while the old
   continuation lines remain below is how you commit a syntax error on the author's
   behalf.
2. **Prove it applies cleanly before you post.** You are sitting in a full clone: apply
   the replacement to the file at exactly the lines you're anchoring, then check the file
   still parses (`python3 -m py_compile <file>`, `bash -n`, `node --check`, `ruby -c`, or
   the obvious parser for the file type; a quick `python3 -c "import yaml,sys;
   yaml.safe_load(open(sys.argv[1]))" <file>` for YAML). Revert with
   `git checkout -- <file>` afterwards. If you can't make it parse as a suggestion,
   post the idea as a plain fenced snippet instead and say the author should fold it in
   by hand.
3. **Give the Apply box a real commit title.** GitHub pre-fills the Apply-suggestion
   commit as "Update <file>", and reviewers can't change that default. So under every
   suggestion block, add one line the author can paste into the commit-title box, in
   Conventional Commits form:

   `Commit title for the Apply box: fix(reconcile): match port-qualified registries`

---

## 5. Assemble and submit ONE review

Build the whole review as a single JSON payload, then POST it once. Getting Markdown
(suggestion blocks, multi-line bodies) into JSON by hand is where escaping bugs creep in, so
let the payload builder assemble and validate the JSON rather than hand-escaping newlines.

Follow the "Voice: write like a human" rules from the top of this file in the `body` and in
every comment `body`. No em-dashes anywhere in the review text.

**a) Locate the payload builder.** Use the first of these paths that exists as
`$PAYLOAD_BUILDER` (same resolution order as the rubric itself):

1. `${CLAUDE_PLUGIN_ROOT}/scripts/build-review-payload.py` — installed as a plugin
2. `.claude/scripts/build-review-payload.py` — headless runs (Nievah installs it into the PR clone)
3. `scripts/build-review-payload.py` — working inside the agent-skills checkout

If none exists (e.g. a headless clone without `scripts/`) or `python3` isn't available, skip
to the **Fallback** below.

**b) Write the review body** to `.git/review-body.md` as plain Markdown with **real
newlines** (never the two literal characters `\n`). It starts at `## Review summary`:

```markdown
## Review summary

<2–4 sentences: what the PR does and your overall read.>

**Bottom line:** <ONE required sentence stating mergeability and the single next action,
keyed to your highest-severity finding (NOT the API event — an own PR is forced to `COMMENT`
even with a blocker). No ⛔/🟡 → say so plainly, e.g. "Nothing here blocks merge, nothing to
fix". 🟡 only → name the top should-fix as worth doing before it lands, without implying it
blocks merge. Any ⛔ → "blocks merge" and name it. Point at inline fixes rather than restating
them, e.g. "tighten the regex at `ReportPageLayout.tsx:500` (inline)". No em-dash, no
checklist — the sections and inline comments carry the detail.>

### ⛔ Blocking
- `path:line`: <what & why> (only this section on your OWN PR; otherwise blockers ride REQUEST_CHANGES)

### 🟡 Should-fix
- `path:line`: <a should-fix with NO anchorable diff line, e.g. a cross-file test-coverage gap or a "this file should have changed too" point. If the fix lands on a diff line it's an inline comment carrying a suggestion (step 4), not a bullet here. At most restate an inline one in a single line so the body still reads as a complete summary.>

### 💬 Notes
- <whole-file / architectural / not-in-diff points that couldn't be inline>

_One line of genuine praise, if warranted._
```

**c) Write the inline comments** to `.git/review-comments.json` as a JSON array. Each entry
carries its anchor from step 4 (`path` + `line`/`side`, or `start_line`/`start_side` +
`line`/`side`) plus the comment text. Put short text inline as `"body"`; when it carries a
suggestion block or spans multiple lines, point `"body_file"` at a Markdown file (path
relative to this JSON file, so keep it in `.git/`) and never escape it:

```json
[
  { "path": "apps/api/server/routes/items.py", "line": 42, "side": "RIGHT", "body": "⛔ <finding>" },
  { "path": "packages/schemas/src/item.ts", "start_line": 10, "start_side": "RIGHT", "line": 14, "side": "RIGHT", "body_file": "review-comment-1.md" }
]
```

Use `[]` (or omit `--comments-file`) when there are no inline comments.

**d) Build and validate the payload.** The builder folds each `body_file` into its comment,
sets `event`, and rejects empty bodies or literal `\n` before you ever hit the API:

```bash
python3 "$PAYLOAD_BUILDER" build \
  --commit-id "$HEAD_SHA" \
  --event COMMENT \
  --body-file .git/review-body.md \
  --comments-file .git/review-comments.json \
  --output .git/review-pr.json
```

Set `--event` per step 3: own PR → `COMMENT`; not own + any ⛔ → `REQUEST_CHANGES`; not own +
only 🟡 → `COMMENT`; not own + clean → `APPROVE`. If there are **no findings at all**, still
write a body (the PR looks clean to you, plus any review-depth caveats) and use `APPROVE`
(or `COMMENT` on your own PR).

**Fallback (no builder found, or no `python3`).** Write the whole payload JSON straight to
`.git/review-pr.json` with the **Write** tool — real newlines inside the strings, since the
Write tool doesn't go through the shell:

```json
{
  "commit_id": "<HEAD_SHA>",
  "event": "COMMENT",
  "body": "## Review summary\n\n<2–4 sentences>\n\n### 🟡 Should-fix\n- `path:line`: <…>\n\n_One line of genuine praise, if warranted._",
  "comments": [
    { "path": "apps/api/server/routes/items.py", "line": 42, "side": "RIGHT", "body": "⛔ <finding>" },
    { "path": "packages/schemas/src/item.ts", "start_line": 10, "start_side": "RIGHT", "line": 14, "side": "RIGHT", "body": "🟡 <finding>" }
  ]
}
```

Set `event` (`APPROVE` / `REQUEST_CHANGES` / `COMMENT`) by the same rule as step d. If the
builder is present you can still sanity-check a hand-written payload with
`python3 "$PAYLOAD_BUILDER" check .git/review-pr.json`.

**e) Submit (single call):**

```bash
gh api --method POST "repos/$OWNER/$REPO/pulls/$PR/reviews" \
  --input .git/review-pr.json \
  -q '"posted review " + (.id|tostring) + " — " + .state'
```

**If it returns 422** — do **not** blindly re-POST. A 422 does not always mean "nothing was
created": GitHub can persist the review and *still* return a 422, so a naive retry double-posts
(the observed bug). **Before touching the review again, re-list the PR's reviews and check
whether one of yours already landed on the current `HEAD_SHA`:**

```bash
VIEWER=$(gh api user -q .login)   # the app/user this run posts as
gh api "repos/$OWNER/$REPO/pulls/$PR/reviews" --paginate \
  -q "[ .[] | select(.user.login == \"$VIEWER\" and .commit_id == \"$HEAD_SHA\") ] | length"
```

- **If that count is ≥ 1, a review by this app already exists on this HEAD_SHA — do NOT
  re-POST.** The submission succeeded despite the 422. Report that (and the review id/state)
  and **stop** — this is what preserves the "post exactly ONE review per run" and HEAD_SHA
  idempotency guarantees.
- **Only if no such review exists** was the POST a genuine failure. Then recover the feedback:
  a 422 is almost always a bad inline anchor (a line not in the diff). Identify the offending
  comment from the error, move that finding into the body as a `path:line` bullet, drop it from
  `comments`, and re-POST **once**. If you can't pin the bad one quickly, fall back to a
  **body-only** review that carries every finding as `path:line` bullets, post that once, and
  note in the report that inline anchoring fell back to the summary. After any re-POST,
  re-run the check above before ever posting again.

**Clean up** the scratch files afterward: `rm -f .git/review-pr.json .git/review-body.md .git/review-comments.json .git/review-comment-*.md`.

---

## 6. Report back

Be idempotent about it: if step 1c showed you **already** posted a review on this same
`HEAD_SHA` with the same findings, don't post a duplicate — say so and stop.

Otherwise, end with a concise summary:

- **Verdict** submitted (`REQUEST_CHANGES` / `COMMENT`) and **why** — and, if this was your
  own PR, the note that GitHub forced `COMMENT` so any blockers live in the body.
- A short table: **severity → file:line → finding → suggested fix**.
- Anything you reviewed shallowly and why (e.g. a very large generated file, a lockfile) so
  coverage isn't overstated — **no silent truncation**.
- Any assumption you made about intent, and any finding that turned on a judgment call, so
  the author can weigh it.
- The PR URL and the one remaining human action ("address the comments — `/address-pr-comments`
  will do it — then re-review and merge").
