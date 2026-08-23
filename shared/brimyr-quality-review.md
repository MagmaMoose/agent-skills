# Brimyr quality review workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

You run **after Brimyr has finished**. Brimyr is **quality assurance**, and it gates on two
things now, not one:

1. **Patch coverage** — the fraction of the lines this PR changed that the test suite executed,
   failing below the threshold (80% by default). It never gates on pre-existing uncovered code,
   and it doesn't gate at all on a diff below `min_lines` (20 by default).
2. **Net-new quality findings** — optional (`quality: 'true'`, off by default) and
   **report-only out of the box**. It doesn't vendor or re-implement a linter: it calls
   `chargate filter-sarif` across a process boundary and gates on the counts that come back.
   `quality_fail_on` defaults to `none`, so on nearly every repo this half counts findings,
   prints them, and blocks on none of them.

Alongside both it runs `sonar-scanner` for the quality trend, non-blocking. Its action outputs
are `mode`, `gate_result` (`pass` | `fail` | `error`), `patch_coverage`, `covered_lines`,
`total_lines`, `total_coverage`, `quality_gate_result`, `quality_net_new_count`,
`quality_blocking_count`, and `quality_fail_on`. The last five are recent; a repo pinned to an
older tag emits only the first five, which is one of the ways you can end up with no quality
half to read (§0e).

And it **posts a PR comment** when `pr_comment: 'true'`: one consolidated comment carrying both
halves, found and patched by its own hidden marker. That comment is your primary source (§0b).

So Brimyr hands you a percentage, a count, and a capped list. What it does not hand anybody is
a **judgement**, and both numbers are blind in the same direction.

**100% patch coverage means every changed line was executed. It does not mean a single one of
them was checked.** A test that calls the function and asserts nothing scores exactly the same
as a test that pins the contract. A test that mocks the dependency it exists to exercise scores
the same as one that would notice if that dependency were deleted. A test whose name promises
one behaviour and whose assertion enshrines the opposite scores the same as a correct one, and
it is worse than having no test at all, because it reads as a guarantee. Coverage is a
lower bound on effort and says nothing about a bound on risk.

**And the finding count is blind the same way, from the other side.** A table reading "14
net-new findings" above a green tick is not a statement that the fourteen are acceptable. It is
a statement that the threshold never fired and nobody read them. A green Brimyr routinely ships a list of
real, PR-scoped defects that no human and no gate has looked at (§4). Those two gaps, together,
are this workflow's entire subject matter.

The end state is **one** PR comment carrying the findings Brimyr could not have produced, plus
a machine-readable block `pr-triage` can act on. You post a comment. You do not submit a GitHub
review, you do not set a status check, and you do not push code. `pr-triage` fixes; you find.

**Run fully autonomously — do not ask the user anything.** No clarifying questions, no
"would you like me to…", no stopping for approval. When intent is ambiguous, make the
best-judgment read of what the PR is trying to do (title, body, linked issues, the diff) and
review against that, stating the assumption in the comment. The only thing that ends the run is
posting the comment or a hard external blocker you cannot work around, and even then you report
it, you don't ask.

**Post exactly ONE comment per run, and patch it on every later run.** The comment carries the
hidden marker `<!-- agent-skills:brimyr-quality-review -->`. Find the prior one and `PATCH` it;
only `POST` when none exists. This is the same find-or-patch discipline Chargate uses for its own
summary. Never dribble a second comment per run, and never leave two on a PR.

## Voice: write like a human

Binding on the comment body and on every finding inside it. It should read as a senior engineer's
quality review, not as tool output.

- Use contractions: "don't", "it's", "there's", "you'll".
- Vary sentence rhythm. Mix short, blunt sentences with longer ones.
- **Never use an em-dash or an en-dash ("—", "–") in the posted comment.** Use a comma, a colon,
  parentheses, or a full stop and a new sentence. Same rule `shared/pr-review.md` and
  `shared/chargate-security-review.md` apply to their review text, and it matters more here than
  in either: this comment lands on the same PR as Chargate's, and two comments from one system
  that punctuate differently read as two different authors. Note the scope — this governs text
  **posted to GitHub**, not this rubric. Em-dashes are fine in the repo's own files, including
  this one, so don't strip them from the prose you're reading.
- Ban these AI-tell phrases outright: "it's worth noting", "in summary", "delve", "leverage",
  "utilize" (write "use"), "let's explore", "furthermore", "additionally", "moreover", "it's
  important to note", "seamlessly", "elevate", "unpack", "meticulously", and "robust" /
  "comprehensive" used as filler.
- No sycophantic openers ("Great work!", "Excellent PR!") and no hedging filler ("perhaps you
  might want to consider"). Say the thing directly.
- No severity-undercutting hedges. On a ⛔ or 🟡, don't call the problem "probably fine" or "only
  theoretical" — name the concrete failure mode and the fix. If the honest read is that nothing
  needs to change, it's a 💬 nit.
- **No robot emojis, no "AI review" branding, and never an attribution footer** of any kind
  ("Generated with …", "Reviewed by …", co-author tags). The only emoji are the severity markers
  (⛔ / 🟡 / 💬).
- Substance beats style. Never drop a specific `file:line` finding to sound casual.

## The hardest rule in this repo, restated for a gate that reports more than it blocks

`shared/pr-triage.md` §2a says: never suppress a finding that is real, and a green gate bought
that way is worse than a red one. Brimyr's form of that rule has two halves, and both are yours:

1. **Never soften, downgrade, or drop a real finding because Brimyr came back green.** A passing
   percentage is not evidence about any finding you hold. If the tests are theatre, `pass` is the
   symptom, not the refutation. The quality half carries the same trap in a sharper form:
   `quality_fail_on` defaults to `none`, so its `pass` is not a verdict on the findings at all,
   it is a threshold that cannot fire. "Brimyr didn't block on it" is never an argument.
2. **Never propose a fix whose only effect is to move the percentage.** A red Brimyr invites the
   single worst remediation available: a test that calls the changed function and asserts nothing,
   written purely to touch the lines. That is dimension **1a** below, and if the PR under review
   already contains one, it is a finding, not a fix. When you recommend adding a test, say what it
   must **assert**, never just what it must call.

---

## 0. Coordinates, and Brimyr's own verdict

### a) Resolve the PR

```bash
# PR number: explicit arg, else the PR for the current branch
gh pr view "$ARGUMENTS" --json number,headRefName,headRefOid,baseRefName,author,url,isDraft 2>/dev/null \
  || gh pr view --json number,headRefName,headRefOid,baseRefName,author,url,isDraft

gh repo view --json owner,name -q '.owner.login + " " + .name'
```

Capture `OWNER`, `REPO`, `PR`, `HEAD` (head branch), `HEAD_SHA` (`headRefOid` — every finding you
report is pinned to this commit), `BASE`, and `AUTHOR`. This repo may live on **github.com** or
**pinkroccade.ghe.com**; `gh` picks the host from the remote, so the commands below work as-is.

You do **not** need a working tree to review — no `gh pr checkout`, no branch switch — except for
the executed mutation probe (§1, tier 2) and the local coverage fallback (§3c). But you **do** need
the head commit's objects present, because every read of a whole file below is
`git show "$HEAD_SHA:<path>"`, and that resolves the blob out of the local object store. Fetch it
first, once:

```bash
git fetch origin "$HEAD_SHA" 2>/dev/null || git fetch origin "$HEAD"
git cat-file -e "$HEAD_SHA^{commit}" && echo "head objects present"
```

**If that check fails, do not carry on as though it passed.** `git show` on a missing object exits
non-zero and writes nothing to stdout, so every pipeline below — the §1a detectors, the §2f
dependency reads, the §8 line verification — degrades to *empty output*, which is
indistinguishable from "found nothing". A silent false-clean is the one failure this whole review
exists to prevent, so read files over the API instead and say in the report that you did:

```bash
gh api "repos/$OWNER/$REPO/contents/<path>?ref=$HEAD_SHA" \
  -H 'Accept: application/vnd.github.raw'
```

That returns the file verbatim on stdout and is a drop-in replacement for `git show
"$HEAD_SHA:<path>"` in every snippet below. Fork PRs are the common case where you'll need it.

If you do check out, never leave the working tree dirty, never commit, never push.

### b) Read Brimyr's summary comment — the primary source, found by marker

**Start here, and prefer this over everything below it.** When the repo runs Brimyr with
`pr_comment: 'true'`, one consolidated comment carries both halves of the verdict, and it is
strictly richer than the check run: the check conclusion flattens two gates into one word, and
the per-level quality breakdown appears in no action output at all.

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | test("<!-- brimyr:(pr|quality)-summary -->"))
      | {id, url:.html_url, user:.user.login, updated:.updated_at, body}'
```

Two markers, and they are **not** interchangeable:

- `<!-- brimyr:pr-summary -->` is *the* comment. `brimyr ci` renders the coverage block and,
  when quality is on, appends the quality block into that same body. This is the one you want,
  and finding it means you need neither (c) nor (d).
- `<!-- brimyr:quality-summary -->` belongs to a standalone `brimyr lint` run, which owns a
  second comment under its own marker precisely so it can never overwrite the consolidated one.
  It is a supplement, not the normal path. Finding only this one does **not** mean the coverage
  half is missing; it means `ci` either didn't comment or hasn't run yet, so still do (c).

Match on the marker, never on the author. The comment is authored by `Brimyr[bot]` when the
token broker minted a token and by `github-actions[bot]` when it fell back to `GITHUB_TOKEN`,
so the login isn't stable and was never the identifier.

**An empty result is still routine, and it is still not an error.** `pr_comment` defaults to
`'false'`, so a repo that hasn't switched it on gates perfectly well and comments nothing; a
fork PR without a token is the same. Fall through to (c), then (d), and record in (e) which
source you actually used.

#### What to take out of the coverage block

```markdown
## Brimyr: Quality Assurance

