# PR triage workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

You are triaging and resolving **all actionable review feedback** on a pull request,
end to end: read every comment, fix the code, commit, reply in-thread, then resolve
the thread. Work through threads **one at a time** so each fix, reply, and resolve
stays correctly paired. **The end state is a PR the user can merge without touching
anything** — branch synced with base, all threads resolved, CI green, nothing left
but the review-and-merge click.

**Run fully autonomously — do not ask the user anything.** No clarifying questions,
no "would you like me to…", no stopping for approval. When something is ambiguous,
make the best-judgment decision, act on it, and record the call (and your reasoning)
in the final report and, where relevant, in the in-thread reply. The only thing that
ends the run is finishing the work or a hard external blocker you cannot resolve in
code (e.g. a protected-branch remote rejection) — and even then you report it, you
don't ask a question.

**Obey commit/push hooks — fix, don't bypass.** Pre-commit and pre-push hooks are
there on purpose. If a hook fails, read its output and **fix the underlying problem**
(run the formatter and re-stage, fix the lint error, fix the failing test, etc.), then
re-run the commit/push. Loop until it passes cleanly. Use `--no-verify` **only as a
genuine last resort** — when the failure is something you truly cannot fix in code and
is irrelevant to correctness (the canonical case: a branch-*name* convention hook
firing on the pre-existing PR branch you checked out, which you must not rename). When
you do bypass, say so and why in the report.

**Presentation.** Replies and commit messages read as an engineer's work, not as tool
output: no robot emojis, no "AI-generated" branding, and **never any attribution footer**
("Generated with …", "Fixed by …", co-author tags) on comments, replies, or commits.

Target PR: the PR input supplied by the invoking agent (if empty, use the PR for the current branch).

---

## 0. Resolve the PR and repo coordinates

```bash
# PR number: explicit arg, else the PR for the current branch
gh pr view "$ARGUMENTS" --json number,headRefName,headRepositoryOwner,baseRefName,url 2>/dev/null \
  || gh pr view --json number,headRefName,headRepositoryOwner,baseRefName,url
```

From that, capture `OWNER`, `REPO`, `PR` (number), `HEAD` (head branch), and
`BASE` (`baseRefName` — the branch the PR merges into).
Get owner/repo robustly:

```bash
gh repo view --json owner,name -q '.owner.login + " " + .name'
```

Note the host: this repo may live on **github.com** or **pinkroccade.ghe.com**.
`gh` auto-selects the right host from the remote, so the commands below work as-is.

**Check out the PR head branch** before touching code (skip if you're already on it):

```bash
gh pr checkout "$PR"
git status --porcelain   # if dirty, stash it: `git stash -u`, restore at the end, note it in the report
```

---

## 0b. Sync with the base branch (and resolve any conflicts)

Bring the PR branch **up to date with its base** before triaging — both so the PR is
mergeable when you're done and because a stale/conflicted branch invalidates the very
lines reviewers commented on. Merging base into head is exactly what GitHub's "Update
branch" button does.

```bash
gh pr view "$PR" --json mergeable,mergeStateStatus -q '.mergeable + " / " + .mergeStateStatus'
git fetch origin "$BASE"                       # $BASE = PR base branch from step 0
git merge --no-commit --no-ff "origin/$BASE" 2>&1 || true
git diff --name-only --diff-filter=U            # conflicted files, if any
```

If `git merge` reported **"Already up to date"**, the branch already has the latest
base — nothing to integrate, carry on.

If it merged **cleanly** (no conflicts, changes staged), **keep it** — finalize the
merge so the branch actually carries the latest base, then push (per step 3's rules):

```bash
git commit --no-edit                           # finalize the "Update branch" merge
```

Do **not** `git merge --abort` a clean merge — aborting would leave the branch stale,
which is the opposite of what we want.

If there **are** conflicts, resolve each one yourself:
1. Open every conflicted file; for each `<<<<<<< / ======= / >>>>>>>` hunk, work out
   the intended result by reading **both** sides plus the surrounding code — never
   blindly keep "ours" or "theirs". The goal is code that preserves the intent of
   **both** branches and still honors this repo's `CLAUDE.md` rules.
2. Remove all conflict markers, then `git add` each resolved file.
3. After all are staged: `git diff --cached` to sanity-check, run the relevant
   build/tests/lint if quick, then commit:

   ```bash
   git commit -m "merge: resolve conflicts with $BASE"
   ```

4. If a conflict's correct resolution is genuinely ambiguous, make the best-judgment
   call that preserves both sides' intent and honors `CLAUDE.md` — do **not** ask, and
   do **not** `git merge --abort` away the work. Resolve it, and **flag that specific
   resolution prominently in your final report** (file, what each side did, the call you
   made) so a human can double-check it.

Conflicts can also surface later — when you `git commit` a fix in step 3 onto a
freshly merged base, or if you rebase. Apply this same per-hunk discipline anywhere
markers appear, not just here.

---

## 1. Gather feedback from EVERY source

Pull all of these — bots and humans land in different places:

**a) Review threads (inline code comments — Copilot, code-quality bots, humans).**
This is the primary source and the only one that carries thread IDs + resolution
state, which you need to resolve later. Use GraphQL:

**PAGINATE, AND CHECK THE COUNT.** `reviewThreads(first:100)` silently returns the first
100 and drops the rest — and the ones it drops are the NEWEST, which on a PR that has just
been re-scanned are exactly the threads a scanner posted seconds ago. This is not
theoretical: on a 101-thread PR the unpaginated query reported "100 threads, 0 unresolved"
while two findings sat open. Nothing errors; you simply get a shorter list.

```bash
gh api graphql --paginate -f query='
query($owner:String!, $repo:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first:50) {
            nodes { author { login } body diffHunk path line }
          }
        }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR" > /tmp/threads.json
```

Then assert you actually got them all, because a truncated read is indistinguishable from a
tidy PR:

```bash
jq -s '{fetched: ([.[].data.repository.pullRequest.reviewThreads.nodes[]]|length),
        total:   (.[0].data.repository.pullRequest.reviewThreads.totalCount)}' /tmp/threads.json
# fetched MUST equal total. If it does not, stop and fix the query — do not triage a subset
# and report it as the whole.
```

**b) PR-level review summaries** (a reviewer's overall verdict + body):

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/reviews" --paginate \
  -q '.[] | {user: .user.login, state, body}'
```

**c) Issue-style conversation comments** (top-level PR comments, many bots post here):

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | {user: .user.login, body}'
```

**c2) THE AGENTIC POST-GATE REVIEWS — findings the thread query cannot see.**
`chargate-security-review` and `brimyr-quality-review` run after their gate finishes and
post what the gate did *not* catch. Each posts a **PR issue comment** carrying a hidden
marker of its own:

