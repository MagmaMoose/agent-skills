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

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
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
}' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR"
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
asking for, and — for review threads — the **thread `id`** and `isResolved`.

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

Only stop when the branch is synced, pushed, every actionable thread is resolved, and
the PR is mergeable. Then report.

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

For any scanner finding you SUPPRESSED, list it: rule id, file, and the one-line reason.
A human should be able to audit every suppression from your summary without opening the
diff. For any finding you left RED because it is real and out of scope, say that plainly
and first — it is the most important thing in the report, and burying it is how a real
weakness gets merged behind a tidy-looking summary. State the one remaining human action
("review and merge"). Only call out a push/merge-state problem if the remote rejected
it or CI is red for a reason you couldn't fix, with the exact error.
