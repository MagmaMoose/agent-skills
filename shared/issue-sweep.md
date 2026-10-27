# Issue sweep workflow

Settle every open issue in scope, so the backlog tells the truth. Every issue ends **closed with
a one-line reason** (done, superseded, not planned, moved to its owner) or **open with a dated
state comment** and the right project status. Boards drift: a "To Do" card can be shipped work, an
"In progress" card can be a PR that merged a week ago, and a backlog item can have lost its reason
to exist. The sweep checks each one against reality instead of trusting the column it sits in.

You act for the owner and decide what is right for each issue. Decide, act, and record the
reasoning; do not stop to ask. The rules below are what keep that safe. Stop and ask only for a
decision that is genuinely the owner's: a commitment to another team, money, or closing something
a person outside the owner's team is waiting on with no new home for it.

Input: the scope (default: open issues assigned to the current user on the current host).
Optional: an organisation or repository filter, and `dry-run` (inventory, verify and propose
comments; change nothing).

## Ground rules

- **Evidence over status.** A project column, a label, a checkbox and an old comment are claims.
  Decide from the default branch, the merged PRs and the live system. A merged PR is not a done
  issue until the change is released or applied where the issue needs it.
- **Production is read-only while you inspect.** Queries, `get`, `describe`, logs and metrics only.
  No exec that changes state, no restarts, no password sign-ins, no "quick fix" on the way past.
- **Respect ownership.** If an issue sits in another team's repository, or describes work that
  belongs to another team, its home is that team's backlog. Never route around a team boundary by
  changing their workload from a central place. Move the need (a short issue in their backlog),
  close or unassign here, and link the two.
- **Private stays private.** Before you write a cross-repository reference, check whether the
  source repository is private. Never put a private repository's names, hostnames, paths or
  contents into a public repository's issues, commits or PRs.
- **No secrets in comments.** Name the secret store path or the key name, never a value. Never
  test a leaked credential to prove it is dead; prove the rotation from the system that rotated it.
- **Write as the owner.** Comments are short, plain and specific, in the owner's voice: no AI
  branding, no headers, no praise, no restating the issue. Each one says what was done or what the
  state is, with the PR or evidence that shows it, and an absolute date.
- **Do not wake automation by accident.** Labels such as `stuck`, assignment to a bot, or a
  `/command` in a comment can restart an issue-to-PR agent. Change them only on purpose.
- **Keep people's private matters out of comments.** Verifying an issue can surface that someone
  is leaving, on leave or ill. That can shape the report to the owner; it never goes in a comment.

## 1. Inventory

Pull every issue with what you need to decide, in one paginated GraphQL search, and write it to
files. Keep pages small (`first: 15`): issue bodies are large, and heavy pages return HTTP 502.
Retry a failed page.

```graphql
query($cursor: String) {
  search(query: "assignee:USER is:issue is:open", type: ISSUE, first: 15, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on Issue {
      number title url createdAt updatedAt author { login }
      repository { nameWithOwner isPrivate }
      assignees(first: 10) { nodes { login } }
      labels(first: 15) { nodes { name } }
      body
      comments(last: 6) { totalCount nodes { author { login } createdAt body } }
      closedByPullRequestsReferences(first: 10, includeClosedPrs: true) {
        nodes { number state mergedAt repository { nameWithOwner } } }
      timelineItems(last: 25, itemTypes: [CROSS_REFERENCED_EVENT]) { nodes {
        ... on CrossReferencedEvent { source {
          ... on PullRequest { __typename number state mergedAt repository { nameWithOwner } }
          ... on Issue { __typename number state repository { nameWithOwner } } } } } }
      projectItems(first: 5) { nodes { id project { title number id }
        fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
      subIssues(first: 20) { totalCount nodes { number state repository { nameWithOwner } } }
      parent { number state repository { nameWithOwner } }
    } }
  }
}
```

Write each page straight to a file (`gh api graphql ... > page-N.json`). Do not pass the JSON
through `echo "$out"`: zsh's `echo` turns `\n` inside JSON strings into real newlines and the
result no longer parses. Then build one compact digest from the pages: per issue, the title,
project status, labels, a clipped body, the linked PRs with their state, sub-issues, parent and
the last few comments. Work from the digest; open the full body only for the issue in hand.

Read the project boards' Status fields and enabled workflows once
(`organization { projectV2(number: N) { field(name: "Status") { ... options } workflows { name enabled } } }`).
Many boards close an issue when its card moves to Done ("Auto-close issue") and move the card to
Done when the issue closes ("Item closed"). Know which before you act, so one action does not
silently cause another.

## 2. Sort, then find the shared causes

Put every issue in one bucket before verifying any. The buckets decide what evidence you need:

- **PR-tracking issues whose PR merged.** Common when an agent files an issue for a PR that was
  opened without one: the PR had no closing keyword, so it merged and the issue stayed open. A
  closing keyword also does nothing when the PR merges into a branch other than the default (a
  deploy branch, for example). Check the merged PR against the issue's acceptance criteria, then
  close.
- **PR-tracking issues whose PR is still open.** The state is the PR's state: mergeable or not,
  which required check fails, which review thread is unresolved, whether it is a draft, how old.
  Say exactly what stands between it and a merge. "In progress" alone tells nobody anything.