| Marker | Posted by | Where it lands |
| --- | --- | --- |
| `<!-- agent-skills:chargate-security-review -->` | the security review that runs after Chargate | its own comment, opening on and linking to Chargate's `<!-- chargate:pr-summary -->` comment |
| `<!-- agent-skills:brimyr-quality-review -->` | the quality review that runs after Brimyr | beside the Brimyr gate comment, or standalone — Brimyr does not always post one |

Find them by marker and keep the comment **`id`**; you need it to answer in §2b:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate \
  -q '.[] | select(.body | test("<!-- agent-skills:(chargate-security-review|brimyr-quality-review) -->"))
      | {id, review: (.body | capture("<!-- agent-skills:(?<r>[a-z-]+) -->").r), url: .html_url, body}'
```

**THESE ARE NOT REVIEW THREADS, AND (a) WILL NEVER RETURN THEM.** `reviewThreads` returns
pull-request *review* threads. An issue comment is not a node in that connection: it has no
thread `id`, no `isResolved`, and no `path`/`line`. So the `fetched == total` assertion above
still passes cleanly — it was never counting these — and a triage run that walks only review
threads skips **every** finding these two skills produce, silently, with a full set of
resolved threads and a green-looking summary to show for it. That is the whole trap: the
subset you read and the subset you were told about are both internally consistent.

Source (c) does fetch these comments — it fetches every issue comment — but it does not
distinguish them, and their findings live in an HTML comment rather than in the prose (c)
skims. Pull them by marker, deliberately.

**Read the machine-readable block, not the prose.** Both reviews append their findings to that
same comment as JSON **inside an HTML comment**, so it never renders and never has to be parsed
back out of English:

```
<!-- agent-skills:findings:v1
{
  "schema_version": 1,
  "skill": "chargate-security-review",
  "gate": "chargate",
  "head_sha": "9f148e8b…",
  "gate_comment_id": 1234567890,
  "verdict": "blocking",
  "duplicates_dropped": 2,
  "findings": [
    {
      "id": "csr-1",
      "severity": "critical",
      "blocks": true,
      "class": "authorization",
      "path": "apps/api/server/routes/items.py",
      "line": 42,
      "title": "Item lookup has no tenant predicate",
      "attack": "Any authenticated user can read another org's item by id.",
      "fix": "Add `.where(Item.org_id == current_user.org_id)` to the select.",
      "confidence": "confirmed",
      "pre_existing": false
    }
  ]
}
-->
```

Read it with the same pipeline the review validates it with before posting — the two delimiter
lines are the `agent-skills:findings:v1` opener and the closing `-->`, and `sed '1d;$d'` drops
them:

```bash
gh api "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" -q .body \
  | sed -n '/<!-- agent-skills:findings:v1/,/^-->/p' | sed '1d;$d' \
  | jq -r '.findings[] | [.id, .severity, (.blocks|tostring), (.confidence // "-"),
                          .path + ":" + (.line|tostring), .title] | @tsv'