**Mode:** `pr` · **Gate:** `pass` · **Ecosystem:** Python

| Metric | Value |
|--------|-------|
| Patch coverage | **91.4%** |
| Covered / changed executable lines | 128 / 140 |
| Total coverage (measured files) | 74.2% |
| Covered / executable lines across 96 file(s) | 3410 / 4595 |
| Threshold | 80.0% |

✅ Patch coverage 91.4% meets the 80.0% threshold.
```

The verdict line is one of `✅ … meets the … threshold.`, `❌ **Patch coverage … is below the …
threshold.** Uncovered changed lines:`, `✅ No changed executable lines to cover — vacuous
pass.`, `⚪ Only N changed executable line(s) — below the N-line minimum, so the … threshold was
**not applied**`, or `📋 Baseline run — total coverage only; no patch gate.`. A broken test run
replaces the whole table with `> ❌ **Broken test run** — the tests failed or produced no
coverage. This is a tool error (build red), **not** 0% patch coverage.`

Two traps live in that list, and both of them read as a pass:

1. **The uncovered-line list only appears when the gate FAILED.** A green comment names no
   uncovered lines at all. So a passing Brimyr tells you nothing about *which* lines it let
   through, and §3 (fetch the coverage report yourself) stays mandatory on a pass. That is
   precisely where §3's subject matter lives.
2. **`⚪ below the minimum` and `📋 Baseline run` both report `pass` while gating nothing.** A
   small PR is not a covered PR, and a baseline run measured no diff. If you see either line,
   the threshold was never applied and the percentage beside it is a measurement, not a verdict.
   Say which one it was in your comment rather than repeating "the gate passed".

The quality block, `## Brimyr: Net-new findings`, is parsed in §4 — that section owns it.

### c) Fallback 1 — the check run, when there's no comment

```bash
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" --paginate \
  -q '.check_runs[] | select(.name | test("brimyr|coverage"; "i"))
      | {name, status, conclusion, started:.started_at, url:.html_url,
         title:.output.title, summary:.output.summary}'
```

The conclusion (`success` / `failure` / `neutral`) maps onto `gate_result`, and `output.summary`
is where a job summary lands if the workflow writes one. Read it before going to the log.

**One conclusion, two gates.** Brimyr exits on the worst verdict of the pair, so a red check is
coverage *or* quality *or* both, and a green one only tells you neither exceeded its own
threshold — which, at the default `quality_fail_on: none`, the quality half cannot do. The
check run cannot separate them. If quality matters on this PR and there's no comment, go to (d).

### d) Fallback 2 — the action outputs in the workflow run

The outputs are consumed inside the workflow, so the REST API won't hand them to you as a field.
Read them off the run:

```bash
RUN_ID=$(gh run list --branch "$HEAD" --limit 20 \
  --json databaseId,name,headSha,conclusion \
  -q "[ .[] | select(.headSha == \"$HEAD_SHA\") ] | .[0].databaseId")

gh api "repos/$OWNER/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
  -q '.jobs[] | {name, conclusion, url:.html_url}'

gh run view "$RUN_ID" --log \
  | grep -Ei 'gate_result|patch_coverage|covered_lines|total_lines|total_coverage|quality_|net-new by level|\bmode\b' \
  | tail -40
```

The action's outputs are `mode`, `gate_result`, `patch_coverage`, `covered_lines`,
`total_lines`, `total_coverage`, `quality_gate_result`, `quality_net_new_count`,
`quality_blocking_count`, `quality_fail_on`. That's the whole list; don't invent an eleventh,
and don't quote a number you didn't read.

Three things about that log, all of which have a wrong reading that looks right:

- The step writes a few names the action doesn't re-export — `threshold`, `gate_failed`,
  `quality_gate_failed`, `quality_total_count`. Seeing them in the log is fine and they're
  usable as context. Don't describe them as outputs of the action, because a downstream
  workflow can't read them.
- **`quality_*` empty means quality was off, OR the repo pins a Brimyr old enough not to emit
  them.** The outputs alone cannot tell those apart. Say which you concluded and what it rests
  on (the workflow file's `quality:` input, the pinned tag).
- `total_coverage` is deliberately empty rather than `0.00` when the run measured nothing. Empty
  is "unmeasured", not "zero". It is also not the repository's coverage: a file no test imports
  is absent from the report and therefore absent from that denominator. It is reported, never
  gated on, so it is context and never a finding.

### e) Record which source you used, and never pretend

Set `gate_source` to exactly one of `comment`, `check-run`, `action-outputs`, or `none`, and say
it in the comment body in plain words. **"Brimyr didn't post a summary comment on this PR" is a
fact you report, not a gap you paper over** — and so is the opposite, so when you did read the
comment, link it. If all four fail, Brimyr didn't run against this head at all (fork PR without
secrets, a path filter, a skipped workflow, a queued run). Say that, review anyway — every
dimension below stands on its own without the gate — and note in §6 that the coverage figures
are unavailable rather than guessing at them.

Track the quality half separately, because it has its own three-way absence and they are not
the same fact:

| What you found | What it means | What you write |
| --- | --- | --- |
| A `## Brimyr: Net-new findings` block | quality ran; §4 applies | the count, the levels, and your triage |
| No such block, but a coverage block | `quality: 'false'` — the half was never enabled | "Brimyr's quality half isn't switched on for this repo" |
| `quality_gate_result: error`, or the broken-scan line | the scan didn't complete | §4b: this is a tool error, **not** zero findings |
| No comment at all, `quality_*` empty | can't distinguish "off" from "old Brimyr" | say which you concluded and why |

**Absence of findings is not a finding of absence**, and the three rows above are the three
different ways this review can be handed nothing. Never collapse them into "no quality issues".

### f) Pull the change itself

```bash
gh pr diff "$PR"
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate \
  -q '.[] | {path:.filename, status, additions, deletions, patch}'

gh pr view "$PR" --json title,body,additions,deletions,changedFiles,labels,closingIssuesReferences \
  -q '{title, body, additions, deletions, changedFiles, labels:[.labels[].name], closes:[.closingIssuesReferences[].number]}'
```

Read the body and any linked issue. A test can be internally coherent and still assert the wrong
contract, and the only way to see that is to know what the change was supposed to do.

Split the changed files into **production code** and **tests** up front, using the repo's own
conventions (`tests/`, `*_test.go`, `*.test.ts`, `test_*.py`, `spec/`). You need both halves: §1
reviews the tests against the production change, §2 reviews the production change on its own.

---

## 1. Test quality — the dimension coverage cannot measure

This is the spine of the review. Work every dimension against **every test the PR added or
changed**, and against the tests that already covered the production lines it touched. Each one
below is a distinct defect with its own tell and its own fix.

**The governing question, asked once per test: if the behaviour under test were wrong, would this
test fail?** Coverage answers "did the line run". This answers "would we find out". They are not
the same question and only one of them protects anybody.

### The mutation probe — how you actually answer that question

Two tiers. Use tier 1 always, tier 2 when a test runner is available in the environment.

**Tier 1, static, always.** For each new test, name the exact source mutation that *should* break
it: invert a conditional, return a constant, delete the error branch, drop a field from the
payload, return an empty list. Then read the assertions and decide whether any of them would
notice. Write the mutation down in the finding — "return `[]` unconditionally from
`resolve_targets()` and `test_resolve_targets_filters` still passes" is a finding a reader can
verify in ten seconds and cannot argue with. A vague "this test looks weak" is not.

**Tier 2, executed, when you can run the suite.** Apply the mutation, run only the affected test,
and record the result:

```bash
gh pr checkout "$PR"
git status --porcelain            # must be clean before you start

# apply the one-line mutation by hand, then run ONLY the affected test
<the repo's own test command, scoped to the one test>

git checkout -- <the mutated file>     # ALWAYS, immediately
git status --porcelain                 # must be clean again
```

**Hard rules on tier 2.** Mutate one file at a time. Revert with `git checkout -- <file>` the
moment the run finishes, before you write anything down. Never `git add`, never commit, never
push, and never leave a mutation in the tree if the run errors out. If you cannot guarantee a
clean revert, do tier 1 only and say so in the report.

### 1a. Executes a line without asserting on it (coverage theatre)

The purest form of the gap: the test calls the function, the line is counted, nothing is checked.
It contributes to `covered_lines` and to nothing else.

Tells: a test body with no assertion at all; a test whose only assertion is that the call did not
raise; `assert result is not None` as the sole check on a function that returns a structure; a
smoke test named as a behaviour test.

```bash
# python: test functions in the PR's test files with no assert / raises anywhere in the body
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[].filename' \
  | grep -E '(^|/)(test_[^/]+|[^/]+_test)\.py$' \
  | while read -r f; do
      git show "$HEAD_SHA:$f" | awk -v f="$f" '
        function flush() { if (name != "" && body !~ /assert|raises/) print f ": " name; name=""; body="" }
        /^[ \t]*(async )?def test_/ { flush(); name=$0; ind=match($0, /[^ \t]/); next }
        name != "" && !/^[ \t]*)/ && /[^ \t]/ && match($0, /[^ \t]/) <= ind { flush() }
        name != "" { body = body $0 "\n" }
        END { flush() }'
    done

# js/ts: an it()/test() block with no expect( before the next one
git show "$HEAD_SHA:<path>" | awk -v f="<path>" '
  /(^|[^A-Za-z_])(it|test)\(/ { if (name && body !~ /expect\(|assert/) print f ": " name; name=$0; body=""; next }
  name                        { body = body $0 "\n" }
  END { if (name && body !~ /expect\(|assert/) print f ": " name }'
```

