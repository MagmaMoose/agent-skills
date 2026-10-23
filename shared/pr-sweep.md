# PR sweep workflow

Clear every open pull request in a GitHub organisation, so nothing is left to worry about.
Every PR ends **merged** or **closed with a one-line reason**. A PR stays open only when it is
blocked on something only the owner can do (a credential, a paid or external account, a store
submission, a product decision with no safe default), and the final report says exactly what.

You act for the owner and decide what is best for each repository. Decide, act, and record the
reasoning; do not stop to ask. The rules below are what keep that safe.

Input: the organisation (required). Optional: a repository filter, and `dry-run` (inventory and
plan only, change nothing).

## Ground rules

- **Never bypass protection.** No `gh pr merge --admin`, no disabling required checks, no edits
  to repository, organisation, ruleset or secret settings. Merge only when GitHub says the PR can
  merge. If a ruleset blocks a merge, the fix is to make the required checks pass.
- **Each repository's own rules win.** Before changing anything in a repository, read its
  `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` and any mistakes log, once each. They decide commit
  identity, signing, co-author trailers, branch names and merge method. Some forbid AI trailers;
  some require a bot identity; follow them exactly.
- **Private stays private.** Check `repository.isPrivate` before you write a cross-repository
  reference. Never put a private repository's name, hostnames, paths or contents into a public
  repository's commits, PRs, comments or code. Describe it generically ("a second Flux source
  outside this repo"). A string pushed to a public repo cannot be taken back.
- **Work in fresh clones or worktrees**, never in a checkout another session might be using.
  Remove them at the end.
- **No secrets in transcripts.** Use API keys and tokens inside the command that needs them
  (read them into a variable, never echo them), and never paste one into a comment.

## 1. Inventory

Pull every open PR with the state you need to decide, in one paginated GraphQL search. Keep pages
small (`first: 20`): heavy pages return HTTP 502. Retry a failed page.

```graphql
query($cursor: String) {
  search(query: "org:ORG is:pr is:open", type: ISSUE, first: 20, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest {
      number title url isDraft createdAt author { login }
      repository { nameWithOwner isPrivate }
      baseRefName headRefName mergeable mergeStateStatus reviewDecision
      autoMergeRequest { enabledAt }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      reviewThreads(first: 30) { nodes { isResolved } }
    } }
  }
}
```

Print one compact row per PR: repo, number, author (bot or human), `mergeStateStatus`, CI state,
draft / auto-merge / unresolved-thread counts, age, title. `UNKNOWN` mergeability only means GitHub
has not computed it yet; query again later.

For each repository you will merge into, read the required checks once:
`gh api repos/ORG/REPO/rules/branches/main` (rulesets) or the branch protection. A failing check
that is not required does not block a merge, but it still has to be understood.

## 2. Find the shared causes first

Before touching individual PRs, collect the failing check names across all red PRs
(`gh pr checks N --repo R --json name,state`) and count them. A check failing on many PRs at
once is almost never many separate problems. Sample one log per distinct failing check
(`gh run view RUN --job JOB --log-failed`) and look for:

- **A broken runner pool.** Jobs queued for a long time with nothing starting, or jobs that fail
  with **no runner name and no log** (the log blob is missing): the runner died mid-job. Look at
  the runner pods and their node: init containers OOMKilled, `DiskPressure`, evictions. A
  self-hosted pool that accepts jobs it cannot run holds them hostage, and other repositories'
  CI stalls behind it.
- **The org's hosted-runner minutes.** A GitHub-hosted job in a private repository that fails in
  about two seconds with no runner, and the annotation "The job was not started because recent
  account payments have failed or your spending limit needs to be increased", is billing. Only
  the owner can fix it. Read the annotation (`gh api repos/ORG/REPO/check-runs/JOB/annotations`),
  do not re-run or rewrite workflows around it, and report every PR whose required check it
  blocks. Self-hosted jobs and public repositories are unaffected, so a sweep can look half
  healthy while this is happening.
- **A gate that cannot run in this context.** Dependabot-triggered runs only see Dependabot
  secrets, not Actions secrets, so a step that needs a secret (a preview deploy, an upload)
  fails on every Dependabot PR. Fix it once on the default branch: skip or degrade that step for
  Dependabot, rather than failing it.
- **A check that is red on the default branch itself.** Then every PR inherits it. Fix it on
  main, or record that it is pre-existing and not required.
- **A shared CI gate or reusable workflow** with a bug. Fix it in its own repository and release
  it the way that repository releases, without breaking its other consumers.