```

These fields decide how the finding gets handled, and §2b turns each one into an instruction:

| Field | What it changes |
| --- | --- |
| `id` | `csr-<n>` from the security review, `bqr-<n>` from the quality review. Stable across re-runs for the same defect, so it is what you cite when you answer — never renumber it. |
| `blocks` | The review's judgement that this should stop the merge. It is a claim about the code, **not** a CI state. |
| `confidence` | `confirmed` = traced end to end. `probable` = one link in the chain is unverified — the review is telling you exactly which step to check first. |
| `auto_fixable` | **Quality review only, and it is addressed to you.** `true` = the fix is mechanical and local (move a dependency between groups, add the missing assertion, seed the RNG). `false` = it needs a design decision, so you leave it for the author rather than guessing at intent. Absent on security findings; treat a missing `auto_fixable` as unset, not as `false`, and decide it on the merits per §2b. |
| `test_must_assert` | Quality review only. The assertion a new or fixed test has to make. When you fix a test finding, this is the contract to satisfy — a test that goes green without asserting it has not fixed anything. `null` when the finding isn't test-shaped. |
| `pre_existing` | `true` means the finding sits on code this PR did not introduce, so §2a's pre-existing rule applies: decide the scope before you widen the diff. |
| `duplicates_dropped` | How many candidate findings the review discarded because its gate already reported them. Non-zero is the additive design working, not findings going missing. |
| `head_sha` | The commit the review actually read. See the staleness check below — this one is a precondition, not a detail. |
| `gate_comment_id` / `gate_source` | Where the review got the gate's own result. `gate_comment_id: null` with `gate_source: "none"` means **the gate posted no comment and the review said so honestly** — Brimyr posts one only when the calling workflow sets `pr_comment: 'true'`, which is not the default. That is a degraded-but-valid review, not a failure, and the coverage numbers beside it will be `null` rather than guessed. Carry that distinction into the §6 report; do not report it as a broken review. |

**Check `head_sha` before you act on a single line number.** There is exactly one of these
comments per review per PR, forever, PATCHed in place — so the comment you just read is not
necessarily about the code you have checked out. If the author pushed after the review ran,
the block still carries the *old* `head_sha`, and every `path:line` in it points into a commit
that is no longer HEAD. Acting on it edits whatever now happens to sit at that line number:

```bash
BLOCK_SHA=$(… | jq -r '.head_sha')          # from the extraction above
HEAD_SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
[ "$BLOCK_SHA" = "$HEAD_SHA" ] && echo "current" || echo "STALE: reviewed $BLOCK_SHA, head is $HEAD_SHA"
```

When it is stale, do **not** discard the findings and do not trust their line numbers. Re-locate
each one by reading the code the `title` and `path` describe, exactly as §2b step 1 requires
anyway, and say in the report that you matched them against a newer commit than the review
read. A finding whose code the later push already fixed is `fixed` in the ledger — say by which
commit — not silently dropped. If the review is still running against the new push, its next
PATCH will supersede what you read; note that too rather than racing it.

`"findings": []` is a real answer — *reviewed, nothing to add* — and it is a different claim
from a missing block. If the comment is present but the block is absent or `jq` cannot parse
it, treat it as malformed: read the prose instead and say in the report that the block did not
parse. **Never read a parse failure as a clean review.**

If a marker appears on more than one comment, the **last** one is live and the earlier is a
stray from a run that failed to PATCH. Answer the last, and note the stray in the report.


**d) GitHub Advanced Security — code scanning alerts on this PR's branch**
(GHAS / CodeQL findings; ignore 403/404 if GHAS isn't enabled):

```bash
gh api "repos/$OWNER/$REPO/code-scanning/alerts?ref=refs/heads/$HEAD&state=open" --paginate \
  -q '.[] | {number, rule: .rule.id, severity: .rule.severity, path: .most_recent_instance.location.path, line: .most_recent_instance.location.start_line, message: .most_recent_instance.message.text}' \
  2>/dev/null || echo "no code-scanning access / none open"
