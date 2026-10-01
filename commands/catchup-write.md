---
description: Write a welcome-back report for a colleague returning from leave - what shipped, what was discussed, what waits for them - as one HTML page with an animated recap, via the catchup CLI
argument-hint: "[who: an alias or email] [--from YYYY-MM-DD --to YYYY-MM-DD]"
allowed-tools: Bash(catchup:*), Bash(transcribe:*), Bash(gh:*), Bash(claude:*), Bash(uv:*), Bash(ls:*), Bash(cp:*), Bash(mkdir:*), Read, Write, Edit
---

Write a welcome-back report for a colleague using the shared MagmaMoose catchup-write workflow.

**First, read the full rubric.** It covers preflight, the away dates, getting the meeting notes
in (including Teams transcripts that no script can fetch), the run, the mandatory review of the
page, and the hard rules. It lives at the first of these paths that exists (check in order):

1. `.claude/shared/catchup-write.md`, for headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/catchup-write.md`, installed as a plugin
3. `shared/catchup-write.md`, working inside the agent-skills checkout

**Hard rules, which hold even if the rubric cannot be found:**

- **Drive the CLI.** Do not rebuild the report from connector calls. Read `facts.md` only when
  writing the prose yourself, and never read `raw/*.json`.
- **Privacy lives in the collectors.** The report holds only what the reader could have seen.
  Never add your own chats, mails or private meetings. Leave out health, family, HR and any
  friction between people.
- **Numbers come from code.** Never edit `pack.json` and never state a count the facts lack.
- **Review the page before handing it over.** Fix lines in `report.json` and re-render rather
  than rewriting.
- **Never send, post or publish the report.** Hand the path to the user.
- The Microsoft 365 sign-in is a device code: the user signs in, you wait.

End with the path to `report.html`, the dates it covers (and whether the leave has ended), which
sources were used or skipped and why, and the command for the return-day re-run.

Input: $ARGUMENTS
