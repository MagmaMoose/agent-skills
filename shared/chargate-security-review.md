# Post-Chargate security review workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, and relevant `README.md` files. Treat explicit hard rules from the target repository as blockers.

Chargate has finished. It is a MegaLinter-backed security and lint gate that blocks on the
findings **introduced by this PR's diff**, and it has already posted its verdict to the PR.
Your job starts where its job ends: read what it found, then review the change for the
security defects a pattern scanner structurally **cannot** find, and reply to its comment
with what it missed.

The output is **one PR comment** that reads as a security review from an engineer who read
the code. It acknowledges Chargate's findings, adds only what is genuinely additional, and
says so plainly when there is nothing to add. It carries a hidden machine-readable block so
`/pr-triage` can pick the findings up and fix them without re-parsing prose.

## What this workflow is not

- **It does not change the gate.** Chargate owns the required check. Nothing here posts a
  status, re-runs the scan, or turns a red gate green. When this review says a finding
  *blocks*, that is a judgement addressed to the author and to `/pr-triage`, not an API call.
- **It never suppresses anything.** Not a Chargate finding, not one of your own. If you
  believe a Chargate finding is a false positive, say so in prose with the reasoning; the
  decision to add an in-source suppression belongs to `/pr-triage` section 2a, which has the
  per-scanner syntax and the hardest rule in this repo: **never suppress a finding that is
  real**. A green gate bought by silencing a true finding is worse than a red one.
- **It does not review style, formatting, or lint.** MegaLinter already did. A finding that a
  linter would have caught is not additional, it is noise.

## Voice: write like a human

These rules are binding on the comment body and on every finding you write into it. It should
read as if a security engineer reviewed the change, not as if a tool emitted a report.

- Use contractions: "don't", "it's", "there's", "you'll".
- Vary sentence rhythm. Short and blunt next to longer. Don't march through identical shapes.
- **Never use an em-dash or an en-dash ("—", "–") in the posted comment.** Use a comma, a
  colon, parentheses, or a full stop and a new sentence. The one exception is the same one the
  emoji rule gets: text you quote from Chargate. Its finding bullets render as
  ``- ❌ **high** `RULE` — path.py:42 — message``, so an em-dash inside a quoted line stays as
  it is. Quote it as a fenced block or inline code so it's visibly a quotation, and don't write
  one in your own sentences.
- Ban these outright: "it's worth noting", "in summary", "delve", "leverage", "utilize"
  (write "use"), "furthermore", "additionally", "moreover", "it's important to note",
  "seamlessly", "robust" and "comprehensive" as filler.
- No sycophantic openers, no hedging filler. And **no severity-undercutting hedges**: if you
  rate something ⛔, don't also call it "probably fine" or "only theoretical". Name the
  concrete attack. If the honest read is that nobody can reach it, it isn't a ⛔.
- **No attribution footer of any kind**, no "AI review" branding, no robot emojis. The only
  emoji are the severity markers ⛔ / 🟡 / 💬, plus whatever you quote from Chargate.

**Run fully autonomously — do not ask the user anything.** No clarifying questions, no
stopping for approval. When intent is ambiguous, make the best-judgment read from the PR
title, body, linked issues and the diff, review against that, and state the assumption in the
comment. The only thing that ends the run is posting the comment, or the hard stop in step 0d.

Target PR: the PR input supplied by the invoking agent (if empty, use the PR for the current branch).

---

## 0. Coordinates, and the gate's own findings

### 0a. Resolve the PR

```bash
gh pr view "$ARGUMENTS" --json number,headRefName,headRefOid,baseRefName,author,url,isDraft 2>/dev/null \
  || gh pr view --json number,headRefName,headRefOid,baseRefName,author,url,isDraft

gh repo view --json owner,name -q '.owner.login + " " + .name'
```

Capture `OWNER`, `REPO`, `PR`, `HEAD` (head branch), `HEAD_SHA` (`headRefOid`), `BASE`, and
`AUTHOR`. The repo may live on **github.com** or **pinkroccade.ghe.com**; `gh` picks the host
from the remote, so every command below works as-is.

You do not need to check out the branch to review, but you **do** need the files. Fetch the
head ref so you can read whole files, not just the patch (step 2 depends on this):

```bash
git fetch origin "$HEAD" && git --no-pager log -1 --oneline "origin/$HEAD"
```

**Fetching does not touch the working tree, and that trips up every "read the file" step
below.** After the fetch, `origin/$HEAD` holds the PR's code while the checkout is still on
whatever branch you started on: a file the PR modified reads back at its *base* content, and a
file the PR *adds* is not on disk at all. Reviewing that is worse than reviewing nothing, since
every line number you cite is then someone else's code. So establish once, up front, which of
the two situations you are in:

```bash
# Is the PR head already the checkout? (true in a headless PR clone, usually false locally)
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$HEAD")" ] \
  && echo "WORKTREE IS THE PR HEAD — Read and grep the working tree directly" \
  || echo "WORKTREE IS NOT THE PR HEAD — read at the ref (see below)"
```

