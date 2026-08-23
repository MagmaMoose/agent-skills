# Brimyr quality review workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

You run **after Brimyr has finished**. Brimyr is a **patch-coverage gate**: it measures the
fraction of the lines this PR changed that the test suite executed, and it fails when that
fraction falls below the threshold (80% by default). It never gates on pre-existing uncovered
code. Alongside the gate it runs `sonar-scanner` for the quality trend, non-blocking. Its
action outputs are `mode`, `gate_result` (`pass` | `fail` | `error`), `patch_coverage`,
`covered_lines`, and `total_lines`.

That is the entirety of what Brimyr knows: **a number**. Your job is everything the number
cannot see.

**100% patch coverage means every changed line was executed. It does not mean a single one of
them was checked.** A test that calls the function and asserts nothing scores exactly the same
as a test that pins the contract. A test that mocks the dependency it exists to exercise scores
the same as one that would notice if that dependency were deleted. A test whose name promises
one behaviour and whose assertion enshrines the opposite scores the same as a correct one, and
it is worse than having no test at all, because it reads as a guarantee. Coverage is a
lower bound on effort and says nothing about a bound on risk. That gap is this workflow's
entire subject matter.

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

## The hardest rule in this repo, restated for a coverage gate

`shared/pr-triage.md` §2a says: never suppress a finding that is real, and a green gate bought
that way is worse than a red one. The coverage-gate form of that rule has two halves, and both
are yours:

1. **Never soften, downgrade, or drop a real finding because Brimyr came back green.** A passing
   percentage is not evidence about any finding you hold. If the tests are theatre, `pass` is the
   symptom, not the refutation.
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
dependency reads, the §7 line verification — degrades to *empty output*, which is
indistinguishable from "found nothing". A silent false-clean is the one failure this whole review
exists to prevent, so read files over the API instead and say in the report that you did:

```bash
gh api "repos/$OWNER/$REPO/contents/<path>?ref=$HEAD_SHA" \
  -H 'Accept: application/vnd.github.raw'
```

That returns the file verbatim on stdout and is a drop-in replacement for `git show
"$HEAD_SHA:<path>"` in every snippet below. Fork PRs are the common case where you'll need it.

If you do check out, never leave the working tree dirty, never commit, never push.

### b) Find Brimyr's summary comment — by marker, not by author

Two markers are possible. Check both:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | test("<!-- brimyr:(pr|quality)-summary -->")) 
      | {id, url:.html_url, user:.user.login, updated:.updated_at, body}'
```

**Brimyr may not post a comment at all.** On `main` today it does not: there is no
`github_comment.py` in its `src/`, and `<!-- brimyr:pr-summary -->` /
`<!-- brimyr:quality-summary -->` exist only on unmerged branches. So an empty result here is the
*expected* case, not an error, and it is never a reason to stop. Fall through to (c), then (d).

### c) Fall back to the check run

```bash
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" --paginate \
  -q '.check_runs[] | select(.name | test("brimyr|coverage"; "i"))
      | {name, status, conclusion, started:.started_at, url:.html_url,
         title:.output.title, summary:.output.summary}'
```

The conclusion (`success` / `failure` / `neutral`) maps onto `gate_result`, and `output.summary`
is where a job summary lands if the workflow writes one. Read it before going to the log.

### d) Fall back to the action outputs in the workflow run

The outputs are consumed inside the workflow, so the REST API won't hand them to you as a field.
Read them off the run:

```bash
RUN_ID=$(gh run list --branch "$HEAD" --limit 20 \
  --json databaseId,name,headSha,conclusion \
  -q "[ .[] | select(.headSha == \"$HEAD_SHA\") ] | .[0].databaseId")

gh api "repos/$OWNER/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
  -q '.jobs[] | {name, conclusion, url:.html_url}'

gh run view "$RUN_ID" --log \
  | grep -Ei 'gate_result|patch_coverage|covered_lines|total_lines|\bmode\b' | tail -40
