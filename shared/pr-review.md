# PR review workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

You are performing a **thorough code review** of a pull request — someone else's or
your own — and landing it as **one consolidated GitHub review**: inline comments
anchored to the exact `file:line`, a summary body, and a verdict. The end state is a
single, high-signal review the author can act on (ideally by running
`/address-pr-comments`) — not a wall of nitpicks and not a vague "looks good".

**Run fully autonomously — do not ask the user anything.** No clarifying questions, no
"would you like me to…", no stopping for approval. When intent is ambiguous, make the
best-judgment read of what the PR is trying to do (from its title, body, linked issues,
and the diff itself), review against that, and state any assumption in the review body.
The only thing that ends the run is posting the review or a hard external blocker you
cannot work around (e.g. the PR doesn't exist, or the API refuses the review) — and even
then you report it, you don't ask.

**Post exactly ONE review per run.** Gather everything, form every finding, then submit a
single review that carries all the inline comments and the summary together. Do **not**
dribble out one comment per API call (that spams the author with notifications). Before
posting, check whether you've already left a review on the current head commit — if an
equivalent one exists, don't duplicate it; report that instead (see step 6).

**Verdict policy — the review CAN approve a clean PR.**
- Not your own PR **and** zero **⛔ blocking** findings **and** zero **🟡 should-fix**
  findings → submit as `APPROVE`.
- Any **⛔ blocking** finding present → submit as `REQUEST_CHANGES`.
- Otherwise (should-fixes but no blockers) → submit as `COMMENT`.
- **Own-PR guard:** GitHub rejects `APPROVE` *and* `REQUEST_CHANGES` on a PR you authored, so
  on your own PR always force `COMMENT` (see below).

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

- **⛔ Blocking** — correctness/security bug, a `CLAUDE.md` hard-rule violation, contract
  drift, or a missing migration. Any one of these makes the verdict `REQUEST_CHANGES`.
- **🟡 Should-fix** — real problem but not merge-blocking on its own (missing test for
  non-trivial logic, a likely-but-unconfirmed perf issue, a fragile pattern). On their own,
  should-fixes → `COMMENT`.
- **💬 Nit / optional** — style/readability suggestion the author can take or leave. Prefix
  the inline comment with `nit:` so the author knows it's optional. Never block on a nit.

**Verdict** (from the policy at the top):
- own PR → **`COMMENT`** always (blockers go under `### ⛔ Blocking` in the body).
- not own PR, ≥1 ⛔ blocking finding → **`REQUEST_CHANGES`**.
- not own PR, no ⛔ blocking but ≥1 🟡 should-fix → **`COMMENT`**.
- not own PR, zero ⛔ blocking **and** zero 🟡 should-fix → **`APPROVE`**.

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

When the fix is small and unambiguous, make the inline comment a GitHub suggestion so the
author can apply it in one click:

````
This drops the session without closing it on the error path.

```suggestion
        async with session.begin():
            result = await session.execute(select(Item))
```
````

---

## 5. Assemble and submit ONE review

Build the whole review as a single JSON payload, then POST it once. Use the **Write** tool
to create the payload file (avoids shell-quoting hell), then submit with `gh api --input`.

**Payload** — write to `.git/review-pr.json` (inside the repo, ignored by git):

```json
{
  "commit_id": "<HEAD_SHA>",
  "event": "COMMENT",
  "body": "## Review summary\n\n<2–4 sentences: what the PR does, your overall read, and the verdict in words>\n\n### ⛔ Blocking\n- `path:line` — <what & why> (only this section on your OWN PR; otherwise blockers ride REQUEST_CHANGES)\n\n### 🟡 Should-fix\n- `path:line` — <…>\n\n### 💬 Notes\n- <whole-file / architectural / not-in-diff points that couldn't be inline>\n\n_One line of genuine praise, if warranted._",
  "comments": [
    { "path": "apps/api/server/routes/items.py", "line": 42, "side": "RIGHT", "body": "⛔ <finding + optional ```suggestion block>" },
    { "path": "packages/schemas/src/item.ts", "start_line": 10, "start_side": "RIGHT", "line": 14, "side": "RIGHT", "body": "🟡 <finding>" }
  ]
}
```

Set `event` per step 3:
- own PR → `"COMMENT"` (GitHub rejects `APPROVE`/`REQUEST_CHANGES` on your own PR).
- not own PR + any ⛔ blocking → `"REQUEST_CHANGES"`.
- not own PR + no ⛔ blocking but ≥1 🟡 should-fix → `"COMMENT"`.
- not own PR + zero ⛔ blocking and zero 🟡 should-fix → `"APPROVE"`.

If there are **no findings at all** and it isn't your own PR, submit an `APPROVE` review whose
body says the PR looks clean to you (noting any review-depth caveats). On your **own** clean
PR, GitHub forbids `APPROVE`, so post a `COMMENT` review that says the same and leaves the
approve/merge click to a human.

**Submit (single call):**

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

**Clean up** the payload file afterward: `rm -f .git/review-pr.json`.

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