When it is not the head, read content at the ref rather than off disk, and say so nowhere in
the comment because it changes nothing about the review, only about how you fetch bytes:

```bash
git --no-pager show "origin/$HEAD:<path>"                 # one whole file at the PR head
git --no-pager grep -nE '<pattern>' "origin/$HEAD" -- '<pathspec>'   # grep the PR head
git --no-pager show --stat "origin/$HEAD"                 # what the head commit touched
```

The Read and Grep tools operate on the working tree, so they are only safe under the first
branch. Under the second, either use the `git show` / `git grep` forms above throughout, or
check the branch out once (`git switch --detach "origin/$HEAD"`) and leave the tree clean when
you're done. The shell snippets in step 1 that grep files by path assume the head is checked
out; convert them with `git grep ... "origin/$HEAD"` if it isn't.

### 0b. Find the Chargate summary comment

Chargate posts exactly one PR *issue comment* carrying the hidden marker
`<!-- chargate:pr-summary -->`, and on each later push it finds that same comment and
`PATCH`es it rather than posting a second. So there is one, and it reflects the latest run.

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- chargate:pr-summary -->"))) | last) // empty
           | "\(.id)\t\(.updated_at)\t\(.html_url)"'
```

**Use `--paginate --slurp` and pipe to `jq`, not `--paginate -q`, whenever the filter
aggregates.** With `--paginate -q`, `gh` applies the jq program to **each page separately**, so
`| last` returns the last match *per page* and a PR with more than 100 comments quietly emits
several answers. `--slurp` wraps the pages into one outer array (hence the leading `add`), and
`gh` refuses `--slurp` together with `-q`, which is why the filter moves into a real `jq` on the
right of a pipe. A per-item filter like `.[] | select(...)` is unaffected and can stay on `-q`.

Keep the `id` (you'll link to it) and save the body to a scratch file:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- chargate:pr-summary -->"))) | last) // empty | .body' \
  > .git/chargate-summary.md
test -s .git/chargate-summary.md || echo "NO CHARGATE COMMENT — go to step 0d"
```

### 0c. Parse what it already reported

The rendered body is stable. Read these four things out of it:

```bash
grep -m1 '^\*\*Mode:\*\*' .git/chargate-summary.md   # **Mode:** `pr` · **Gate:** ❌ `fail`
grep -m1 -A2 '^| Net-new' .git/chargate-summary.md   # the counts table row
grep -E '^- (❌|⚠️) ' .git/chargate-summary.md        # every net-new finding, one per line
grep -m1 '^✅ No net-new findings' .git/chargate-summary.md   # the clean case
```

- **Mode** is `pr` or `baseline`. A `baseline` run does not gate at all and its comment says
  `📋 Baseline scan — full SARIF shipped; no net-new gate.` There is no net-new set to be
  additional to. Treat it exactly like the missing-comment case in 0d: report it and stop.
- **Gate** is `✅ \`pass\`` or `❌ \`fail\``.
- Each finding bullet is rendered as
  `- ❌ **<band>** \`<rule-id>\` — <path>:<line> — <message>`, where `❌` means it blocks under
  the current `fail_on` threshold and `⚠️` means it is net-new but below that threshold. The
  band is one of `critical` / `high` / `medium` / `low` / `none`. Both the rule id and the
  message are optional in the render, so parse defensively.
- `✅ No net-new findings introduced by this change.` means the gate is clean. That is a
  perfectly normal input to this review, and the most valuable one: the gate found nothing,
  which says nothing at all about the classes in step 1.

Also pull Chargate's **inline** comments. They carry `<!-- chargate:finding -->` and give you
the exact `path` and `line` GitHub anchored each finding to, which is what step 3 dedupes on:

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR/comments" --paginate \
  -q '.[] | select(.body | contains("<!-- chargate:finding -->")) | {path, line, body}'
```

If the run uploaded its SARIF artifact (the action's default name is `chargate-sarif`), that
is the authoritative, uncapped list. Inline review comments are capped and scanners self-limit,
so the artifact can be larger than the threads:

```bash
# Filter on the workflow NAME as well as the SHA. Most repos run several workflows per commit,
# so "the first run at this SHA" is usually someone else's job and the download then misses.
RUN_ID=$(gh run list --branch "$HEAD" --limit 50 --json databaseId,headSha,name,conclusion \
  -q "([.[] | select(.headSha == \"$HEAD_SHA\" and (.name | ascii_downcase | contains(\"chargate\")))] | first) // empty | .databaseId")
# Fall back to any run at the SHA only if nothing is named for the gate (the workflow may be
# called something else entirely); the download still has to find the artifact by name.
[ -z "$RUN_ID" ] && RUN_ID=$(gh run list --branch "$HEAD" --limit 50 --json databaseId,headSha,name \
  -q "([.[] | select(.headSha == \"$HEAD_SHA\")] | first) // empty | .databaseId")