- **Agent-stuck issues.** An issue-to-PR agent gave up (a `stuck` label, a "stopped working on
  this" comment). Many stuck issues in one repository are almost never many separate problems:
  look for the shared cause. Read the agent's own failure logs before the code: a model gateway
  answering 429 counts as a failed attempt in many agents, so a rate limit can strand a dozen valid
  issues. Other causes: CI red on the default branch, a contract or spec the issue relies on that
  does not exist, a token without a permission, a task too large for one PR. A planner that files
  issues on a timer can also file work that already merged, so compare each stuck issue's title and
  scope with closed issues and merged PRs. Fix the cause or re-scope before re-queuing; re-queuing
  an impossible task only repeats the failure.
- **Epics, work streams and checklists.** Done when every sub-issue is closed and every checklist
  item is verified. Otherwise comment which items remain and who holds each.
- **Audits and finding lists.** Check each finding. When most are fixed, close the audit and file
  one focused issue per remaining finding (or one issue holding the short remainder), linked both
  ways, so the remainder is not buried at the bottom of a long report.
- **Requests from people outside the owner.** Someone is waiting. Handle these first, and put any
  that need the owner at the top of the report. When the request is a setting in the requester's
  own repository and they hold the rights to change it, the fastest answer is how to do it
  themselves.
- **Old backlog** (no activity for months). Still valid, done by other means, or no longer needed?
  Close what no longer has a reason to exist, with that reason. A clear "not planned, reopen if X"
  costs nothing and keeps the board honest.
- **Decisions and proposals for others.** Blocked on a named person, team or vendor. Say on whom,
  and since when.

With many issues, fan out the verification: one read-only agent per repository or group of small
repositories, each given these rules, its issue list, the digest path and the output format. Have
each write a verdict, its evidence and a ready-to-post comment per issue to a file, and do the
posting yourself, so the voice stays consistent and nothing is posted on evidence you have not
read.

## 3. Verify each issue

Read the full body and every comment, and the acceptance criteria if there are any. Then:

- **Merged PR:** on the default branch? Released, if the repository publishes per version? Applied,
  if a controller or pipeline deploys it? Check the effect where it is cheap: the hostname
  answers, the workload runs the new digest, the metric exists, the alert is loaded.
- **Open PR:** `mergeStateStatus`, the required checks (read the ruleset, not just the check
  list), unresolved threads and their authors, draft state, last activity.
- **Live state claims** ("backups work", "audit logging is on"): query the system. A backup
  schedule is not a completed backup; a play in the repository is not a play that ran.
- **Premise:** an issue can be wrong. The thing it asks to fix may be gone, already handled by a
  broader setting, or never have existed. Close those with the reason.
- **Superseded:** search for later work that covers the same outcome under another name before
  you call something not started.

Record what you could not verify. "Not verified: no access to X" is a valid line in a comment or
the report; a guess presented as a check is not.

Verifying agents report things outside their list (a node condition, a failing sync, an expiring
certificate nobody tracks). Check each one before it reaches the report, and file the real ones.

## 4. Act

| Verdict | Action |
| --- | --- |
| Done | Comment what was done, with the PR, and close as completed. |
| Superseded | Comment "Superseded by #N" with one line on why, close as not planned. |
| Not planned | Comment the reason and what would bring it back, close as not planned. |
| Moved | File a short issue in the owning team's backlog, comment the link here, close or unassign. |
| In progress | Comment the dated state and what is left; set the board to In progress. |
| Blocked | Comment on whom or what, since when; set the board to On hold or the board's equivalent. |
| To do | Leave it, or set the board to the backlog column if it sits in an active one. |

- Close children before their parents. A parent whose open children carry the rest of the work on
  their own can close too, naming the child that holds it.
- Fix the board while you are there: move each open card to the column that matches its state.
- An issue mostly done with a real remainder: close it and file one focused follow-up when the
  original is long or noisy; keep it open with the remainder listed when the remainder is the core.
- Small fixes found on the way (a missing test workflow, a one-line image change) are worth a PR
  when the owner allows it. Link the PR from the issue instead of closing the issue early; it
  closes when the PR merges.
- Unassign the owner from issues that are now another team's work, after saying so in a comment.
- Before closing a PR or an issue that holds information found nowhere else (a security finding,
  a list of leftovers), move that information into the follow-up issue first.
- Comment and close in one step per issue (`gh issue close N --comment "..." --reason completed`
  or `--reason "not planned"`), so a partial run never leaves a closed issue with no reason.
- Other sessions and people work the same backlog while you sweep. Re-read each issue's state
  right before acting on it, and skip it if it closed or changed since you verified it.
- A bare `#N` links to the repository the comment is in. Write `owner/repo#N` for every number
  that lives elsewhere, including each one in a list (`owner/repo#1, #2` links `#2` to the wrong
  repository), and avoid a bare `#N` for anything that is not an issue or PR, such as a project
  number.

## 5. Verify and report

Re-run the inventory. Every issue still open needs a state comment that is current, and a board
column that matches it. Then report:

- one row per issue: `repo#number | closed (reason) / open (status) | one line`;
- shared causes found and what was done about them;
- PRs and follow-up issues opened, with links;
- what only the owner can do, item by item, most urgent first (people waiting go first).