```

Take `gate_result`, `patch_coverage`, `covered_lines`, `total_lines` from there. Those four names
are the action's real outputs; don't invent a fifth, and don't quote a number you didn't read.

### e) Record which source you used, and never pretend

Set `gate_source` to exactly one of `comment`, `check-run`, `action-outputs`, or `none`, and say
it in the comment body in plain words. **"There was no Brimyr comment on this PR" is a fact you
report, not a gap you paper over.** If all four fail, Brimyr didn't run against this head at all
(fork PR without secrets, a path filter, a skipped workflow, a queued run). Say that, review
anyway — every dimension below stands on its own without the gate — and note in §5 that the
coverage figures are unavailable rather than guessing at them.

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
        name != "" && /[^ \t]/ && match($0, /[^ \t]/) <= ind { flush() }
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

So a `pass` from Brimyr is where this section starts, not where it stops.

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

The number is context, not a finding (§5). What goes in the comment is: *this* line, *this*
behaviour, uncovered, and here's the assertion that would cover it.

---

## 4. Severity

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
`blocking` / `advisory` / `clean` (§6b). Pick `critical` over `high` when the defect is already
reachable in production rather than only on the next change.

**This comment sets no status check.** A ⛔ here doesn't block the merge button; it's a judgement,
and `pr-triage` acting on it is what closes the loop. Say that plainly in the comment so nobody
reads it as a second gate that has jammed.

**Severity honesty.** The label and the prose must agree. If your text for a 🟡 says the current
code makes the failure "probably fine" and the only failure you can name is hypothetical, it's a
💬. A 🟡 must name either a failure reachable today or missing coverage for non-trivial new logic.
Missing coverage stays 🟡 even though nothing fails today — that's the whole subject here.

And the rule from the top, one more time because this is where it gets tested: **`gate_result:
pass` is not a reason to relabel anything downward.**

---

## 5. Deduplicate against Brimyr and SonarQube

Everything you post must be **additive**. The point of this review is what the gate did not catch.
A finding the gate already reported is a duplicate: suppress it, count it, and say how many you
dropped. A comment that restates the gate is noise, and noise is how a real finding gets skimmed
past.

### 5a. Collect what has already been said

```bash
# Brimyr's own comment, if it exists (§0b) — parse its findings out of the body
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

### 5b. SonarQube

Brimyr runs `sonar-scanner` non-blocking, so Sonar's issues are already on this PR somewhere and
restating them is a duplicate. Read them from whichever of these the environment gives you:

```bash
# project key, from the scanner's own config
git show "$HEAD_SHA:sonar-project.properties" 2>/dev/null | grep -E 'projectKey|organization'

# the PR's issues, when SONAR_HOST_URL / SONAR_TOKEN are in the environment
curl -sS -u "$SONAR_TOKEN:" \
  "$SONAR_HOST_URL/api/issues/search?componentKeys=<projectKey>&pullRequest=$PR&resolved=false" \
  | jq -r '.issues[] | "\(.component):\(.line) [\(.severity)] \(.rule) \(.message)"'

# no credentials? the check run and any SonarQube status carry the headline
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" --paginate \
  -q '.check_runs[] | select(.name | test("sonar"; "i")) | {name, conclusion, title:.output.title, summary:.output.summary}'
gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/status" -q '.statuses[] | select(.context | test("sonar"; "i"))'
```

If none of that resolves, say in the comment that Sonar's issue list wasn't reachable, so a
finding of yours *might* overlap with one of its. That's an honest caveat and it costs one line.

### 5c. The dedup rule

Drop a finding of yours when a gate or an existing thread already names **the same defect at the
same place**: same file, line within ±3 (a scanner and a human anchor differently), and the same
underlying problem. Same *file* alone is not a duplicate — Sonar flagging cognitive complexity on
line 40 doesn't cover your assertion-inversion on line 58.

Keep it, and say why, when you're **materially extending** it: the gate said the function is
uncovered, you can say the uncovered branch is the authz denial and name the assertion. Lead the
finding with what's new, don't re-narrate what the gate said.

**Never restate the coverage percentage as a finding.** `patch_coverage` is context for the first
paragraph of the comment. "Patch coverage is 84%" is not a finding, it's the gate's output, and
repeating it back is the exact noise this section exists to prevent.

Count the drops. `duplicates_dropped` goes in the machine-readable block and one plain sentence
goes in the body: "Dropped 3 as duplicates of Chargate and Sonar." That number is how a reader
knows you looked, and it's how a maintainer notices when the gates and this review start
overlapping enough to retune one of them.

---

## 6. The reply comment — one, idempotent, patched in place

**Exactly one PR issue comment, carrying the hidden marker
`<!-- agent-skills:brimyr-quality-review -->` as its first line.** Find the prior one and `PATCH`
it; `POST` only when none exists. Same find-or-patch pattern Chargate uses for
`<!-- chargate:pr-summary -->`. One comment per PR, forever, rewritten whole on every run.

GitHub issue comments don't thread, so "replying to Brimyr" means: link Brimyr's comment in your
opening line so the two read as a pair. When Brimyr posted nothing, you have nothing to link, and
you say so.

### 6a. Find the prior comment

```bash
PRIOR=$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:brimyr-quality-review -->"))) | last) // empty | .id')
echo "prior comment: ${PRIOR:-none}"
```

Use `last`, not `first`: if a previous run ever double-posted, patch the newest and say in the
report that a duplicate exists so a human can delete the stale one. Never post a third.