[ -n "$RUN_ID" ] && gh run download "$RUN_ID" -n chargate-sarif -D .git/chargate-sarif 2>/dev/null \
  && jq -r '.runs[].results[] | [(.ruleId // "-"),
       (.locations[0].physicalLocation.artifactLocation.uri // "-"),
       ((.locations[0].physicalLocation.region.startLine // 0) | tostring),
       (.message.text // "")] | @tsv' .git/chargate-sarif/*.sarif \
  || echo "no SARIF artifact — use the summary comment as the finding list"
```

One caution on that artifact: it is the **full** SARIF, net-new *plus* pre-existing. Only the
bullets in the summary comment are net-new. Step 3 tells you what to do with the difference.

### 0d. HARD STOP: no gate finding set, no review

If 0b returns nothing, or 0c shows the run was `baseline`, **do not review**. "Additional to
what Chargate found" is undefined when there is no record of what it found, and a review posted
in that state either duplicates the gate or silently claims coverage the gate never gave. Post
nothing, and report which of these it is:

1. **Chargate never ran on this PR.** `gh pr checks "$PR"` shows no Chargate check. The
   workflow is missing, path-filtered out, or the PR is from a fork without the token. The
   human action is to get the gate running, not to hand-review around it.
2. **It ran but PR commenting is off or failed.** The check exists but there is no comment.
   Chargate isolates GitHub API failures on purpose (a comment failure never fails the gate),
   so this is silent by design. Find the run with the `gh run list` call from 0c, then
   `gh run view "$RUN_ID" --log | grep -i 'PR comments'` — the job summary carries the reason.
3. **It ran in `baseline` mode.** The comment *does* exist, and says `📋 Baseline scan — full
   SARIF shipped; no net-new gate.` A baseline run establishes the pre-existing set, it does
   not gate a diff, so there is no net-new finding set to be additional to.

In all three cases: say so, name the run you looked at, and stop. Do not post a comment
carrying the review marker, because an empty or apologetic comment under that marker is
indistinguishable, on the next run, from a review that ran and found nothing.

---

## 1. Review the classes the gate cannot see

This is the reason the workflow exists. Chargate is a pattern and SAST gate over the diff. It
matches rules against text and syntax, per file, on changed lines. Everything below is either
invisible to that model or requires knowing what the code *means*. Work through all thirteen;
each one is a dimension you must actively look for, not a checklist to tick.

For each dimension, the question is the same: **what does the code in this diff let someone do
that it shouldn't?**

### 1.1 Authorization and multi-tenancy

Scanners check that authentication exists. They do not check that the caller is allowed to
touch *this object*. A route that authenticates perfectly and then loads a record by id with
no ownership predicate is a complete tenancy breach and lints clean.

Look for: a new or modified handler that reads an identifier from the request and fetches by
it; a query missing the `tenant_id` / `org_id` / `user_id` predicate its siblings have; a
decorator or dependency present on neighbouring routes and absent on this one; an admin-only
capability reachable from a non-admin path.

```bash
# Every route touched by the diff, next to the auth dependency (or its absence).
# Reads at the PR head, so a route in a file this PR ADDS still shows up.
gh pr diff "$PR" --name-only | grep -E 'routes?|handlers?|api|views' \
  | while read -r f; do
      git --no-pager grep -nE '@(app|router)\.(get|post|put|patch|delete)|def [a-z_]+\(' \
        "origin/$HEAD" -- "$f"
    done
# Compare the new query against how the same table is queried elsewhere
git --no-pager grep -nE "select\(.*<Model>" "origin/$HEAD" -- '*.py' | head -20
```

The comparison is the tell. If nine call sites filter by tenant and the new one doesn't, that
is a finding regardless of what any rule says.

### 1.2 Authentication flow, session and token lifetime

Syntactically valid, semantically wrong: a token minted with no expiry, a refresh token that
never rotates, a session that survives a password change, a password reset token that is
single-use in the comment and reusable in the code, a JWT verified with `verify=False` or with
the algorithm taken from the token's own header.

Look for: `exp` / `ttl` / `max_age` absent or set very high, `algorithms=` accepting a list
that includes `none` or `HS256` alongside RS256, a comparison of secrets with `==` instead of
a constant-time compare, a logout that clears a cookie without invalidating server state.

### 1.3 Secrets reaching a log or an error path

Secret scanners find secrets in the *source*. They do not find a secret that arrives at
runtime and gets written to a log line, an exception message, a trace span, or an error
response. This is the single most common real finding in this category and it is always
invisible to the gate.

Look for: the whole request object, headers, or a config object passed into a log call;
`repr()` / f-string interpolation of a settings or credentials object; an exception handler
that returns `str(exc)` to the client where the exception can carry a connection string; a new
debug log added "temporarily".

```bash
gh pr diff "$PR" | grep -nE '^\+.*(log(ger)?\.(debug|info|warning|error)|print\()' \
  | grep -iE 'token|secret|password|passwd|key|authorization|cookie|credential|conn|dsn|url'
```

### 1.4 SSRF and unvalidated outbound requests

A new outbound HTTP call whose URL, host, or path comes even partly from user input. The gate
sees a request library call, which is fine everywhere else in the file, so it says nothing.

Look for: a URL built from a request field; a webhook target the caller supplies; a redirect
target followed server-side; an image or document fetched by URL; a "fetch this for me"
feature of any shape. Then ask the three questions that matter: is the scheme constrained, is
the host allowlisted, and are redirects followed (a same-host allowlist plus
`allow_redirects=True` is not an allowlist). On cloud, the concrete payload is the instance
metadata endpoint: `169.254.169.254`, or `metadata.google.internal`.

### 1.5 Injection through a path the scanner cannot trace

Chargate catches obvious concatenation into a query on one line. It loses the trail across a
function boundary, through a helper, through a dict, or through an ORM escape hatch.

Look for: `text()` / `raw()` / `execute()` taking a value that was built elsewhere;
`subprocess` with `shell=True` and any non-literal in the argument; a template rendered from a
string that came from input (SSTI); an LDAP or NoSQL filter assembled by string ops; a
`getattr` / `eval` / `pickle.loads` on anything request-derived. Trace the value back to its
source by hand. If the source is a request, it's a finding even when every individual line
looks fine.

### 1.6 Insecure direct object references

The sibling of 1.1, at the identifier level. A sequential or guessable id exposed in a URL or
response, where the handler's only check is that the id exists.

Look for: a route parameter used as a primary key with no scoping; a signed-URL or share-token
scheme where the token is derived from the id; a bulk endpoint that accepts a list of ids and
checks ownership on the first one only, or on none.

### 1.7 Race conditions and TOCTOU

A check and its use split by anything: an `await`, a network call, a separate transaction. The
scanner reads each statement in isolation and sees two correct statements.

Look for: check-then-act on a balance, a quota, a seat count, a one-time token, a uniqueness
constraint enforced in Python instead of the database; `os.path.exists` then open; a
"reserve then confirm" flow with no lock, no `SELECT ... FOR UPDATE`, and no unique index. Ask
what two simultaneous requests do. If the answer is "both succeed", that is the finding.

### 1.8 Cryptographic misuse that is syntactically fine

The call is to the right library, with a modern algorithm, and it is still wrong.

Look for: a static or reused IV/nonce; ECB mode; a key derived with a single hash pass instead
of a KDF; `random` instead of `secrets` for anything security-bearing; encrypt-without-
authenticate where the ciphertext is attacker-reachable; a signature verified with the key the
message supplied; a hash used as a MAC. Also the inverse: a "hash" of a password with a fast
digest, which every scanner flags, and a *slow* KDF with a work factor of 1, which none do.

### 1.9 Dependency and supply-chain risk beyond a CVE match

The scanner matches installed versions against a CVE database. That leaves the whole of supply
chain risk that isn't a published CVE yet.

Look for, on any dependency the diff adds or bumps: is the package name a typo-neighbour of a
popular one; is it pinned to an exact version where the target repo's `CLAUDE.md` requires that,
and does a lockfile entry come with it; is a GitHub Action pinned to a **commit SHA** rather
than a tag; does a new install step pipe a remote script into a shell; did a transitive
dependency arrive alongside the direct one, and did anyone look at it. A dependency added
without the approval the target repo's `CLAUDE.md` requires is a finding on its own terms.

```bash
# Added lines in dependency and workflow files (gh pr diff takes no pathspec, so filter here)
gh pr diff "$PR" \
  | awk '/^\+\+\+ /{f=$2} /^\+[^+]/{ if (f ~ /\.(toml|json|lock|ya?ml)$/) print f": "$0 }' \
  | grep -E 'uses: |version|"[~^]|>=' | head -40
```

### 1.10 Privilege escalation in infrastructure as code

IaC scanners have deep rule coverage for encryption, public access and logging. They are much
weaker on *authority*: a policy document that is syntactically perfect and grants far more
than the workload needs.

Look for: `"Action": "*"` or a service-level wildcard, `"Resource": "*"` on anything that
isn't genuinely global, `iam:PassRole` without a `Condition`, a trust policy whose `Principal`
is broader than one account or one role, `sts:AssumeRole` chains that end somewhere
surprising, an OIDC trust condition matching `repo:org/*` instead of one repository and ref.
In Kubernetes: a ClusterRole where a Role would do, `*` verbs on `secrets`, `escalate` /
`bind` / `impersonate`, a ServiceAccount token mounted into a pod that never calls the API,
`hostPath` / `hostNetwork` / `privileged`, or a NetworkPolicy the change quietly widens.

The question to ask on every one: what can this identity do that it does not need to do, and
who can make it do that?

### 1.11 Data exposure in an API response shape

Nothing in a scanner's model knows that a field is sensitive. A serializer that grows a field,
or switches from an explicit field list to "dump the model", ships whatever the model has.

Look for: a response schema that changed from an allowlist to the whole ORM object; a new
`include` / `expand` / `?fields=` parameter; a nested relation serialized with its own full
model; an error response that echoes back input; a list endpoint that leaks the *existence* of
other tenants' rows through counts, ids, or timing. Read the model, not the schema: the
question is which of its columns just became reachable.

### 1.12 Missing rate limiting or idempotency on a state-changing route

Absence is invisible to a scanner. It cannot flag the decorator that isn't there.

Look for: a new POST/PUT/PATCH/DELETE with no rate limit where its neighbours have one; login,
password reset, OTP, invite, or anything that sends mail or SMS, with no throttle (that's a
billing DoS as well as an enumeration vector); a payment or provisioning call with no
idempotency key, where a client retry double-charges; an expensive query reachable
unauthenticated; a webhook receiver with no signature verification and no replay window.

### 1.13 What the diff enables elsewhere

The one the gate can never do, because the vulnerability is not in the changed lines at all.
The diff makes an existing weakness reachable, or removes something another file depended on.

Look for: a new caller of an existing unsafe helper (now with attacker-controlled input for
the first time); a validation or guard removed because it "wasn't used"; a feature flag
default flipped to on; a route added to a public router; a CORS origin, CSP directive, or
allowlist widened; an internal service exposed through an ingress; a config default changed in
a way that only matters in production.

```bash
# For each function/class the diff touches, who else calls it now (searched at the PR head)
gh pr diff "$PR" | grep -E '^\+.*(def |class |func |function )' \
  | sed -E 's/.*(def|class|func|function) +([A-Za-z0-9_]+).*/\2/' | sort -u \
  | while read -r sym; do
      echo "== $sym"
      git --no-pager grep -nw "$sym" "origin/$HEAD" \
        -- '*.py' '*.ts' '*.tsx' '*.go' '*.js' '*.rb' '*.java' '*.cs' | head -5
    done
```

---

## 2. Read the diff AND the code around it

A security review that reads only the diff has reproduced the gate's blind spot with a slower,
more expensive tool. Half the dimensions above are only decidable from code the diff never
touched: the caller that supplies the input, the sibling route that has the check this one
lacks, the model behind the serializer, the middleware that may or may not be in the path.

So for every non-trivial hunk:

```bash
gh pr diff "$PR"                                    # the change
gh api "repos/$OWNER/$REPO/pulls/$PR/files" --paginate \
  -q '.[] | {path:.filename, status, additions, deletions}'
```

then **read the whole file at the PR head** (Read when the working tree *is* the head,
otherwise `git --no-pager show "origin/$HEAD:<path>"`, per the check in step 0a), and:

1. **Follow every input backwards** to where it enters the process. Request body, query
   string, path parameter, header, webhook payload, queue message, environment. If you cannot
   name the entry point, you cannot rate the finding.
2. **Follow every new symbol forwards** to its callers, with Grep. A helper that is safe for
   its two existing callers may not be safe for the third one this PR adds.
3. **Read the sibling.** The fastest way to find a missing check is to read the nearest
   equivalent route, resource, or policy and diff them by eye. Convention in the file is
   evidence: if every other handler has the guard, its absence here is intentional or a bug,
   and either way it needs a sentence.
4. **Check the tests.** A new security-relevant branch with no negative test (the unauthorized
   caller, the wrong tenant, the expired token) is at least a 🟡. The gate never looks at test
   coverage of a security path.

Budget your reading. On a very large PR, prioritise files that touch auth, routing, IAM,
serialization, crypto, and anything under a `security/` or `middleware/` path, and then **say
in the comment which files you read shallowly**. Overstated coverage is its own defect.

---

## 3. Deduplicate against Chargate

Everything you post must be *additional*. Restating a finding the gate already made is noise
that trains the author to skim both comments.

**Match on location and on rule intent, never on wording.** Chargate's message is a scanner
string; yours is a sentence. They will never match textually and that proves nothing.

For each candidate finding of yours, drop it when **either** test hits:

- **Location test.** Same file, and your line is within **±3 lines** of a Chargate net-new
  finding (from the summary bullets in step 0c) or of one of its inline comments. The tolerance
  matters: the scanner anchors to the line it matched, you anchor to the line that's wrong, and
  on a multi-line statement those differ. Widen the window to the whole statement when the
  finding is about one.
- **Intent test.** Different location, same underlying defect. Chargate flagging
  `AVD-AWS-0089` (no S3 access logging) on line 20 and you writing "this bucket has no access
  logging" about line 45 of the same resource is one finding, not two. Read the rule id: the
  scanner is named by the shape of the id (`CKV_*` Checkov, `AVD-*` Trivy, a UUID KICS, a
  dotted path Semgrep), and looking the rule up tells you exactly what it covers.

Then handle these three cases explicitly rather than by instinct:

- **A finding of yours coincides with a *pre-existing* SARIF result.** Chargate did not report
  it on this PR (pre-existing findings never block and never appear in the summary bullets), so
  it is not a duplicate of the gate's PR output. Keep it, and label it `pre-existing` in both
  the prose and the machine block, so nobody reads it as something this PR introduced. Do not
  quietly let the PR own it.
- **You disagree with a finding Chargate made.** Say so in prose, in the opening paragraph,
  with the reason. That is not an additional finding and it does not go in the findings list.
  It also is not permission to suppress: `/pr-triage` decides that, under its section 2a.
- **The diff adds an in-source suppression.** Chargate counts accepted in-source suppressions
  in the summary table (the `Suppressed` column shows up only when it's non-zero) and never
  gates on them, which makes a suppression the quietest way to ship a real weakness. Every
  suppression the diff introduces is in scope for this review, and nothing else will look at
  it. Read the rule each one silences and decide whether the control genuinely doesn't apply
  here. If it does apply, that is one of your findings, at the severity of the weakness it
  hides, not at the severity of "a comment was added".

  ```bash
  gh pr diff "$PR" | grep -nE '^\+.*(checkov:skip=|trivy:ignore:|kics-scan disable=|kics-ignore|nosemgrep|nosec|DevSkim: ignore|trunk-ignore)'
  ```

**Count the drops and report the count.** The comment states how many candidates were dropped
as duplicates. Without that number, a reader cannot tell a review that deduped carefully from
one that never checked.

---

## 4. Severity, and what the author does about it

Every finding you keep must carry all five of these. A finding missing any of them is not
ready to post:

1. **Exact `file:line`** (a range when the defect spans a statement). Real, verified, at
   `HEAD_SHA`.
2. **What an attacker does with it.** Concrete: who they are (unauthenticated, any logged-in
   user, another tenant, a compromised CI job), what they send, and what they get. If you
   cannot write this sentence, you have a code smell, not a security finding, and it belongs in
   `/pr-review` instead.
3. **The concrete fix.** The change to make, specific enough to apply. A code block when it's
   small.
4. **A severity**, from the table below.
5. **Whether it blocks.**

| Severity | Marker | Blocks | Litmus |
| --- | --- | --- | --- |
| `critical` | ⛔ | yes | Reachable by an unauthenticated caller, or breaks tenant isolation, or exposes credentials or customer data. Exploitable as merged. |
| `high` | ⛔ | yes | Reachable by an authenticated caller who shouldn't get there, or escalates privilege, or a real weakness whose exploitation needs one non-trivial precondition. |
| `medium` | 🟡 | no | A real weakness that needs an unlikely precondition, or defence-in-depth that is genuinely missing (no rate limit on a costly route, a missing negative test on a security branch). |
| `low` | 💬 | no | Hardening. Nothing breaks if the author skips it. |

The severity vocabulary is deliberately the same as Chargate's bands (`critical` / `high` /
`medium` / `low`) so the two halves of the PR conversation rate things on one scale.

**Severity honesty, and it cuts both ways.** The label and the prose must agree. If your text
says "practically unreachable" or the only attacker you can describe is hypothetical, it is
`low`, so label it `low`. Equally, do not round a tenant-isolation break down to `medium`
because the PR is otherwise good, and never soften a finding because the gate is green and
turning it red is inconvenient. **The strongest rule in this repo applies here: never suppress
or downplay a real finding to make a gate look clean.**

**Review verdict**, derived mechanically:

- any `critical` or `high` → **`blocking`**
- otherwise any `medium` or `low` → **`advisory`**
- no additional findings at all → **`clean`**

---

## 5. Reply to the Chargate comment

**One PR issue comment, carrying `<!-- agent-skills:chargate-security-review -->`.** Find the
prior one and `PATCH` it; only `POST` when there isn't one. This is the same idempotency
pattern Chargate uses for its own summary, and for the same reason: a push re-runs the gate,
which re-runs this review, and a second comment per push turns the PR into a scroll.

Chargate's summary is a plain issue comment, so there is no thread to reply into. The reply is
this comment, and it reads as a reply by opening on what Chargate found and linking to it:
`https://github.com/$OWNER/$REPO/pull/$PR#issuecomment-<the id from step 0b>`.

### 5a. Write the body

Write it to `.git/security-review.md` with the Write tool (real newlines, no shell escaping).

````markdown
<!-- agent-skills:chargate-security-review -->
## Security review

<One paragraph. What Chargate reported (quote its counts and the gate result), whether you
agree with its call, and anything it flagged that you read differently. Link its comment.
Then one sentence on what you reviewed beyond it.>

### Additional findings

#### ⛔ 1. <short title> (`path/to/file.py:42`, `critical`)

<What an attacker does. Who they are, what they send, what they get. Two or three sentences.>

**Fix:** <the concrete change>

```python
# the corrected form, when it's small enough to show
```

#### 🟡 2. <short title> (`path/to/other.tf:118-126`, `medium`)

<Same shape.>

**Fix:** <…>

### Reviewed and clear

<Optional, one line each, only for dimensions where "we looked and it's fine" is genuinely
useful to the author. Skip entirely rather than padding.>

<details>
<summary>Coverage</summary>

Reviewed at `<HEAD_SHA>` against the 13 checks a pattern scanner can't make: authorization and
tenancy, auth and token lifetime, secrets on log and error paths, SSRF, injection across call
boundaries, IDOR, TOCTOU, crypto misuse, supply chain, IaC privilege, response-shape exposure,
rate limiting and idempotency, and what the change enables elsewhere.

Read in full: `<file>`, `<file>`. Read shallowly: `<file>` (<why>).
Dropped <K> candidate finding(s) as already reported by Chargate.

</details>
````

**The clean case must be unambiguous.** Silence reads as "the review didn't run", which is the
worst outcome: the author gets a green gate and assumes a human looked. When there are no
additional findings, replace the findings section with a direct statement and keep the coverage
block, so the reader can see what "nothing" was measured against:

```markdown
### Nothing to add

I went through the diff and the code around it against the checks below, and I don't have
anything to add to what Chargate reported. <One sentence on the riskiest thing in the change
and why it's fine, so it's clear this was a read and not a rubber stamp.>
```

The same applies when the gate itself is clean. `✅ No net-new findings` plus a silent review
is exactly the state where a real authorization bug ships.

### 5b. The machine-readable block

Append this at the very bottom of the body, inside an HTML comment so it never renders. It is
what `/pr-triage` parses to fix the findings without re-reading prose.

```
<!-- agent-skills:findings:v1
{
  "schema_version": 1,
  "skill": "chargate-security-review",
  "gate": "chargate",
  "head_sha": "<HEAD_SHA>",
  "gate_comment_id": 1234567890,
  "gate_result": "fail",
  "gate_net_new": 3,
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
      "end_line": 48,
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

Field rules, all binding:

- `verdict` is `blocking` | `advisory` | `clean`, derived exactly as step 4 says.
- `severity` is `critical` | `high` | `medium` | `low`. `blocks` is `true` only for
  `critical` and `high`, and must agree with `severity` on every entry.
- `class` is the dimension from step 1, one of: `authorization`, `authentication`,
  `secret-exposure`, `ssrf`, `injection`, `idor`, `race-condition`, `crypto`, `supply-chain`,
  `iac-privilege`, `data-exposure`, `rate-limiting`, `enabled-elsewhere`, plus
  `unsafe-suppression` for the step 3 case where the diff silences a rule that does apply.
- `confidence` is `confirmed` (you traced it end to end and can name the entry point) or
  `probable` (the pattern is there and one link in the chain is unverified). Never post a
  `blocks: true` finding at `probable` confidence without saying which link you couldn't
  verify, in the prose.
- `pre_existing` is `true` only for the step 3 case: your finding sits on code this PR did not
  introduce.
- `id` is stable across runs for the same defect (`csr-<n>` in the order they appear), so a
  re-review updates rather than renumbers.
- `line` is required and real. `end_line` only when the finding spans a statement.
- **Never emit the three characters `-->` inside the JSON.** They close the HTML comment early
  and spill the rest of the block onto the page as visible text. If a quoted snippet contains
  one, escape the `>` as `\u003e` (so the JSON reads `--\u003e`), which `jq`
  decodes back to the original string on the way out.
- **The opener and the closer are the delimiters, so keep their shape exactly.** The block
  starts with `<!-- agent-skills:findings:v1` on its own line and ends with `-->` **alone at
  column 0**. `/pr-triage` extracts it with `sed -n '/<!-- agent-skills:findings:v1/,/^-->/p'`,
  which anchors the closer to the start of a line; an indented `-->`, or one trailing the last
  `}`, leaves the range unterminated and the block unreadable.
- `"findings": []` on a clean review. The block is always present, including when clean, so a
  consumer can tell "reviewed, nothing found" from "never reviewed". `/pr-triage` treats a
  missing or unparseable block as malformed, **not** as a clean review, so a broken block costs
  you the whole review rather than degrading gracefully.

Validate your own body **before** you post it, straight off the file:

```bash
sed -n '/<!-- agent-skills:findings:v1/,/^-->/p' .git/security-review.md | sed '1d;$d' \
  | jq -e '.findings | length' >/dev/null && echo "block parses" || echo "BLOCK IS MALFORMED"
```

If `jq` errors there, fix the body before posting; a malformed block is worse than none,
because `/pr-triage` reads it as "reviewed, nothing found". A consumer picks it up the same
way, once the comment exists:

```bash
gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:chargate-security-review -->"))) | last) // empty | .body' \
  | sed -n '/<!-- agent-skills:findings:v1/,/^-->/p' | sed '1d;$d' \
  | jq '{verdict, blocking: [.findings[] | select(.blocks)] | length}'
```

### 5c. Post it, once

```bash
EXISTING=$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate --slurp \
  | jq -r '(add | map(select(.body | contains("<!-- agent-skills:chargate-security-review -->"))) | last) // empty | .id')

if [ -n "$EXISTING" ]; then
  gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$EXISTING" \
    -F body=@.git/security-review.md -q '"updated " + .html_url'
else
  gh api --method POST "repos/$OWNER/$REPO/issues/$PR/comments" \
    -F body=@.git/security-review.md -q '"posted " + .html_url'
fi
```

`-F body=@<path>` sends the file's contents as the field value, so Markdown, code fences and
the JSON block all survive without hand-escaping.

The `PATCH` replaces the whole body, which is what you want: a finding the author fixed since
the last run disappears from the comment instead of accumulating, and the comment always
describes `HEAD_SHA` rather than a history of every push. Keep the `id`s stable for findings
that survive, so a reader can follow one across updates.

**Carry forward anything `/pr-triage` wrote into the comment.** When it answers these findings
it PATCHes *this* comment, appending a per-finding ledger below the coverage block and above
the machine block (its section 2b says so, and it is the only durable record of a finding it
*rejected*). A blind rewrite on the next push deletes that reasoning silently. So when
`$EXISTING` is set, pull the prior body first and lift out the region between `</details>` and
the findings block, then paste it back into the new body in the same position:

```bash
gh api "repos/$OWNER/$REPO/issues/comments/$EXISTING" -q .body > .git/prior-review.md
# Anchor on the LAST </details> before the findings block: a finding may carry its own
# <details> (a proof-of-concept), and anchoring on the first one drags the coverage block
# into the carry-forward with its closing tag eaten, which silently swallows the rest of
# the comment into a collapsed section when you paste it back.
awk '/^<\/details>$/{buf="";f=1;next}
     /^<!-- agent-skills:findings:v1/{f=0;exit}
     f{buf=buf $0 "\n"}
     END{printf "%s",buf}' .git/prior-review.md \
  | sed -e '/./,$!d' > .git/carry-forward.md
test -s .git/carry-forward.md && echo "carry this forward verbatim into the new body"
```

Reproduce it **verbatim**, and reconcile against it rather than ignoring it: a finding the
ledger records as `fixed` should be gone from your new findings list, and if it isn't, say so
in the prose (the fix didn't land, or it landed and missed the case). A finding it `rejected`
that you still believe stands keeps its id and gets one line answering the rejection's named
step, not a restatement of your original claim.

That call is a **one-shot**. Once it returns an `html_url` you are done: do not post again, not
to correct a typo, not to add a finding you thought of afterwards (edit the file and `PATCH`
the same id instead), and never a second comment in one run. If it fails, read the error and
fix the body; a 422 here is almost always malformed JSON in the payload, not a GitHub problem.

**Do not** post inline review comments. Chargate owns the inline lane on this PR and deletes
prior `<!-- chargate:finding -->` comments on each run; adding a second inline stream doubles
the noise the gate exists to reduce. Everything you found goes in the one comment, anchored by
`path:line` in prose.

Clean up afterwards: `rm -f .git/security-review.md .git/chargate-summary.md && rm -rf .git/chargate-sarif`.

---

## 6. Verify before you report

Run every one of these before posting. A security review that cries wolf gets muted, and a
muted review is worse than none.

- **Every `file:line` is real.** Check it at the head ref, not from memory:
  `git --no-pager show "origin/$HEAD:<path>" | sed -n '<line>p'`. A finding pointing at the
  wrong line is indistinguishable from a hallucinated one.
- **Every finding traces to something you read.** Not to a pattern you expect to be there. If
  you wrote "there's no ownership check", you must have read the function and confirmed the
  absence, and confirmed no middleware or dependency supplies it upstream.
- **Every attack sentence names a real entry point.** Walk it once more: request → handler →
  the line. If a step is missing, downgrade the confidence or drop the finding.
- **Nothing was invented to look thorough.** A short review that is entirely true beats a long
  one with two speculative entries. Findings are not a quota.
- **The dedupe actually ran.** You have the Chargate finding list in hand and a count of what
  you dropped.
- **The JSON parses**, via the local `sed | jq` check in 5b, and its closing `-->` sits alone
  at column 0.
- **On an update, `/pr-triage`'s ledger survived.** If the prior comment carried one, it is in
  the new body verbatim and you reconciled your findings against it (5c).
- **No em-dash, no attribution footer, no robot emoji** anywhere in the body, outside text
  quoted from Chargate. Check the prose you wrote, not the lines you quoted:

  ```bash
  # strip fenced blocks and inline code, then look for a dash you wrote yourself
  awk '/^```/{f=!f;next} !f' .git/security-review.md | sed 's/`[^`]*`//g' | grep -n '[—–]'
  ```
- **Say when you found nothing.** Explicitly, in the words of the clean-case template. Never
  let an empty findings section stand in for a statement.

---

## 7. Report back

End the run with a short summary for the invoking agent (this is your transcript output, not
another comment):

- Whether the comment was **posted** or **updated**, and its URL.
- The Chargate baseline you reviewed against: gate result, net-new count, and the comment id.
- Your verdict (`blocking` / `advisory` / `clean`) and a table:
  **severity → file:line → finding → fix**.
- How many candidates you dropped as duplicates.
- Anything reviewed shallowly and why, so coverage isn't overstated. **No silent truncation.**
- Any judgement call worth a human's eye: a finding that turned on an assumption about intent,
  a Chargate finding you read as a false positive, a `probable`-confidence finding you posted
  as blocking.
- The one remaining human action, which is normally "`/pr-triage` will fix the blocking
  findings, then re-check the gate".