```

**d2) FAILING CHECKS — findings that never got a thread.**
Do not treat the threads as the complete list. Inline review comments are capped (GitHub
502s past roughly 40, and scanners self-limit), so a scanner with 44 findings may open a
dozen threads and report the rest only in its summary comment and its SARIF artifact.
Triaging threads alone therefore ends with every thread resolved and the gate still red —
which reads, from the outside, exactly like a job well done.

```bash
gh pr checks <PR>                       # which gates are red
gh run view <run-id> --log-failed | grep -E 'BLOCKING|net-new'
gh pr view <PR> --json comments -q '.comments[].body' | grep -A200 'chargate:pr-summary'
```

Reconcile the two: every finding in the summary must end up fixed or suppressed, whether
or not it ever had a thread. See §2a for how, and for why the usual suppression attempts
fail silently.

**e) Dependabot / secret-scanning alerts** — only if the feedback references them;
otherwise skip. (`gh api repos/$OWNER/$REPO/dependabot/alerts`.)

Build a single triage list. For each item record: source, file:line, what it's
asking for, and — for review threads — the **thread `id`** and `isResolved`. For an agentic
finding from (c2) there is no thread, so record the **comment `id`** and the **finding `id`**
instead: those two are what you cite when you answer it.

---

## 2. Decide what's actionable

Skip a thread (do **not** fix/resolve it) when:
- `isResolved` is already `true`.
- It's pure praise, a question with no code change requested, or already addressed
  by an existing commit on the branch.
- Acting on it would contradict this repo's `CLAUDE.md` hard rules or change intent
  beyond the comment's scope.

For anything you skip that a human might expect to be handled, note it in your final
summary with a one-line reason — don't silently drop it.

### 2a. Security scanner findings — get the gate green, and verify that you did

A scanner finding that is a required CI gate is not handled by replying "false
positive". The check stays red and the PR stays blocked. You must either FIX it or
SUPPRESS it in a form the scanner actually honours — and then prove the count went
down, because **every common failure here is silent**.

**First: get the authoritative list, not the threads.**
Inline review comments are capped (GitHub 502s past ~40, and scanners self-limit), so
the threads are a SUBSET. Triaging only what has a thread leaves the gate red while
every thread reads as resolved. In order of preference:

```bash
# 1. The scanner's own summary comment — the complete net-new list
gh pr view <PR> --json comments -q '.comments[].body' | grep -A200 'chargate:pr-summary'
# 2. The full SARIF, uploaded as a run artifact
gh run download <run-id> -n chargate-sarif && jq -r '.runs[].results[] | .ruleId + ": " + .message.text' full.sarif
# 3. The job log — the gate line says exactly what is blocking
gh run view <run-id> --log-failed | grep -E 'BLOCKING|net-new'
```

**Know what the gate counts.** Chargate blocks on **net-new** only:
`BLOCKING 44 net-new finding(s) (fail_on=any)` alongside `1982 pre-existing, never
blocking` and `30 suppressed (accepted in-source, never blocking)`. So the target is
net-new → 0, reachable by fixing or by an accepted in-source suppression. Pre-existing
findings are NOT yours to clear in a feature PR.

**The rule ID tells you which scanner owns it — and only that scanner's syntax works.**
Chargate runs several scanners at once, and a suppression aimed at the wrong one is a
no-op that looks exactly like a fix:

| Rule ID looks like | Scanner | Suppression | Placement |
| --- | --- | --- | --- |
| `CKV_AWS_28`, `CKV2_AWS_16` | Checkov | `#checkov:skip=<id>:<reason>` | **INSIDE** the resource block |
| `AVD-AWS-0089`, `AWS-0089` | Trivy | `#trivy:ignore:<id>` | line above the resource |
| a UUID (`baee238e-…`) | KICS | `# kics-scan disable=<uuid>` | **file line 1, column 0** |
| dotted path (`terraform.aws.security.…`) | Semgrep | `# nosemgrep: <id>` | on or above the flagged line |
| `CKV_*` in a `kics-scan` line | — | **NOTHING. KICS does not know Checkov IDs.** | — |

That last row is a real defect found in the wild: a commit added
`# kics-scan disable=CKV_AWS_273,CKV_AWS_40` to suppress two Checkov rules. KICS ignored
the unknown IDs, Checkov never saw a skip, and both rules kept blocking — while the diff
read as though the finding had been handled.

**Placement is the second silent failure.** In the same repo, 42 correctly-formed
`#checkov:skip=` comments sat immediately ABOVE their `resource` blocks instead of inside
them. Checkov honours a skip only within the block it applies to, so all 42 were inert and
every rule still fired. Copy placement from a suppression you have CONFIRMED works — not
from one that merely exists.

**NEVER SUPPRESS A FINDING THAT IS REAL.** This is the one rule in this section that is
not a preference. Suppression records a judgement that the control does not apply *here*;
using it to quieten a scanner that has correctly spotted a weakness ships that weakness
with a comment asserting it is fine, and the next person reads the comment instead of the
code. A green gate bought that way is worse than a red one, because the red one was still
telling the truth.

Decide per finding, in this order, and never skip to 3:

1. **Fix it** if the control applies and the fix is available. Many cost nothing and are
   straightforwardly right: SQS SSE (`sqs_managed_sse_enabled = true`), SNS encryption with
   the AWS-managed key, S3 `abort_incomplete_multipart_upload`, a log retention period.
   Default here. If you can fix it, fixing it is the answer.