The Python one tracks indentation deliberately, so a method inside a `unittest.TestCase` or a
pytest `class Test*` is caught alongside a module-level `def test_`. Anchoring that pattern at
column 0 — the obvious way to write it — makes every class-based suite invisible and returns
nothing, which reads exactly like a clean result. Check the detector finds *something* on a repo
you know has tests before you trust a zero.

Treat the grep as a shortlist, never as the finding. Read the body before you call it. A test that
asserts through a fixture teardown, a snapshot, or a schema validator is asserting; a grep can't
see that.

**Severity:** 🟡 when the covered line is ordinary logic. ⛔ when the assertion-free test is the
*only* coverage of a security control, a permission check, a money path, or an error handler,
because the gate is now reporting that path as protected when nothing is watching it.

**The fix to prescribe:** name the assertion, not the call. "Assert the returned list contains
only the two enabled targets, and that the disabled one is absent" — not "add an assertion".

### 1b. Asserts the implementation, not the behaviour

The test pins *how* the code works, so it fails on every refactor and passes through every
behaviour change that keeps the shape.

Tells: `assert mock_client.call_count == 3`; asserting on the exact SQL string a query builder
produced; asserting on log text as the only check that work happened; asserting the internal
call order of private helpers; a snapshot of an internal data structure standing in for a check
on output.

The question to apply: **rewrite the implementation to be correct but different — a different
loop, a batched call, an extracted helper. Does this test fail?** If yes and the behaviour is
unchanged, the test is pinned to the implementation. It will be deleted the first time it gets in
someone's way, and it protects nothing on the way out.

**Severity:** usually 🟡, and 💬 when the internal shape genuinely *is* the contract (a wire
format, a serialized schema, a public API surface). Say which of those you decided and why.

### 1c. Over-mocked — would pass if the real dependency were deleted

The single most common way a green suite covers a broken deployment. The test mocks the boundary
so thoroughly that it exercises the mock's behaviour, not the code's, and it stays green while the
real dependency is missing, renamed, misconfigured, or answering differently.

The litmus, and put it in the finding verbatim: **delete the real dependency entirely. Does this
test still pass?** If yes, it is testing the mock.

Tells: a mock whose return value is the assertion's expected value (the test asserts its own
setup); patching the module under test rather than its collaborator; `autospec` absent, so a
signature change on the real object never surfaces; every collaborator mocked, so no real code
path executes end to end; a mocked client whose *construction* is what actually fails in
production.

This has a live scar in this fleet, and it is worth naming because it is exactly this shape:
`nievah.worker.sqs_drain` imported `boto3` inside a function, `boto3` sat in the `dev` dependency
group, and the image built with `uv sync --frozen --no-dev`. Every unit test passed against a
mocked client. Production logged `sqs.setup_failed: No module named 'boto3'` and went quiet, with
the worker `Running`, `2/2 Ready`, health endpoint green, and the queue filling. No unit test can
see the container image. See §2f for the production-side check.

**Severity:** ⛔ when the mocked boundary is the thing the PR exists to change (a new client, a
new integration, a new external call) and nothing else exercises it. 🟡 otherwise.

**The fix to prescribe:** name the narrower seam. Mock the HTTP transport and keep the client
construction real; use `autospec=True` so a signature drift fails; add one integration or
contract test that constructs the real object even if it never sends a request.

### 1d. The name and comment describe one contract, the assertion enshrines the opposite

The most dangerous test in the catalogue, because it reads as a guarantee to every future reader
and to every review that skims. Coverage cannot see it. A linter cannot see it. Only reading the
name against the assertion can.

This has really happened here and it shipped a broken production consumer. `nievah`'s SQS drain
had a test named `test_a_client_setup_failure_does_not_propagate`, with the comment *"must not
kill the background task silently"* — and the assertion *"task exits cleanly"*. The name and the
comment stated the right contract. The assertion stated the exact opposite and locked it in. The
consumer's `consume_loop` caught a setup error, logged one warning, and `return`ed, ending the
background task permanently, so a transient DNS or credential blip at startup disabled the
consumer until a human noticed queue depth. The test asserted that as correct.

**How to check, on every added or changed test, without exception.** Read three things in order
and require that they agree:

1. the test **name**, as a sentence of intent
2. any **docstring or comment** in the body
3. what the **assertions actually require**

Then ask the direct question: *if the code did the opposite of what this name promises, would this
test fail, or would it pass?* Look hardest at negation words in names — `not`, `does_not`,
`never`, `without`, `no_` — because that's where the inversion hides. `does_not_propagate` and
`does_not_die` are different contracts, and a test can be named for one and assert the other.

```bash
# every added/changed test name carrying a negation, for a name-vs-assertion read
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -E '^\+.*(def test_|it\(|test\()' \
  | grep -Ei 'not|never|without|no_|fail|error|invalid|missing|reject'
```

**Severity:** ⛔, always, when the assertion contradicts the name. It is not a naming nit. It is a
false guarantee, and it is worse than the absence of the test, because the absence is visible in a
coverage report and this is not.

**The fix to prescribe:** say which of the two is the real contract, and fix the *other* one to
match. Usually the name is right and the assertion is wrong, which means the production code is
wrong too — check that before you write the finding, because then you have a second, larger
finding in the source.

### 1e. Missing negative and error-path cases

The happy path is covered, the failure path is not, and patch coverage is happy because the error
branch was never part of the diff or was executed incidentally.

Enumerate, per changed function: what does it do on invalid input, on a dependency that raises, on
a timeout, on a partial write, on an empty result, on a permission denial, on a retry that
exhausts? Every `except` / `catch` / `if err != nil` in the diff is a branch, and a branch with no
test is a claim nobody has checked.

Look specifically for a caught exception that logs and continues. That is a decision to keep
running in a degraded state, and it needs a test that proves the degraded state is the one
intended — see 1d's scar, where "caught and returned" was exactly the untested decision that
killed a consumer.

**Severity:** 🟡 normally. ⛔ when the untested error path is a security control, a rollback, a
retry that could double-charge or double-send, or an error handler that decides whether a process
keeps running.

### 1f. Missing boundary cases

The changed code has edges and only the middle is tested: empty collection, single element,
exactly-at-threshold, one past it, zero, negative, `None`/`null`, maximum length, unicode,
duplicate keys, an offset at the end of a page, a timestamp exactly on a window boundary.

Read the diff for every literal comparison — `>`, `>=`, `<`, `<=`, `==`, a slice index, a
`limit`, a `range` — and check that a test exists on **both** sides of it. Off-by-one lives here
and coverage is blind to it: one test at the middle of the range executes the same line an
exactly-at-boundary test would.