### 6b. Write the body

Write it to `.git/brimyr-quality-review.md` with **real newlines** (never the two literal
characters `\n`). Structure:

````markdown
<!-- agent-skills:brimyr-quality-review -->
## Quality review

Brimyr's patch coverage came back at 91.4% (128 of 140 changed lines), over the 80% threshold, so
the gate passed. [Its summary is here](<link to the Brimyr comment, when one exists>). Here's what
the number doesn't cover.

<When no Brimyr comment exists, that first paragraph reads instead:
"Brimyr didn't post a summary comment on this PR, so the figures below come from the check run:
patch coverage 91.4%, gate `pass`." State the source. Never imply a comment you didn't read.>

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

### 💬 Notes
- nit: `normalize_ref()` at `src/utils/refs.py:12` duplicates the block added at
  `src/sync/pull.py:60`.

Dropped 3 as duplicates of Chargate and Sonar. Nothing here sets a status check: the blocking
item above is a judgement, not a second gate, so the merge button is exactly as green as Brimyr
left it. Coverage detail below.

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
  "gate_comment_id": null,
  "gate_source": "check-run",
  "gate_result": "pass",
  "patch_coverage": 91.4,
  "covered_lines": 128,
  "total_lines": 140,
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
  `dead-code`, `stale-comment`, `complexity`, `uncovered-critical-line`.
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
- `gate_comment_id` is the id of Brimyr's summary comment, or `null` when it posted none. That
  `null` is the signal that the gate comment was absent, so don't omit the key.
- `gate_source` is `comment` | `check-run` | `action-outputs` | `none`. When it's `none`,
  `patch_coverage`, `covered_lines` and `total_lines` are `null` — **never a guess** — and
  `gate_result` is `unknown`.
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

### 6c. When there's nothing to report

Say it plainly and post anyway. The comment is the record that the review ran, and its absence is
indistinguishable from a crashed job:

> ## Quality review
>
> Brimyr passed at 96% patch coverage (48 of 50 changed lines). I read the four new tests against
> the change and couldn't break any of them by hand: each one asserts on behaviour, the error
> branch in `pull.py` has its own case, and the two uncovered lines are a `__repr__` and a
> re-export. Nothing to fix here.

`findings` stays `[]` and `verdict` is `clean` in the block, which is exactly how a consumer
tells "reviewed, nothing found" from "never reviewed". Don't manufacture a nit so the comment
looks like work.

### 6d. Post or patch

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
don't add a follow-up. If it fails, re-run §6a first: check whether your comment landed anyway
before you try again, so a retry can never become a second comment.

---

## 7. Verify before you report

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

5. **No invented flags, markers, outputs or API shapes.** Brimyr's outputs are `mode`,
   `gate_result`, `patch_coverage`, `covered_lines`, `total_lines`. Its markers are
   `<!-- brimyr:pr-summary -->` and `<!-- brimyr:quality-summary -->`, and it may emit neither.
   Chargate's are `<!-- chargate:pr-summary -->` and `<!-- chargate:finding -->`. That's the whole
   list. Anything else you'd like to exist, doesn't.

6. **No padding.** Three real findings beat three real ones plus five nits. Every line you add
   that the reader can dismiss makes the ⛔ above it easier to dismiss too.

7. **The machine-readable block parses, and its counts match the prose.** Run the §6b reader
   against your own body before posting. `verdict` must follow from `blocks`, the number of
   `blocks: true` entries must equal the bullets under ⛔, and `duplicates_dropped` must equal the
   number you state in the prose.

---

## 8. Report back

Be idempotent about it: if a comment on this `head_sha` with these findings already exists, say so
and stop rather than patching it with an identical body.

Otherwise end with:

- **Where the gate figures came from** (`comment` / `check-run` / `action-outputs` / `none`) and
  what they were. If Brimyr posted no comment, lead with that — it's the most likely thing a
  reader will otherwise assume you missed.
- A short table: **severity → `file:line` → dimension → finding → the assertion or fix required.**
- **How many duplicates you dropped**, and against which source.
- **What you reviewed shallowly and why** — a generated file, a large fixture, a section you
  couldn't check because no coverage report was reachable (§3c). No silent truncation: a section
  you skipped must be named as skipped.
- Whether the mutation probe ran executed (tier 2) or static (tier 1), and confirmation the tree
  is clean if you mutated anything.
- Any judgement call, so a human can weigh it: a severity you were torn on, a duplicate you kept
  because you were extending it, an assumption about intent.
- The comment URL, and the one next action — `pr-triage` picks up the `auto_fixable` findings from
  the machine-readable block; the rest need the author.