2. **Suppress** only when the control genuinely does not apply to this design, or when the
   only fix costs real money on an account where that matters. "Lambda must be in a VPC"
   does not apply to a function whose entire job is receiving public webhooks. A KMS CMK,
   cross-region replication, PITR or a NAT gateway all carry a real bill — on a
   personally-funded account that is a legitimate reason, *stated as the reason*.
3. **Leave it red** when the finding is real and you cannot fix it within the scope of this
   PR. Do not suppress it to finish the job. Say so in the summary, name the finding and
   what fixing it would take, and let a human decide. An honest red gate is a correct
   outcome of triage; a suppressed real finding is a defect you introduced.

If you cannot tell which of the three applies — the finding is real but you are unsure the
control fits the architecture — treat it as 3 and escalate. Uncertainty is not a licence to
suppress.

Write the reason for a human reading it in a year: what the resource is, why the control
does not apply, and — if cost is the reason — say cost. `#checkov:skip=CKV_AWS_28:PITR off
deliberately — every row is a 24h-TTL delivery id, nothing worth restoring` is a good
reason: it names the data and why losing it is acceptable. "false positive" is not a
reason; it is a label, and usually an untested one.

**Verify against the scanner, never by eye.** This is the whole point of the section: a
misplaced or misaddressed suppression produces no error, no warning, and no diff you can
spot. After pushing, re-read the gate line and confirm the net-new count actually dropped:

```bash
gh pr checks <PR> --watch
gh run view <run-id> --log-failed | grep -E 'BLOCKING|net-new by severity'
```

If the count did not move, the suppression is not being honoured — change the form or the
placement and push again. Do not reply and resolve while the gate is still red.

Never dismiss a security alert through the API (`PATCH … state=dismissed`) —
dismissal is a human judgment call. Always fix or suppress inline.

### 2b. Agentic post-gate findings — reasoned, not matched

The findings from `chargate-security-review` and `brimyr-quality-review` (source c2) are a
different kind of object from everything in 2a, and the difference decides how you handle
them. A scanner finding is **a pattern that matched**: it has a rule id, a scanner that owns
it, a suppression syntax that scanner honours, and a re-run that proves the count moved. An
agentic finding is **a claim somebody reasoned to**. There is no rule id, nothing to suppress,
and no scanner to re-run for confirmation. The only confirmation that exists is you, reading
the code the finding names and deciding whether the failure it describes is real.

**So the verification burden goes UP, not down.** A scanner is dumb but honest: it matched or
it did not, and when it is wrong it is wrong in a shape you learn to recognise. A reasoned
finding can be **confidently, fluently wrong** — right about the file, right about the
function, wrong about the one caller that already makes it safe — and it reads exactly like
the correct findings sitting next to it. Fluency is not evidence. Treat each one as a
hypothesis with a named failure, and reproduce the reasoning before you change a line:

1. Open the `file:line` it names and read the surrounding code — the code, not the snippet
   quoted in the comment.
2. State the failure concretely to yourself: which input, which path, which state, and what
   goes wrong at the end of it. If you cannot fill those in, you have not reproduced it yet
   and you are about to edit code on someone else's confidence.
3. Look for the thing that would defeat it — the guard upstream, the type that cannot hold
   that value, the caller that already validated. This is the step that catches a confidently
   wrong finding, and it is the step that gets skipped. When `confidence` is `probable` the
   review has already named the link it could not verify: start there, because that is where
   it will be wrong if it is wrong.

Then decide, in this order, and never skip to 3:

1. **Fix it** when the reasoning holds. Minimal and correct per §3, same as any other item.
   Default here, exactly as in 2a. This is the half of the job the reviews are handing you:
   they find, you fix. Where the finding carries `auto_fixable: true`, the review has already
   judged the fix mechanical and local, and `test_must_assert` names the assertion the result
   has to make — satisfy that, not merely the test runner. `auto_fixable: false` is the review
   saying the fix needs a design decision it did not want to make for you: that one becomes
   `open` in the ledger with the decision spelled out, **not** a rejection and not a guess.
   The flag narrows *how* you fix, never *whether* the finding is real — a `false` on a
   `blocks: true` finding still leaves a blocking finding on the PR.
2. **Reject it in writing** when the reasoning does not hold — and name **the step that
   fails**, not the conclusion. "Not exploitable" is not a rejection, it is a label;
   "`handler()` is only reachable from `dispatch()`, which rejects any payload without a
   verified signature at line 44" is a rejection, because it can be checked and it can be
   proved wrong. You are making a claim about the code, so write it to survive someone who
   disagrees reading it.
3. **Leave it open** when you cannot tell. Say what you could not determine and what would
   settle it. Uncertainty is not a licence to close a finding, exactly as it is not a licence
   to suppress one.