Give the concrete case in the finding: "no test at `limit` exactly, `paginate()` at `offset ==
total` returns the last page twice" beats "add boundary tests".

**Severity:** 🟡, or ⛔ when the boundary is a threshold in a control (rate limit, quota, retention
window, auth expiry).

### 1g. Flaky construction — time, ordering, network, randomness

A test that fails intermittently gets retried, then quarantined, then deleted, and the coverage it
contributed disappears with it. Catch it at introduction, when it costs one comment.

Tells, all greppable in the diff:

- **Time**: `datetime.now()`, `time.time()`, `Date.now()`, `time.Now()`, `sleep(` in a test,
  anything comparing against a wall clock, a TTL asserted by waiting. Fix: inject the clock or
  freeze it.
- **Ordering**: asserting on the order of a `set`, a `dict` before insertion order is guaranteed,
  an unordered query without `ORDER BY`, a filesystem listing, a concurrent gather. Fix: sort
  both sides, or assert set membership.
- **Network / real I/O**: a test that resolves a hostname, hits a real URL, or reads outside the
  repo. Fix: a fixture or a local double.
- **Randomness**: unseeded `random`, `uuid4()` in an expected value, a faker without a seed.
- **Shared state**: a module-level singleton, a class attribute, a real temp path, a database row
  the test doesn't clean up, order-dependence between tests in a file.

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -nE '^\+.*(datetime\.now|time\.time|Date\.now|time\.Now|sleep\(|uuid4\(|random\.|Math\.random|freeze_time)'
```

**Severity:** 🟡 normally, 💬 when the flakiness is genuinely bounded (a sleep in a test marked
slow and excluded from CI, say). Never 💬 for a wall-clock comparison; those fail at midnight, at
a DST change, or in a different timezone, and the failure always lands on somebody else.

### 1h. A test that cannot fail

The degenerate case. It runs, it covers lines, and there is no state of the world in which it goes
red.

Tells: `assert True`; `assert x == x`; an assertion comparing a variable to itself after a
round-trip through the code; the whole body wrapped in `try/except: pass` or a bare `catch {}`; an
assertion inside a conditional or a loop that never executes (a `for` over an empty fixture is the
common one); `expect(mock).toHaveBeenCalled()` where the test's own setup made the call;
`pytest.raises` around a call that raises for a *different* reason than the one under test — a
`TypeError` from a signature mismatch satisfying a test that meant to check a `ValueError` from
validation; a test skipped by a marker or a `-k` filter that never runs in CI at all.

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -nE '^\+.*(assert True|assert 1 ==|expect\(true\)|toBeTruthy\(\)\s*$|except.*:\s*pass|catch\s*\(\w*\)\s*\{\s*\}|@pytest\.mark\.skip|it\.skip|test\.skip|xfail)'
```

For a `pytest.raises` / `expect().toThrow()`, check the **match**: an exception class alone is
weak, and the message or type is what separates "the validation fired" from "the call signature is
wrong". Prescribe `pytest.raises(ValueError, match="…")`.

**Severity:** ⛔ when it's the only coverage of the changed behaviour. 🟡 otherwise. A test skipped
in CI is ⛔ if the PR added it as the coverage for its own change, because the gate counted lines
that no run will ever execute again.

---

## 2. Code quality past the number

Brimyr measures the tests. Nobody measures the change itself. These are the defects that ship at
100% patch coverage because coverage was never the instrument that would have found them. Work
the production half of the diff (from §0f) against each.

### 2a. Duplication the diff introduces

Not duplication that already existed — that's not this PR's debt. Duplication the diff *adds*: the
same parsing, the same retry, the same date normalisation, the same permission check written a
second time three files away. Two copies means the next fix lands on one of them.

```bash
# the helper may already exist — search before calling it new
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -E '^\+' | sort | uniq -c | sort -rn | awk '$1 > 2 && length($0) > 40' | head -20
```

Read the hits — repeated boilerplate (imports, decorators, closing braces) is noise. What you're
after is a repeated *block* of logic. Then grep the tree for the same shape outside the diff,
because the most useful version of this finding is "there's already a `normalize_ref()` in
`utils/refs.py`". **Severity:** 🟡 with a named existing helper, 💬 without one.

### 2b. A function doing two jobs

The tell is the name containing "and", a boolean parameter that switches behaviour, a function
that both computes and persists, or one that returns a value *and* mutates an argument. The
practical cost lands on tests: you cannot test either job in isolation, which is often the real
reason the new test is weak (§1a and §1c both grow here). Say so in the finding — it links the
code smell to the coverage number and makes the fix worth doing.

**Severity:** 🟡 when it's why the test is untestable, 💬 when it's just shape.

### 2c. A name that lies

A name that promises something the code doesn't do is a bug with a delayed fuse, and it is
invisible to every automated check in the pipeline. `validate_x()` that returns a bool nobody
checks. `get_*` that writes. `is_*` returning a non-boolean. `*_safe` that isn't. A `_private`
helper imported across the package. A constant whose name states a unit the value isn't in
(`TIMEOUT_MS = 30`). A flag named for the enabled state that defaults to the disabled one.

This has a fleet-scale sibling worth remembering: a tier named for a **role** rather than a
location (`worker`) silently widened from one node to three when a node joined, while every
comment beside it still said "pinned to ff-vm1". The name was accurate the day it was written and
became a lie without anybody touching it. Names that encode a fact rather than a rule rot.

**Severity:** ⛔ when the name is load-bearing for a caller's correctness (a `validate_` that
returns rather than raises, and a caller that ignores the return). 🟡 otherwise.

### 2d. An abstraction with one caller

A base class with a single subclass, an interface with one implementation, a config layer over one
value, a factory that constructs one thing, a generic helper parameterised for cases that don't
exist. It costs indirection now and it will be wrong for the second caller anyway. Count the
callers before you write the finding:

```bash
git grep -n "ClassOrFunctionName" -- ':!*test*' | wc -l
```

**Severity:** 💬 normally. 🟡 when the indirection is what's forcing the mocking in §1c.

### 2e. Error handling that swallows

`except Exception: pass`. A `catch` that logs at debug and continues. A bare `return None` on
failure where the caller can't distinguish it from a legitimate empty result. A retry that catches
the exception that means "stop retrying". An `err != nil` checked and discarded.

The specific shape to hunt: **a caught error that ends a loop or a background task**. That is the
`nievah` consumer failure from §1c, restated from the source side — `consume_loop` caught the
setup error, logged one warning, and returned, so the background task ended permanently and a
transient failure became a permanent outage with a green health endpoint.

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -nE '^\+.*(except[^:]*:\s*pass|except[^:]*:\s*(return|continue)|catch\s*\{\s*\}|catch\s*\([^)]*\)\s*\{\s*\}|_\s*=\s*err|rescue\s*$)'
```

**Severity:** ⛔ when swallowing turns a recoverable failure into a silent permanent one, or when
it hides a security failure (an authz check that errors and falls through to allow). 🟡 otherwise.

### 2f. A lazy import that defers a requirement rather than removing one

Importing inside a function so callers who don't use the feature don't pay for it is sound
reasoning. It does **not** move the dependency out of the runtime requirements — it only moves the
moment you find out. If the package then sits in a dev-only group while the image installs
production-only, every test passes, the image builds, the release ships, and the feature cannot
construct a client in production.

That is not hypothetical. `nievah`'s `sqs_drain` did exactly this: `boto3` imported inside the
function, left in the `dev` group, `Dockerfile` running `uv sync --frozen --no-dev`. It logged
`sqs.started`, then `sqs.setup_failed: No module named 'boto3'`, and went quiet.

**No unit test can see the container image**, so this check is manual and it is yours:

```bash
# 1. every function-scoped import the diff adds
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate -q '.[] | select(.patch) | .patch' \
  | grep -nE '^\+\s+(import |from .* import )'

# 2. for each package named there, which group declares it
git show "$HEAD_SHA:pyproject.toml" | sed -n '/^\[project\]/,/^\[/p'      # runtime deps
git show "$HEAD_SHA:pyproject.toml" | sed -n '/dependency-groups/,$p'      # dev-only groups

# 3. what the image actually installs
git show "$HEAD_SHA:Dockerfile" | grep -nE 'uv sync|pip install|poetry install|npm ci|pnpm i'
```

A package that is (1) imported on a production code path, (2) declared only in a dev group, and
(3) excluded by the install line is **⛔ Blocking**, every time. The fix is to move it into
`[project.dependencies]`, and the guard is a test that reads `pyproject.toml` and asserts the
package is in the runtime dependencies and not in a dev group — a test the *file* can see, since
the container is out of reach. Prescribe that test by name in the finding.

The same shape exists outside Python: a Node dependency in `devDependencies` used at runtime with
`npm ci --omit=dev`, a Go build tag, an optional extra. Check the install line, not the manifest.

### 2g. Dead code

Code the diff adds that nothing reaches: a branch made unreachable by a guard above it, a
parameter never read, a returned value never consumed, an exported symbol with no importer, a
feature flag with no reader, a config key nothing loads. Coverage tools *do* see some of this as
uncovered lines, which is where §3 and this section meet — but a covered-by-an-added-test dead
function is invisible to both, so check the caller count for anything new:

```bash
git grep -n "new_symbol_name" -- ':!*test*' | wc -l    # 0 outside its own definition = dead
```

**Severity:** 🟡 when the diff adds it, 💬 when the diff merely leaves it behind.

### 2h. A comment that contradicts the code

Treat a comment as a claim and check it, exactly as you would check an assertion. When the two
disagree, one of them is a defect and you cannot assume it's the comment: a stale comment misleads
the next reader, and a *correct* comment beside wrong code means the code is the bug.

This fleet has been bitten by it twice at scale, and both times the prose was right:
`ansible/firefly-control-plane-resources.yaml` carried a comment predicting the exact GC
death-spiral that later took the node down, complete with the threshold to watch — and nothing was
watching. A Terraform `schedule.tf` said *"Names must match `nievah.worker.tick.CRONJOB_TICKS`"*
directly above a map that did not match, and the mismatch silently deleted every scheduled tick.

**A threshold or an invariant written in prose is not a monitor and not a check.** When the diff
adds a comment asserting that two things must agree, the finding is: make it mechanical. A test, an
assertion, a shared constant, a CI step. **Severity:** 🟡 when the comment states an invariant with
no enforcement, 💬 for a merely stale comment.

### 2i. Complexity that will be the next incident

The last dimension, and a judgement call, so hold it to a high bar. Deep nesting, a function
whose branch count exceeds what any set of tests will realistically cover, a condition with four
`and`/`or` terms and a negation, state spread across three mutable variables, a `try` block long
enough that you can't tell which statement the `except` is for.

The bar for reporting it: **name the incident.** "Six branches and three of them share a mutable
`state` dict; the retry path re-enters with `state` already populated, and nothing tests the
second entry" is a finding. "This function is complex" is padding, and padding is what makes the
whole comment ignorable. If you can't name the failure, drop it.

**Severity:** 🟡 with a named failure path, 💬 otherwise, never ⛔ on complexity alone.

---

## 3. The uncovered lines Brimyr let through

Brimyr fails a PR under the threshold. It says nothing at all about a PR **at or above** it, and
80% of a 140-line change leaves 28 lines unexecuted. Those 28 are not a random sample: uncovered
lines cluster in error handlers, fallbacks and edge branches, because those are the hardest to
reach from a happy-path test. **An uncovered error path is worth more than ten covered getters**,
and the gate weights them identically.

So a `pass` from Brimyr is where this section starts, not where it stops. And the comment won't
help you here: Brimyr lists uncovered changed lines only when the gate **failed** (§0b), so on
the pass this section is about, that list doesn't exist anywhere but in the coverage report you
fetch yourself.

### 3a. Get the coverage report

The coverage file is produced by the repo's own test job. Find it from the run:

```bash
gh api "repos/$OWNER/$REPO/actions/runs/$RUN_ID/artifacts" \
  -q '.artifacts[] | {name, size:.size_in_bytes, expired}'

gh run download "$RUN_ID" -D .git/bqr-cov          # all artifacts

# gh extracts EACH artifact into its own subdirectory named after the artifact, so the
# report is at .git/bqr-cov/<artifact-name>/… — never at .git/bqr-cov/coverage.xml.
# Find it, don't assume it:
COV=$(find .git/bqr-cov \( -name 'coverage*.xml' -o -name 'lcov.info' -o -name 'coverage*.json' \) | head -1)
echo "coverage report: ${COV:-none found}"
```

Carry `$COV` into §3b — it's the path the rest of this section reads. An empty `$COV` means fall
through to §3c, not that the change is covered.

If no artifact is published, read the workflow to see what the test step writes
(`git show "$HEAD_SHA:.github/workflows/<file>" | grep -nE 'cov|lcov|coverage'`), and fall back to
§3c. Don't guess at an artifact name.

### 3b. Intersect uncovered lines with the lines the PR changed

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate \
  -q '.[] | {path:.filename, patch:(.patch // "")}' | jq -c . > .git/bqr-files.jsonl

python3 - "$COV" <<'PY'
import json, re, sys, xml.etree.ElementTree as ET

added = {}
for line in open(".git/bqr-files.jsonl"):
    rec = json.loads(line)
    path, n = rec["path"], 0
    for ln in rec["patch"].splitlines():
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", ln)
        if m:
            n = int(m.group(1))
        elif ln.startswith("+") and not ln.startswith("+++"):
            added.setdefault(path, set()).add(n); n += 1
        elif ln.startswith("-") or ln.startswith("\\"):
            pass
        else:
            n += 1

uncovered = {}
for cls in ET.parse(sys.argv[1]).getroot().iter("class"):
    fn = cls.get("filename") or ""
    for ln in cls.iter("line"):
        if ln.get("hits") == "0":
            uncovered.setdefault(fn, set()).add(int(ln.get("number")))

for path in sorted(added):
    # Cobertura paths are relative to <sources>; match on suffix
    hit = next((f for f in uncovered if path.endswith(f) or f.endswith(path)), None)
    gaps = sorted(added[path] & uncovered[hit]) if hit else []
    if gaps:
        print(f"{path}: {gaps}")
PY
```

For `lcov.info` instead of Cobertura, uncovered lines are the `DA:<line>,0` records:

```bash
awk -F'[:,]' '/^SF:/{f=$2} /^DA:/ && $3==0 {print f": "$2}' "$COV"
```

If the suffix match finds nothing, the report's `<sources>` root doesn't line up with the repo
paths — read `<sources>` and prefix accordingly rather than reporting "fully covered", which is
the wrong answer and the easy one.

### 3c. Local fallback when there's no report to download

```bash
gh pr checkout "$PR"
<the repo's own coverage command, from CONTRIBUTING.md / Makefile / package.json / pyproject>
```

Then run §3b against the file it wrote. Leave the tree clean afterwards. If you can't produce a
report at all, say so in the comment — "I couldn't get line-level coverage, so §3 wasn't checked"
is an honest and useful sentence. Silently skipping the section is not.

### 3d. Judge each uncovered changed line on its own

Do **not** report the list. Report the ones that matter, ranked, and say what a test would have to
assert. Rank by what the line does:

| Uncovered changed line | Weight |
| --- | --- |
| A security control: authz check, signature verify, token expiry, input sanitisation | ⛔ |
| An error handler, rollback, or compensating action | ⛔ if it decides whether a process keeps running, else 🟡 |
| A money, billing, or irreversible-side-effect path (send, delete, publish) | ⛔ |
| A retry, backoff, or timeout branch | 🟡 |
| A migration, a data transform, a concurrency guard | 🟡 |
| Ordinary branch logic on a non-critical path | 🟡 |
| Logging, `__repr__`, a trivial getter, a type stub, a re-export | 💬 or drop it |

The number is context, not a finding (§6). What goes in the comment is: *this* line, *this*
behaviour, uncovered, and here's the assertion that would cover it.

---

## 4. The net-new quality findings Brimyr reported and didn't block on

Brimyr's second half counts **net-new** findings: results Chargate's classifier attributes to
this PR's diff rather than to the pre-existing pile. It is off by default, and when it's on,
`quality_fail_on` defaults to `none`.

Read what that means. **The normal state of a healthy repo is a green Brimyr carrying a list of
real, PR-scoped defects that it deliberately did not block on.** The gate counted them, printed
them, passed, and moved on. Nobody triages that list. It sits in a collapsed `<details>` under a
green tick, on every PR, and the tick is what people read.

That list is the single richest "what else should change here" surface on the whole pull
request, and the expensive part is already done: something ran the linters, and something
already worked out which findings are this PR's. What's missing is the only part a count can't
do. **Which of these actually matter, and why can the rest wait?** That question is yours.

### 4a. Read the quality block

It sits under `## Brimyr: Net-new findings` in the same comment as the coverage block (§0b),
and appears verbatim in the job summary:

```markdown
## Brimyr: Net-new findings

**Gate:** `report-only` · **Blocks on:** `none`

| Metric | Value |
|--------|-------|
| Net-new findings | **14** |
| Pre-existing (never blocking) | 212 |
| Suppressed in source (never blocking) | 3 |
| Net-new by level | error=2, note=1, warning=11 |

📋 Report-only — `quality_fail_on` is `none`, so findings are counted and shown but nothing blocks.

<details><summary>Net-new findings</summary>

- `src/api/routes/items.py:142 [BLE001]`
- `src/sync/pull.py:80 [BLE001]`
- `src/api/schemas.py:19 [N815]`
… 11 more entries, one per finding …

</details>
```

(Abridged: 14 findings is under the 20-entry cap, so the real block lists all fourteen and
carries no `… and N more` line. That line appears only above 20 — see below.)

- **Gate** is `pass` | `fail` | `error` | `report-only`. `report-only` and `pass` are different
  states and the block says which; `error` is §4b.
- **Blocks on** is the threshold in force. `none` means nothing could ever have blocked.
- A `Blocking at <level>` row appears only on a gated run, so its absence is not a zero.
- **Net-new by level** is the per-level breakdown, rendered `name=count` and comma-joined,
  levels sorted alphabetically. This is the breakdown you rank against, and **no action output
  carries it** — the `quality_*` outputs are four scalars (§0d), none of them per-level. It
  exists in exactly two places: this block (identically in the job summary, which is the same
  render) and one line on the run log's stderr, `brimyr: quality: net-new by level: error=2,
  note=1, warning=11`. That line reads `quality:` and not `quality_`, so a grep for the output
  names alone slides straight past it; §0d's pattern matches it on `net-new by level`.
- The verdict line is exactly one of four. The `📋 Report-only` line above wins whenever
  the run couldn't block, and it names which of the two reasons applied (`quality_fail_on` is
  `none`, or baseline mode has no diff to gate). Otherwise:

  ```text
  ❌ **N net-new finding(s) at or above `<level>`.**
  ✅ N net-new finding(s), none at or above `<level>`.
  ✅ No net-new quality findings.
  ```
- The listing entries are `path:line [ruleId]`, **capped at 20**, with `- … and N more` when
  there were more. An entry whose SARIF carried no location degrades to the path alone or to
  `(no location)`.

Two consequences of that cap. The count in the table is the truth and the listing is a sample,
so when `… and N more` is present, say the listing was truncated instead of writing as though
you reviewed all of them. And an entry with no line number can't be verified at `head_sha` and
can't be deduped by line, so don't promote it until you've found the site yourself (§8, step 1).

**Only one of those four lines means zero**, and it's the last one. The other three all sit
above a `Net-new findings` count that can read 14, and each is a different way of saying nobody
acted on them:

- `📋 Report-only — quality_fail_on is none …` is the default, and it means the gate was
  never allowed to look. This is the line you'll see on almost every repo.
- `✅ N net-new finding(s), none at or above <level>` is a repo that *did* set a threshold, and
  nothing reached it. Still N findings, just with a bar in place that they went under.
- `❌ **N net-new finding(s) at or above <level>.**` is the rare one: the gate blocked. Those
  specific findings are already being acted on, so they're the least interesting to you (§6c)
  and the *other* net-new findings in the listing are still untriaged.

Read the count first and the tick second. A green tick above a non-zero count is this section's
entire reason to exist.

### 4b. A scan that didn't complete is not a clean PR

Chargate writes its counts JSON *before* it decides whether the scan produced anything, so a run
that scanned nothing leaves a well-formed document full of zeros. On its own that file is
indistinguishable from a clean pull request, which is why Brimyr refuses to read it and reports
an error instead. Two distinct shapes, and you must not read either as zero:

- **Broken.** `quality_gate_result: error`, and the block carries
  `> ❌ **The quality scan did not complete** — Chargate errored or produced no report. This is
  a tool error (build red), **not** zero net-new findings.` Everything downstream of it —
  the count, the levels, the listing — is absent, not zero.
- **Partial.** The scan exited 0 but some linters didn't run:
  `⚠️ **The scan was not complete** — these linters did not run: …`. The count is real for the
  linters that ran and silently missing everything the named ones would have said. A scan that
  quietly got smaller and a repo that's genuinely clean produce the same number.

How to tell, in order: `quality_gate_result` from §0d if you have it, then grep the comment body
for either line, then check whether a `## Brimyr: Net-new findings` heading exists at all (no
heading means quality was never enabled — §0e's table). **Never write "no quality findings" off
a broken or partial scan.** Say the scan didn't complete, name which linters were missing when
the block names them, and mark the section unchecked. That is the same honesty rule §3c applies
to an unreachable coverage report, and for the same reason: a silent false-clean is the failure
this whole review exists to prevent.

### 4c. Severity here is the SARIF level, not a security band

`fail_on` speaks SARIF levels: `none` | `note` | `warning` | `error` | `any`. It does **not**
speak `critical` / `high` / `medium` / `low`. This is not a naming quirk, it's load-bearing:
Brimyr gates off the counts document, where `per_severity_*` is populated only from a real
`security-severity` property, and quality linters essentially never emit one. A band-valued
threshold would therefore match nothing, on every PR, forever, while looking exactly like a
configured gate. `per_level_*` covers every result, so levels are what the gate can actually
reach.

| SARIF level | Chargate band | What it actually tells you |
| --- | --- | --- |
| `error` | `high` | the linter is confident the rule applies |
| `warning` | `medium` | the linter thinks it applies |
| `note` | `low` | the linter is offering an opinion |

Chargate's `fail-on: high` is Brimyr's `fail_on: error`. `any` blocks on every net-new finding
including ones the producing linter left unlevelled; `none` is report-only.

**A reviewer who reads those as severity bands mis-ranks the entire list.** A linter's `error`
means "this rule is confident", not "this is dangerous" — a naming-convention rule fires at
`error` all day. A `note` from a rule about a swallowed exception can cost you an outage. Use
the level to read the linter's confidence, and rank by what the code does, per §4d. Never
translate a level into a severity marker mechanically; ⛔ / 🟡 / 💬 are your judgement (§5),
not a relabelling of somebody else's enum.

### 4d. Judge them, don't restate them

**Never paste the listing back into your comment.** It's already on the PR, one collapsed
`<details>` above yours, and restating it is exactly the duplication §6 exists to prevent. What
you add is a decision. Sort the net-new findings into three buckets and report only the first
two:

1. **Matters now.** The finding names a defect this rubric would have caught on its own: a
   swallowed exception (§2e), a bare `except`, a mutable default argument, a resource never
   closed, a name shadowing something that changes behaviour, an unreachable branch (§2g).
   Promote it: write your own concrete failure sentence, give it the `class` from §7b that
   describes the defect, and say in one clause that the linter flagged it and you're keeping it
   because you can name what breaks.
2. **Matters, later.** Real, but not this PR's job: it sits on a line the diff touched
   incidentally, or the fix is a refactor with its own blast radius. One line, 💬, no drama.
3. **Noise here.** Style, line length, an idiom this repo has already decided against, a rule
   it suppresses elsewhere in the tree. Drop it, count it, don't narrate it.

The bar for bucket 1 is the bar the whole rubric uses: **you can name the failure** in §8, step 4's
shape, *this input or state produces this wrong outcome*. A finding you can only restate as the
linter's own message is one you're copying, not judging. Leave it in bucket 3 and let the count
speak for it.

Then say the split, in one sentence, in the comment:

> Brimyr reported 14 net-new findings and blocked on none of them. Two are worth fixing here:
> the bare `except` at `src/sync/pull.py:80` and the client never closed at `src/api/client.py:33`.
> The other 12 are formatting and naming, and they can wait.

That sentence is this section's deliverable. It's short, it's a judgement, and it is the only
thing on the PR that tells a reader whether the collapsed list under the green tick was worth
opening.

Two guard rails on the promotion:

- **`Pre-existing (never blocking)` is not this PR's debt**, the same way §2a's duplication rule
  only covers what the diff adds. Don't promote one into a blocking finding of yours. If you
  report it at all, it's `pre_existing: true` and never `blocks: true` (§7b).
- **Never argue from the gate's silence.** `quality_fail_on: none` means the threshold could not
  fire; it is a configuration, not an assessment. A finding you can justify at ⛔ stays ⛔ on a
  green quality gate, exactly as it does on a green coverage gate.

---

## 5. Severity

Same three markers as `pr-review`, so `pr-triage` and the humans reading both comments don't have
to learn a second vocabulary:

- **⛔ Blocking** — this shouldn't merge as it stands. A test that asserts the opposite of its
  name, a runtime dependency the image won't install, a swallowed error that turns recoverable
  into permanent, an uncovered security control, an assertion-free test standing as the only
  cover for a critical path.
- **🟡 Should-fix** — a real gap the author should close before this lands: missing negative,
  boundary or error-path tests for non-trivial new logic; an over-mocked test on a
  non-critical seam; duplication with a named existing helper; a flaky construction.
- **💬 Nit** — nothing breaks if they skip it. Prefix with `nit:`. Never inflate one to pad the
  comment.

In the machine-readable block those become the shared vocabulary the security review also uses:
⛔ is `critical` or `high` with `blocks: true`, 🟡 is `medium`, 💬 is `low`, and `verdict` is
`blocking` / `advisory` / `clean` (§7b). Pick `critical` over `high` when the defect is already
reachable in production rather than only on the next change.

**This comment sets no status check.** A ⛔ here doesn't block the merge button; it's a judgement,
and `pr-triage` acting on it is what closes the loop. Say that plainly in the comment so nobody
reads it as a second gate that has jammed.

**Severity honesty.** The label and the prose must agree. If your text for a 🟡 says the current
code makes the failure "probably fine" and the only failure you can name is hypothetical, it's a
💬. A 🟡 must name either a failure reachable today or missing coverage for non-trivial new logic.
Missing coverage stays 🟡 even though nothing fails today — that's the whole subject here.

And the rule from the top, one more time because this is where it gets tested: **`gate_result:
pass` is not a reason to relabel anything downward.** Neither is `quality_gate_result: pass`,
and that one is worse, because at the default `quality_fail_on: none` it passes *by
construction* — the threshold cannot fire, so the verdict carries no information about any
finding underneath it. A ⛔ you can justify stays a ⛔ on a doubly green Brimyr.

**Don't inherit the linter's ranking either.** A SARIF level is the producing tool's confidence,
not your severity (§4c). Mapping `error` → ⛔ and `note` → 💬 mechanically produces a review that
ranks a naming-convention rule above a swallowed exception. Rank by what the code does.

---

## 6. Deduplicate: what the gates already said, and which lane owns it

Everything you post must be **additive**. The point of this review is what the gates did not
catch. A finding a gate already reported is a duplicate: suppress it, count it, and say how many
you dropped. A comment that restates a gate is noise, and noise is how a real finding gets
skimmed past.

There are now **three** axes to dedupe against, and they are not the same check:

1. **Coverage** — Brimyr's own percentage and, on a failing run, its uncovered-line list (§6e).
2. **SonarQube** — the non-blocking scan Brimyr runs alongside the gate (§6b).
3. **Brimyr's own net-new quality findings** — new, and the one this rubric used not to have
   (§6c). It's the axis most likely to catch you, because those findings are Chargate-derived
   and read like a different tool's output while sitting inside Brimyr's comment.

And there's a fourth thing that isn't a dedupe at all but a **lane boundary** (§6d): security
findings are not yours to report, whichever gate surfaced them.

### 6a. Collect what has already been said

```bash
# Brimyr's own comment (§0b) — both blocks: the coverage verdict AND the net-new quality listing
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | test("<!-- brimyr:(pr|quality)-summary -->")) | .body'

# Chargate's summary and its inline findings — different gate, still a duplicate if it said it
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | contains("<!-- chargate:pr-summary -->")) | .body'
gh api "repos/$OWNER/$REPO/pulls/$PR/comments" --paginate \
  -q '.[] | select(.body | contains("<!-- chargate:finding -->")) | {path, line, body}'

# any sibling agent-skills review already on this PR
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | contains("<!-- agent-skills:")) | {id, first_line:(.body|split("\n")[0])}'

# human and bot review threads, plus their resolution state
gh api graphql --paginate -f query='
query($owner:String!, $repo:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes { isResolved path line comments(first:10){ nodes { author{login} body } } }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR"
```

Paginate the threads and check `totalCount` against what you got back. `reviewThreads(first:100)`
silently drops the overflow, and the ones it drops are the **newest** — exactly what a scanner
posted seconds ago.

### 6b. SonarQube

Brimyr runs `sonar-scanner` non-blocking, so Sonar's issues are already on this PR somewhere and
restating them is a duplicate. Read them from whichever of these the environment gives you:

```bash
# project key, from the scanner's own config
git show "$HEAD_SHA:sonar-project.properties" 2>/dev/null | grep -E 'projectKey|organization'

# the PR's issues, when SONAR_HOST_URL / SONAR_TOKEN are in the environment
curl -sS \
  -u "$SONAR_TOKEN:" `# gitleaks:allow — env var reference, not a literal secret` \
  "$SONAR_HOST_URL/api/issues/search?componentKeys=<projectKey>&pullRequest=$PR&resolved=false" \
  | jq -r '.issues[] | "\(.component):\(.line) [\(.severity)] \(.rule) \(.message)"'

# no credentials? the check run and any SonarQube status carry the headline
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" --paginate \
  -q '.check_runs[] | select(.name | test("sonar"; "i")) | {name, conclusion, title:.output.title, summary:.output.summary}'
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/status" -q '.statuses[] | select(.context | test("sonar"; "i"))'
```

If none of that resolves, say in the comment that Sonar's issue list wasn't reachable, so a
finding of yours *might* overlap with one of its. That's an honest caveat and it costs one line.

### 6c. Brimyr's own net-new quality findings — the second axis

This is new, and it is the axis a rubric written for a coverage-only gate has no habit for. Pull
the listing entries out of the comment body and hold them beside your own findings:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | test("<!-- brimyr:(pr|quality)-summary -->")) | .body' \
  | sed -n '/## Brimyr: Net-new findings/,$p' \
  | grep -oE '^- `[^`]+`' | sed 's/^- //; s/`//g'
```

Each surviving line is `path:line [ruleId]` (§4a). Match them against your findings on the same
rule §6e uses: same path, line within ±3, same underlying defect. Then apply this, which is the
part that differs from every other axis:

- **Restating one is a duplicate.** If your finding is the linter's finding in your own words,
  drop it and count it. The reader can see the listing.
- **Promoting one is not a duplicate** — it's the deliverable of §4d. You're adding the named
  failure, the severity judgement, and the fix. Lead with those and never re-narrate the rule
  id. Say you're keeping it and why in one clause.
- **The gate's silence is not a dedupe argument.** With `quality_fail_on: none` every finding in
  that listing was "already reported and not acted on". That is a threshold, not an assessment,
  and it is the reason this axis exists rather than a reason to drop everything on it.

The `… and N more` cap (§4a) applies here too: findings past the cap are not in the listing, so
a finding of yours that doesn't match anything visible may still be a duplicate of one you can't
see. Say so once, in the same breath as the truncation caveat, rather than claiming a clean
dedupe you couldn't perform.

### 6d. The lane boundary: security is Chargate's, quality is yours

Both gates now emit Chargate-derived findings. Brimyr's quality half **calls** `chargate
filter-sarif`, so the classifier behind Brimyr's listing and the one behind Chargate's comment
are the same engine, pointed at different linter sets. That makes the overlap real, and it makes
the rule that separates the two post-gate reviews worth stating in one line:

**The boundary is the SUBJECT, not the tool.** Not which gate reported it, not which binary ran
it. What the finding is about.

| Subject | Lane | What you do with it |
| --- | --- | --- |
| Injection, authz, authn, secrets, crypto, SSRF, deserialisation, path traversal, a vulnerable dependency | `chargate-security-review` | leave it, even when it showed up in Brimyr's listing |
| A swallowed exception, dead code, a name that lies, complexity, duplication, a missing or dishonest test | yours | judge it (§4d), report it |
| Both at once — a swallowed exception in an authz path | security leads | report only the quality half, and say in one clause that the security lane owns the rest |

Two concrete tests before you promote anything out of Brimyr's listing. **Read the rule id**:
Chargate's curated quality set is `GO_GOLANGCI_LINT`, `JAVASCRIPT_ES`, `JAVA_PMD`,
`PYTHON_RUFF`, `TYPESCRIPT_ES`, so a `ruff`, `golangci-lint`, `eslint` or `PMD` rule is yours by
construction, while a rule id from a security scanner arrived by a different route and is not.
And when the id doesn't settle it, **ask who the fix protects**: an attacker, or the next
maintainer. Post to that lane.

Then check whether the other lane has already run — §6a's third query lists any
`<!-- agent-skills: -->` review on the PR — and drop anything
`<!-- agent-skills:chargate-security-review -->` has already said. Two reviews from one system
that both report the same finding is precisely the failure this section exists to prevent, and
it costs more credibility than either finding is worth.

### 6e. The dedup rule

Drop a finding of yours when a gate or an existing thread already names **the same defect at the
same place**: same file, line within ±3 (a scanner and a human anchor differently), and the same
underlying problem. Same *file* alone is not a duplicate — Sonar flagging cognitive complexity on
line 40 doesn't cover your assertion-inversion on line 58.

Keep it, and say why, when you're **materially extending** it: the gate said the function is
uncovered, you can say the uncovered branch is the authz denial and name the assertion. Lead the
finding with what's new, don't re-narrate what the gate said.

**Never restate a gate number as a finding.** `patch_coverage` is context for the first
paragraph of the comment. "Patch coverage is 84%" is not a finding, it's the gate's output, and
repeating it back is the exact noise this section exists to prevent. Same for
`quality_net_new_count`: "Brimyr reported 14 net-new findings" is context, and the *finding* is
which two of the fourteen matter and why (§4d). `total_coverage` is context too, and it isn't
even the repository's coverage (§0d), so it never carries a finding on its own.

Count the drops. `duplicates_dropped` goes in the machine-readable block and one plain sentence
goes in the body: "Dropped 3 as duplicates of Chargate, Sonar and Brimyr's own findings list."
Name the sources you deduped against, because with three axes "dropped 3" no longer says which
check you actually ran. That number is how a reader knows you looked, and it's how a maintainer
notices when the gates and this review start overlapping enough to retune one of them.

---

## 7. The reply comment — one, idempotent, patched in place

**Exactly one PR issue comment, carrying the hidden marker
`<!-- agent-skills:brimyr-quality-review -->` as its first line.** Find the prior one and `PATCH`
it; `POST` only when none exists. Same find-or-patch pattern Chargate uses for
`<!-- chargate:pr-summary -->`. One comment per PR, forever, rewritten whole on every run.

GitHub issue comments don't thread, so "replying to Brimyr" means: link Brimyr's comment in your
opening line so the two read as a pair. That link is the normal case now — when the repo runs
with `pr_comment: 'true'` there is a comment to point at, and yours reads as the second half of
it. When Brimyr posted nothing, you have nothing to link, and you say so instead.

### 7a. Find the prior comment

```bash
PRIOR=$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:brimyr-quality-review -->"))) | last) // empty | .id')
echo "prior comment: ${PRIOR:-none}"
```

Use `last`, not `first`: if a previous run ever double-posted, patch the newest and say in the
report that a duplicate exists so a human can delete the stale one. Never post a third.

### 7b. Write the body

Write it to `.git/brimyr-quality-review.md` with **real newlines** (never the two literal
characters `\n`). Structure:

````markdown
<!-- agent-skills:brimyr-quality-review -->
## Quality review

Brimyr's patch coverage came back at 91.4% (128 of 140 changed lines), over the 80% threshold, so
the gate passed. [Its summary is here](<link to the Brimyr comment>). It also reported 14 net-new
quality findings and blocked on none of them, because `quality_fail_on` is `none`. One of those
is worth fixing here. Everything below is what neither number covers.

<When Brimyr posted no comment, that first paragraph names the source you did use instead:
"Brimyr didn't post a summary comment on this PR, so the figures below come from the check run:
patch coverage 91.4%, gate `pass`, and no quality figures at all." State the source, and never
imply a comment you didn't read. When the quality half didn't run, say that rather than
implying it came back clean.>

### ⛔ Blocking
- `src/nievah/worker/sqs_drain.py:87`: `test_a_client_setup_failure_does_not_propagate` asserts
  the task exits cleanly, which is the opposite of what its name and its comment promise. On a
  setup failure `consume_loop` returns and the background task ends permanently, so a transient
  DNS blip disables the consumer until somebody notices queue depth. The test should assert the
  loop is still running and retried, and `consume_loop` should retry rather than return.

### 🟡 Should-fix
- `src/api/routes/items.py:142`: the 403 branch is the only uncovered changed line. Add a test
  that calls the route as a non-owner and asserts a 403 plus an empty body, not just the status.
- `tests/test_items.py:30`: `test_list_items` calls `list_items()` and asserts only that it
  didn't raise. Return `[]` unconditionally from `list_items` and it still passes. Assert the two
  enabled items are present and the disabled one is absent.
- `src/sync/pull.py:80`: Brimyr's findings list flags the bare `except` here and didn't block on
  it. Keeping it, because I can name what it costs: it catches the `KeyboardInterrupt` and the
  `CancelledError` too, so the sync task can't be shut down cleanly and a deploy has to wait out
  the pod's termination grace period. Catch `Exception`, and let the two control-flow exceptions
  through.

### 💬 Notes
- nit: `normalize_ref()` at `src/utils/refs.py:12` duplicates the block added at
  `src/sync/pull.py:60`.

The other 13 net-new findings are formatting and naming, and they can wait. Dropped 3 as
duplicates of Chargate, Sonar and Brimyr's own findings list. Nothing here sets a status check:
the blocking item above is a judgement, not a second gate, so the merge button is exactly as
green as Brimyr left it. Coverage detail below.

<details>
<summary>Uncovered changed lines</summary>

| File | Lines | What's there |
| --- | --- | --- |
| `src/api/routes/items.py` | 142-144 | the 403 branch |
| `src/api/routes/items.py` | 190 | `__repr__` |

</details>

<!-- agent-skills:findings:v1
{
  "schema_version": 1,
  "skill": "brimyr-quality-review",
  "gate": "brimyr",
  "head_sha": "<HEAD_SHA>",
  "gate_comment_id": 2481019332,
  "gate_source": "comment",
  "gate_result": "pass",
  "patch_coverage": 91.4,
  "covered_lines": 128,
  "total_lines": 140,
  "total_coverage": 74.2,
  "quality_gate_result": "pass",
  "quality_net_new_count": 14,
  "quality_blocking_count": 0,
  "quality_fail_on": "none",
  "verdict": "blocking",
  "duplicates_dropped": 3,
  "findings": [
    {
      "id": "bqr-1",
      "severity": "critical",
      "blocks": true,
      "class": "test-inverted-assertion",
      "path": "src/nievah/worker/sqs_drain.py",
      "line": 87,
      "end_line": 92,
      "title": "Test asserts the opposite of the contract its name states",
      "failure": "A setup failure ends the background task permanently; the test asserts that as correct, so no run will ever go red for it.",
      "fix": "Retry in consume_loop instead of returning, and flip the assertion to match the name.",
      "test_must_assert": "the loop is still running after a setup failure, and that setup was retried",
      "confidence": "confirmed",
      "auto_fixable": true,
      "pre_existing": false
    }
  ]
}
-->
````

The envelope is deliberately identical to the one `chargate-security-review` emits, down to the
`<!-- agent-skills:findings:v1` opener, so `pr-triage` needs **one** parser for both post-gate
reviews. Only `skill`, `class`, and the gate-specific fields differ. Field rules, all binding:

- `skill` is `brimyr-quality-review`, `gate` is `brimyr`, `schema_version` is `1`.
- `verdict` is `blocking` | `advisory` | `clean`: `blocking` if any finding has `blocks: true`,
  `advisory` if there are findings but none block, `clean` if `findings` is `[]`.
- `severity` is `critical` | `high` | `medium` | `low`, matching the prose markers: ⛔ is
  `critical` or `high`, 🟡 is `medium`, 💬 is `low`. `blocks` is `true` only for `critical` and
  `high`, and must agree with `severity` on every entry.
- `class` is the defect kind, one of: `test-no-assertion`, `test-asserts-implementation`,
  `test-over-mocked`, `test-inverted-assertion`, `test-missing-error-path`,
  `test-missing-boundary`, `test-flaky`, `test-cannot-fail`, `duplication`, `mixed-responsibility`,
  `misleading-name`, `speculative-abstraction`, `swallowed-error`, `deferred-dependency`,
  `dead-code`, `stale-comment`, `complexity`, `uncovered-critical-line`. **A finding you
  promoted out of Brimyr's net-new listing (§4d) takes the class that describes the defect** —
  a bare `except` is `swallowed-error`, an unread parameter is `dead-code`. Don't add a class
  for "came from the linter" and never put a rule id in this field; `pr-triage` switches on
  these values and the list is the contract.
- `failure` is the concrete failure in the shape "*this input or state* produces *this wrong
  outcome*", or for a test finding, "*this mutation* leaves the test green" (§1). It is the
  analogue of the security review's `attack` field. Never a restatement of the title.
- `test_must_assert` is the assertion a new or fixed test has to make, or `null` when the finding
  isn't test-shaped. Never fill it with "add a test".
- `auto_fixable` is `true` only when the fix is mechanical and local (move a dependency between
  groups, add the missing assertion, seed the RNG, sort both sides of a comparison). Anything
  needing a design decision is `false`, and `pr-triage` leaves it for a human.
- `confidence` is `confirmed` (you ran the mutation, or traced the path end to end) or `probable`
  (the pattern is there and one link is unverified). Never post a `blocks: true` finding at
  `probable` without saying in the prose which link you couldn't verify.
- `pre_existing` is `true` when the defect sits on code this PR did not introduce (a weak test
  that already covered the lines the diff touched). Report those, but never `blocks: true`.
- `gate_comment_id` is the id of Brimyr's summary comment, or `null` when it posted none. It is
  usually a real id now, so `null` is a claim: it says you looked for the comment and there
  wasn't one. Don't omit the key, and don't leave it `null` on a run where `gate_source` is
  `comment`.
- `gate_source` is `comment` | `check-run` | `action-outputs` | `none`. When it's `none`,
  `patch_coverage`, `covered_lines`, `total_lines` and `total_coverage` are `null` — **never a
  guess** — and `gate_result` is `unknown`.
- `total_coverage` is the overall percentage across the files the run **measured**, or `null`.
  It is not the repository's coverage and is never gated on (§0d), so it is context and never
  supports a finding by itself.
- The four `quality_*` keys mirror the action outputs of the same name and are **all `null` when
  the quality half didn't run** — which is the default, so `null` here is the common case and
  means "off", not "clean". Two rules on them: `quality_gate_result: "error"` means the scan
  didn't complete, and with it set `quality_net_new_count` is evidence of nothing (§4b); and
  `quality_fail_on` is carried even though it looks redundant, because `"none"` is the only
  thing distinguishing a report-only pass from a genuinely clean one.
- `path` is repo-relative, `line` is required and real at `head_sha`, `end_line` only when the
  finding spans a statement.
- `id` is stable across runs for the same defect (`bqr-<n>` in the order they appear), so a
  re-review updates rather than renumbers.
- **Never emit the three characters `-->` inside the JSON.** They close the HTML comment early
  and spill the rest onto the page as visible text. If a quoted snippet contains one, escape
  the `>` as `\u003e` (so the JSON reads `--\u003e`), which `jq` decodes back to the original
  string on the way out.
- `findings` is `[]` on a clean review, and the block is always present — that's how a consumer
  tells "reviewed, nothing found" from "never reviewed".

`pr-triage` reads it back with:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:brimyr-quality-review -->"))) | last) // empty | .body' \
  | sed -n '/<!-- agent-skills:findings:v1/,/^-->/p' | sed '1d;$d' \
  | jq '{verdict, gate_source, blocking: [.findings[] | select(.blocks)] | length,
         fixable: [.findings[] | select(.auto_fixable)] | length}'
```

Run exactly that against your own body **before** you post it. If `jq` errors, the block is
malformed and the whole point of it is lost.

### 7c. When there's nothing to report

Say it plainly and post anyway. The comment is the record that the review ran, and its absence is
indistinguishable from a crashed job:

> ## Quality review
>
> Brimyr passed at 96% patch coverage (48 of 50 changed lines) and reported no net-new quality
> findings. I read the four new tests against the change and couldn't break any of them by hand:
> each one asserts on behaviour, the error branch in `pull.py` has its own case, and the two
> uncovered lines are a `__repr__` and a re-export. Nothing to fix here.

If the quality half reported findings and you judged that none of them matter here, say that
too, with the count: "Brimyr reported 6 net-new findings, all formatting, and I'd leave them."
A silent zero and a triaged six look identical to a reader, and only one of them is work you did.

`findings` stays `[]` and `verdict` is `clean` in the block, which is exactly how a consumer
tells "reviewed, nothing found" from "never reviewed". Don't manufacture a nit so the comment
looks like work.

### 7d. Post or patch

```bash
if [ -n "$PRIOR" ]; then
  gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$PRIOR" \
    -F body=@.git/brimyr-quality-review.md -q '"updated " + .html_url'
else
  gh api --method POST "repos/$OWNER/$REPO/issues/$PR/comments" \
    -F body=@.git/brimyr-quality-review.md -q '"posted " + .html_url'
fi

rm -f .git/bqr-files.jsonl
```

Pass the body with `-F body=@<file>` (or build the payload with `jq -n --rawfile body <file>
'{body: $body}'` and `--input` it). Never hand-escape Markdown into a shell string — that's where
a stray backtick or newline turns into a mangled comment or a 422.

**One call. Once the PATCH or POST returns a URL, you are done** — don't re-post to "double-check",
don't add a follow-up. If it fails, re-run §7a first: check whether your comment landed anyway
before you try again, so a retry can never become a second comment.

---

## 8. Verify before you report

Do this pass **before** writing the body, on every finding, and delete the ones that fail it. The
credibility of the whole comment is set by its weakest line.

1. **The file and line are real at `head_sha`.** Not approximately, exactly:

   ```bash
   git show "$HEAD_SHA:<path>" | sed -n '<line>p'
   ```

   If that prints something other than what your finding describes, your line number is stale
   (usually from reading the pre-merge file rather than the head). Fix it or drop the finding.

2. **The quoted code is quoted, not paraphrased.** A test name, an assertion, a dependency group
   — copy it. Never reconstruct one from memory.

3. **Every claim about the gate traces to §0.** A percentage you didn't read is not a percentage.
   `gate_source: none` means the numbers are `null`.

4. **Every finding names a concrete failure**, in the shape "*this input / this state* produces
   *this wrong outcome*", or, for a test finding, "*this mutation* leaves the test green". If you
   can't write that sentence, it isn't a finding.

5. **No invented flags, markers, outputs or API shapes.** Brimyr's action outputs are `mode`,
   `gate_result`, `patch_coverage`, `covered_lines`, `total_lines`, `total_coverage`,
   `quality_gate_result`, `quality_net_new_count`, `quality_blocking_count`, `quality_fail_on`
   (§0d, which also lists the few extra names the step writes but the action doesn't export).
   `quality_fail_on` takes `none` | `note` | `warning` | `error` | `any`, and **never** a
   severity band (§4c). Its markers are `<!-- brimyr:pr-summary -->` for the consolidated
   comment and `<!-- brimyr:quality-summary -->` for a standalone `brimyr lint` run, and on a
   repo with `pr_comment: 'false'` it emits neither. Its two comment headings are
   `## Brimyr: Quality Assurance` and `## Brimyr: Net-new findings`. Chargate's markers are
   `<!-- chargate:pr-summary -->` and `<!-- chargate:finding -->`. That's the whole list.
   Anything else you'd like to exist, doesn't.

6. **No padding.** Three real findings beat three real ones plus five nits. Every line you add
   that the reader can dismiss makes the ⛔ above it easier to dismiss too.

7. **The machine-readable block parses, and its counts match the prose.** Run the §7b reader
   against your own body before posting. `verdict` must follow from `blocks`, the number of
   `blocks: true` entries must equal the bullets under ⛔, and `duplicates_dropped` must equal the
   number you state in the prose.

---

## 9. Report back

Be idempotent about it: if a comment on this `head_sha` with these findings already exists, say so
and stop rather than patching it with an identical body.

Otherwise end with:

- **Where the gate figures came from** (`comment` / `check-run` / `action-outputs` / `none`) and
  what they were, for **both** halves. If Brimyr posted no comment, lead with that — it's the
  most likely thing a reader will otherwise assume you missed. If the quality half didn't run,
  say "not enabled" or "scan didn't complete" and never "no findings" (§0e).
- **What you did with the net-new quality findings**: how many there were, how many you promoted,
  and one line on why the rest can wait. A count with no triage behind it is the state this
  section exists to end.
- A short table: **severity → `file:line` → dimension → finding → the assertion or fix required.**
- **How many duplicates you dropped**, and against which source.
- **What you reviewed shallowly and why** — a generated file, a large fixture, a section you
  couldn't check because no coverage report was reachable (§3c), a findings listing truncated at
  the 20-entry cap (§4a). No silent truncation: a section you skipped must be named as skipped.
- Whether the mutation probe ran executed (tier 2) or static (tier 1), and confirmation the tree
  is clean if you mutated anything.
- Any judgement call, so a human can weigh it: a severity you were torn on, a duplicate you kept
  because you were extending it, an assumption about intent.
- The comment URL, and the one next action — `pr-triage` picks up the `auto_fixable` findings from
  the machine-readable block; the rest need the author.