Fix each shared cause once, in its own small PR, before the per-PR pass. Otherwise every PR you
touch goes red for the same reason.

## 3. Process each repository

With many repositories, fan out: one agent per repository or group of small repositories, each
given this workflow, the list of PRs it owns, the shared causes already found, and an instruction
not to touch PRs outside its list. Handle the repositories that deploy on merge yourself, or give
them to the most careful agent.

### Dependabot and other dependency bots

- Green and mergeable: merge.
- Behind or conflicting: comment `@dependabot rebase`. If someone else has pushed to its branch,
  Dependabot stops updating it; use `@dependabot recreate`.
- Superseded by a newer PR for the same dependency or group: close it, "Superseded by #N".
- Fails because the bump needs code changes (a major version): fix it on the PR branch when the
  change is reasonable and testable. Otherwise close it with the reason and
  `@dependabot ignore this major version`, so it does not come back next week.
- Fails for a reason that is not the bump: that is a shared cause (section 2).

### Human- and agent-authored PRs

Read the diff, the linked issue, every comment and every review thread. Work the threads and the
failing security gates with the PR triage workflow (`shared/pr-triage.md`): fix or correctly
suppress, reply, resolve.

**Then check the PR's premise against reality before merging.** An agent-written PR can be green
and still wrong. Real examples of premises that turned out false:

- a "fix" for an application that had been deliberately disabled, so the change touched nothing;
- a values key the chart never reads, so the change had no effect;
- a rate limit "added" where a broader setting already applied the same limit;
- an alert on a metric the platform stopped exporting, so it could never fire;
- an audit that scanned Git manifests while the offender was rendered by a chart, so it
  concluded the problem was gone.

Close those with the reason, and fix the real problem at its source if you can (often in another
repository, such as the chart).

- **Duplicates:** keep the best one (usually the newest and most complete), close the rest with
  "Duplicate of #N". Several generated refresh PRs ("refresh agent context", "refresh generated
  documentation") in one repository: keep only the newest, check it is accurate and safe to
  publish, close the others as superseded.
- **Conflicts:** rebase onto the base branch and keep both intents. In numbered lists (a mistakes
  log, numbered rules), append new entries after the existing ones rather than renumbering, since
  other files link to the existing numbers. **Never commit conflict markers**: grep for
  `<<<<<<<` and `>>>>>>>` before every commit, and make resolution scripts assert there are none,
  because a failed script followed by `git add` commits them.
- **Drafts:** finish and merge if small and clearly wanted; otherwise close with the reason.
- **Salvage what is useful.** If a PR's code is superseded but part of it is valuable (a runbook,
  a test), narrow the PR to that part and merge it, instead of closing it outright.

### PRs that deploy or apply on merge

Find out what a merge does before you merge: GitOps controllers reconcile it, Terraform pipelines
apply on push, release workflows publish. Then:

- **Kubernetes:** render the change (`kustomize build`, `helm template` with the chart's CI
  values) and inspect the result, not just whether it builds. A patch that targets nothing fails
  silently. Verify every alert expression against the live Prometheus: the metric must exist.
  After the merge, confirm the controller applied the new revision and the workload is healthy.
  Rendering cannot catch runtime failures: a volume mounted at a path that is a file in the image
  (a minimal image's binary often lives at `/<name>`) renders fine and then fails to start. For a
  new container, check the image's layout or start it once in a throwaway pod first. Watch every
  rollout you cause; a `Recreate` Deployment is down the moment its new pod cannot start. If that
  happens, suspend the controller for that app, fix it live, and land the same fix in Git.
- **Terraform:** read the plan for the exact commit you will merge. Adopt existing objects with
  declarative `import {}` blocks, so the reviewed plan shows the import and the gated apply
  performs it, instead of a manual `terraform import` someone must remember first. Merge only
  when the plan is exactly what is intended (for an adoption: N to import, 0 to change, 0 to
  destroy). **Never enable auto-merge on these**, because auto-merge merges before you have read
  the plan.
- **Destructive changes** (deleting a bucket, a database, a tunnel): verify the preconditions the
  PR itself states, with read-only queries. If you cannot verify them, do not merge; report what
  to check.
- **Secret references:** a PR that adds a key to a secret-store reference must point at a secret
  that exists, because one missing key fails the whole secret for every workload using it.

## 4. Settle the issues that keep re-creating PRs

If the organisation runs an agent that turns open issues into PRs, closing a PR while its issue
stays open makes the agent open it again (watch for the same title on a branch ending in `-r2`,
appearing minutes after you close the first). For every PR you close as obsolete, duplicate or
wrong, close or update its linked issue with the same reason. Consolidate duplicate issues into
one tracking issue, and close issues the sweep has resolved. Re-run the inventory at the end, so
PRs opened during the sweep are processed too.

If a planner agent files those issues from written notes or directives (a list of known gaps,
a roadmap file), a stale note re-files work that already shipped. When you close an issue or PR
as a duplicate of something merged, update the note it came from too: mark what is fixed and
what is in flight, with the PR numbers, dated. A planner reading the code can also miss a test or
fix that merged hours earlier. Before you merge an issue-lane PR, check that main does not
already have it.

Other automation can also change PRs under you. Auto-merge can be switched off by another
session or a merge gate running as the same account, and a governance bot can commit straight to
default branches mid-sweep. Re-check auto-merge and branch state in the final pass. Before you
re-arm auto-merge, read the PR timeline for why it was turned off: a merge gate that pushed its
own fix to a branch may turn auto-merge off on purpose, so the new head is reviewed and the gate
merges it itself. Leave that to the gate rather than routing around its review. But check the
reason it gives: a triage bot can claim a check is required when it is not. Compare it with the
ruleset (`gh api repos/ORG/REPO/rules/branches/main`), and where the reason is wrong, reply on
the PR with the correction and re-arm auto-merge.

## 5. Merging and CI capacity

- When a PR is ready, `gh pr merge N --repo R --squash --auto` lets GitHub merge it once the
  required checks pass. If GitHub answers that the PR "is in clean status", it is already
  mergeable: merge it directly. Auto-merge can drop off silently; re-check every PR you set it on
  during the final pass.
- **Auto-merge waits only for REQUIRED checks.** A failing check that is not required (a version
  bump guard, a test job) does not stop it, so a PR can merge red. Before enabling auto-merge,
  look at every check the repository runs, not just the required ones; where a meaningful check
  is not required, wait for it and merge by hand, and tell the owner it should be required.
- **A merged change is not a shipped one.** Where publishing is per artifact version (charts in a
  monorepo, packages), a change ships only with a version bump, and a publish step that skips
  existing versions skips it silently. After the merge, check the registry for the new version
  and that the consumer picked it up.
- Use `gh api -X PUT repos/ORG/REPO/pulls/N/update-branch` to bring a PR up to date without a
  local rebase, when it has no conflicts.
- Resolve review threads with GraphQL `addPullRequestReviewThreadReply` followed by
  `resolveReviewThread`, so the reply and the resolution stay paired. Correct a reply that turns
  out wrong (`updatePullRequestReviewComment`) rather than leaving it.
- Many PRs means many CI runs, and runner capacity becomes the bottleneck. Watch the pool as you
  go. A job that failed with no log needs the runner fixed, not a blind re-run; re-run with
  `gh run rerun RUN --failed` once it is fixed.
- A new push can queue behind its own stale run. Where a workflow has a `concurrency` group per
  ref with `cancel-in-progress: false`, the new head's run waits until the old head's run ends,
  and that old run still holds a runner. After pushing to a PR, cancel the old head's runs
  (`gh run list --branch B`, then `gh run cancel RUN`).
- A cancelled required check never runs again by itself. When a queue backs up, people and
  automation cancel runs that have waited for hours, and auto-merge then waits for ever. In the
  final pass, look for required checks that ended `cancelled` and re-run them.
- Do not poll CI in a tight loop. One look at a PR's state per pass is enough.

## 6. Verify and report

Re-run the inventory. Every PR still open needs a stated reason and the exact owner action. Then
report:

- one row per PR: `repo#number | merged / closed / open | what was fixed, or why`;
- shared causes fixed, and where (with links);
- issues closed or consolidated;
- anything changed on a default branch outside a PR's own branch;
- what only the owner can do, item by item.

## Platform notes

- **Windows Git Bash** rewrites arguments that look like POSIX paths, including `git show
  origin/main:path` (it becomes `origin\main;path`). Set `MSYS_NO_PATHCONV=1` first. A Bash
  heredoc can collapse `\\` to `\`; write scripts that need backslashes to a file and run that.
  Some `jq` builds emit CRLF; strip `\r` before looping over their output.
- `gh pr checks` reports a skipped required check differently from a missing one; read the
  required list from the ruleset rather than inferring it from the checks.