**NEVER CLOSE A REAL FINDING TO MAKE A GATE GREEN.** The rule from 2a carries over unchanged,
and here it is *easier* to break: suppressing a scanner finding at least leaves a comment in
the diff with a rule id on it, which a human can grep for and audit later. Talking down an
agentic finding leaves **no artefact at all** — no line in the diff, no id, nothing to search
for, just a paragraph of confident prose in a comment. The written rejection is the
entire audit trail. That is why it has to name the step that fails.

**Do not make a change whose only purpose is to close the finding.** A defensive `if` added
around code that was already correct, a `# type: ignore`, a test loosened until it passes —
these end the conversation without ending the disagreement, and they are worse than the
rejection you did not write, because now the code carries a scar that implies a bug was
there. If the finding is wrong, say it is wrong. Pushing back in the comment is a valid and
expected outcome of this section; a cosmetic edit is not.

**`blocks` is a judgement, not a check.** `blocks: true` in the findings block records the
reviewing skill's view that the finding should stop the merge. It is a claim about the code,
not a CI state — read `gh pr checks` (§2a) for what is actually red. The two point opposite
ways more often than you would expect: a `blocks: true` finding on a fully green PR is the
**normal** case, because these reviews exist precisely to report what the gate could not see.
**A green gate is not an argument against the finding.** The envelope's `verdict` says the same
thing at comment level; neither field turns a check red by itself, and neither is negotiable
because a check is green.

**A duplicate is one finding, not two.** Both reviews are additive by construction — they drop
anything their gate already reported, and say how many in `duplicates_dropped`. If you
nonetheless see the same defect from both the gate and the review, it is one defect. Fix it
once, answer it in both places (the scanner's thread or gate line, and the review comment),
and count it once in the report — do not fix it twice, and do not let the second copy read as
an unhandled finding.

**Answer the review's comment — never edit the gate's.** `<!-- chargate:pr-summary -->`
belongs to Chargate, which finds that comment by that marker and PATCHes it on every
subsequent run. Anything you write into it survives until the next scan and then vanishes
without trace, including your rejection of a finding, which is the one thing a human comes
looking for later. Write only into the `agent-skills:` marker'd comment, or into a new
comment of your own. The block's `gate_comment_id` is there so you can link the gate comment,
not so you can write into it.

**How to answer — there is no thread here to resolve.** Nothing in (c2) has a GraphQL thread
`id`, so §4's `addPullRequestReviewThreadReply` and `resolveReviewThread` do not apply to it.
Answer by **PATCHing the same marker'd comment** you found in c2: read its body, append a
response section, write the whole thing to a file, and send the file. Keep **both** blocks
byte-for-byte intact, for two different reasons: the skill marker is how the review finds this
comment on its next run, so mangling it buys a duplicate comment instead of an updated one;
and the `agent-skills:findings:v1` block is how the *next* triage run reads the findings, so
mangling that buys a run that sees a malformed block and, per the rule above, has to treat it
as unread. Your ledger goes between the prose and the findings block, leaving that block last
where both the review and the next triage run expect to find it. Rewrite neither.

```bash
COMMENT_ID=…    # from c2
gh api "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" -q .body > .git/answered-body.md
# append your ledger below the prose, above the findings block, then:
gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" \
  -F body=@.git/answered-body.md -q '"updated " + .html_url'
```

`-F body=@<path>` sends the file's contents as the field value, so Markdown, code fences and
the JSON block all survive without hand-escaping — the same reason the reviews post that way.

If the token cannot PATCH a comment it does not own (403 — likely whenever the review posted
as a different identity from the one triaging), post your own comment instead, linking back to
the original by its `html_url` and citing the same finding ids. **That fallback comment is
itself idempotent**, by the same rule the reviews follow: give it the marker
`<!-- agent-skills:triage-answer -->`, and on every later run find that comment and PATCH it
rather than posting again. Without the marker a PR that gets triaged three times collects
three answer comments, each one a stale copy of the last:

```bash
# .git/answer.md must contain the line <!-- agent-skills:triage-answer --> ; then:
PRIOR=$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:triage-answer -->"))) | last) // empty | .id')

if [ -n "$PRIOR" ]; then
  gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$PRIOR" \
    -F body=@.git/answer.md -q '"updated " + .html_url'
else
  gh api --method POST "repos/$OWNER/$REPO/issues/$PR/comments" \
    -F body=@.git/answer.md -q '"posted " + .html_url'
fi
```

One comment per PR either way — find, then PATCH, else POST. Never a second comment in one
run, and never a fresh comment on a re-run.

Either way the answer is a per-finding ledger, and **every finding id appears in it**:

| Finding | Action | Detail |
| --- | --- | --- |
| `csr-1` | fixed | `4f2a91c` — tenant predicate added to the select |
| `csr-2` | rejected | unreachable: `dispatch()` verifies the signature at line 44 before any call |
| `csr-3` | open | needs the retry semantics decided; flagged in the summary |

Nothing is left unanswered. A finding you neither fixed nor rejected is `open` — said out
loud, in the ledger, and again in the final report under §6 next to anything you left red.
Silence on a finding is indistinguishable from having missed it.

**A ledger written into the review's comment is not durable.** The review PATCHes that body
whole on its next run, so your ledger goes with it — and the entries it erases are precisely
the ones with no other trace: a `rejected` finding leaves nothing in the diff to grep for
(that is the §2b point about the written rejection being the entire audit trail), and an
`open` one leaves nothing at all. So whenever the ledger contains a `rejected` or an `open`
entry, also write it to your own `<!-- agent-skills:triage-answer -->` comment, by the
find-then-PATCH-else-POST block above — the same one comment, patched, not a second per run.
Nobody else rewrites that comment, so it survives the next review run. The §6 report remains
the copy of record; this is what a human finds on the PR six weeks later.

If a comment is **ambiguous or opinionated**, do not ask — make the most reasonable
interpretation, implement it, and state the assumption you made in the in-thread reply
(step 4) and in the summary. Resolve the thread as normal. Only leave a thread
**unresolved** when you genuinely could not act on it in code (e.g. it needs a product
decision or external context unavailable to you); in that case reply explaining what's
blocking and flag it in the summary — still without asking the user a live question.

---

## 3. Fix the code — one thread at a time

For each actionable item:
1. Read the file and surrounding context (`diffHunk` shows what the reviewer saw).
2. Make the **minimal, correct** edit that addresses the comment. Honor the repo's
   `CLAUDE.md` conventions (e.g. for this stack: SQLAlchemy 2.0 style, Pydantic v2,
   uv/pnpm/Ruff only). Don't reformat unrelated lines.
3. If tests/lint exist and are quick, run the relevant ones for the file you touched.

**Commit per logical fix** (or per thread) so history maps to feedback. Conventional
Commit style, referencing the source:

```bash
git add -A
git commit -m "fix: <what changed> (addresses review comment from <author>)"
```

**If a pre-commit hook fails the commit, fix what it flagged and re-commit.** Read the
hook output: if it auto-formatted/auto-fixed files, just `git add -A` and re-run the
commit; if it reported lint errors or a failing check, fix the underlying code, re-stage,
and commit again. Loop until the commit succeeds with hooks passing. Do **not** reach for
`--no-verify` to get past a fixable failure.

**Push after committing — don't leave commits local.** The point of this command is
to close out PRs fast, so push as you go (or at the latest right before you reply/resolve
threads in step 4, since replies reference commit SHAs that must be visible on the remote):

```bash
git push                              # branch already tracks a remote
# first push of a new branch:
git push -u origin "$(git branch --show-current)"
```

If you're in a git worktree, `git push` from **this** worktree — that's where the
commits are. You always push to the PR's own branch — the one you ran `gh pr checkout`
on — never a renamed or new branch.

**Pre-push hook fails → fix the cause, same as commit hooks.** If the push is rejected
by a hook for something you can fix (lint, formatting, tests, a security/secret check),
fix it, commit, and push again. Bypassing with `--no-verify` is the **last resort**, only
when the failure is genuinely unfixable in code *and* irrelevant to correctness.

The one standing exception: a **branch-name convention** pre-push hook (e.g.
`<type>/<description>`) firing on the pre-existing PR branch you checked out. You must not
rename that branch (it's the PR's branch), and its name doesn't affect code — so here, and
only here, retry once with `--no-verify` and note in the report that you bypassed the
branch-naming hook because the PR branch pre-exists:

```bash
git push --no-verify                  # last resort: only for the unfixable branch-naming hook
```

For a **remote** rejection: a non-fast-forward (someone else pushed) → `git pull --rebase`
then push, resolving any conflicts per step 0b. A protected branch that refuses the push
outright is a hard blocker — report the exact error in your summary and move on; don't ask.
Never announce "not pushed yet, run git push when ready" — that defeats the purpose.

---

## 4. Reply in the thread, then resolve it

**Reply** to the specific thread with a short note on what you did (commit SHA helps).
Use the thread's GraphQL `id` from step 1:

```bash
gh api graphql -f query='
mutation($threadId:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}) {
    comment { id url }
  }
}' -f threadId="$THREAD_ID" -f body="Fixed in <sha> — <one-line what/why>."
```

**Then resolve** that same thread:

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { id isResolved } }
}' -f threadId="$THREAD_ID"
```

For feedback that isn't a review thread (PR-level review body, issue comment, GHAS
alert) there's no thread to resolve — instead leave **one** top-level PR comment
summarizing how each was handled. For GHAS alerts, **fix the code** so the alert clears
on the next scan; never dismiss an alert (don't `PATCH … state=dismissed`) — dismissal
is a human judgment call, so the default is always to fix, not dismiss.

---

## 5. Leave the branch ready to review and merge

The goal is that the user does **nothing but review and click merge**. Before reporting,
make sure the PR is in that state:

1. **Re-sync with base** one more time in case it advanced while you worked, and push:

   ```bash
   git fetch origin "$BASE"
   git merge --no-edit "origin/$BASE"   # resolve any conflicts per step 0b, then push
   git push                              # per step 3's hook/last-resort rules
   ```

2. **Confirm everything is pushed** — `git status` shows nothing ahead of the remote,
   and the local branch tip matches `origin/<branch>`.

3. **Confirm the PR is mergeable** and all threads are handled:

   ```bash
   gh pr view "$PR" --json mergeable,mergeStateStatus,reviewDecision \
     -q '"mergeable=" + (.mergeable//"?") + " state=" + (.mergeStateStatus//"?") + " review=" + (.reviewDecision//"none")'
   ```

   Aim for `mergeable=MERGEABLE` and a clean `mergeStateStatus` (`CLEAN`, or `BLOCKED`
   only because a required human review is still pending — which is the user's job, not
   yours). If it's `DIRTY` (conflicts) or `BEHIND`, you didn't finish — go back and fix
   it. If CI is required and you can see it failing on your commits, **fix the failure**
   (same fix-don't-bypass discipline) and push again; don't leave a red PR.

4. **Confirm every agentic finding from (c2) is answered.** These do not appear in
   `mergeable`, in `reviewDecision`, or in any check — a `blocks: true` security finding sits
   on a fully green PR by design (§2b), so steps 1-3 above can all pass with one wide open.
   Re-read the findings blocks and check every `id` against your ledger:

   ```bash
   # per review comment id from c2:
   gh api "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" -q .body \
     | sed -n '/<!-- agent-skills:findings:v1/,/^-->/p' | sed '1d;$d' \
     | jq -r '[.findings[] | select(.blocks)] | "blocking=\(length) ids=\([.[].id]|join(","))"'
   ```

   Every id it prints must be `fixed` or `rejected` in the ledger. **If any is still `open`,
   the PR is not ready to merge** — whatever `mergeStateStatus` says. Do not report it as
   ready. Say plainly that a blocking finding is unresolved, name it, and put it first in the
   §6 report per the rule about never burying a real weakness behind a tidy summary.

Only stop when the branch is synced, pushed, every actionable thread is resolved, every
blocking agentic finding is fixed or rejected in writing, and the PR is mergeable. Then
report.

---

## 6. Report back

End with a concise table: **thread/source → file:line → action taken → commit → resolved?**
State whether the branch had merge conflicts and how you resolved them, and **flag any
judgment calls** (ambiguous comments you interpreted, conflict resolutions you chose,
hooks you had to bypass) so a human can review them — these are flags, not questions.
End by confirming the PR is **ready to merge**: commits pushed, branch up to date with
base, threads resolved, `mergeable=MERGEABLE`, **and every required check green**. If a
scanner gate was red when you started, quote its final count — `net-new 0` — rather than
asserting you handled it. "All threads resolved" is not the same claim as "the gate is
green", and on a capped scanner they routinely disagree.

**A GREEN-LOOKING RUN CAN END WITH NEW THREADS BEHIND IT.** Pushing a fix makes the scanner
re-run, and it posts its findings against YOUR commit — after your last read of the threads.
On MagmaMoose/infra#638 the final triage commit landed at 12:45:34 and two fresh Chargate
threads appeared at 12:49:09. Nothing was skipped; they did not exist yet. So before
reporting, re-read the threads once the gate has finished, and treat anything new as this
run's work rather than the next one's.

**The post-gate reviews re-run too — and they leave no new comment to notice.** Your push
restarts Chargate and Brimyr, and the two reviews follow them, but a review does not post a
second comment: it PATCHes the one it already owns (§c2). So a fresh, higher-severity finding
against *your* fix lands by silently rewriting a comment you have already read and ticked off.
Nothing appears in the thread list, the comment count does not change, and a re-read of
threads alone will not surface it. Re-fetch both findings blocks by marker after the reviews
have finished, and compare the `id` set and `head_sha` against what you answered. New ids, or
the same ids at a `head_sha` matching your commits, are this run's work.

For any agentic finding you REJECTED, list it in the report with its `id` and the step of the
reasoning that fails — the same sentence you put in the ledger. That rejection is the only
audit trail that exists for it (§2b), and unlike a suppression it leaves nothing in the diff,
so a reader who cannot see it in your summary cannot find it at all.

For any scanner finding you SUPPRESSED, list it: rule id, file, and the one-line reason.
A human should be able to audit every suppression from your summary without opening the
diff. For any finding you left RED because it is real and out of scope, say that plainly
and first — it is the most important thing in the report, and burying it is how a real
weakness gets merged behind a tidy-looking summary. State the one remaining human action
("review and merge"). Only call out a push/merge-state problem if the remote rejected
it or CI is red for a reason you couldn't fix, with the exact error.
