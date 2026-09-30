---
description: Cache a repository's brand, copy and claim facts once so every later launch-video run skips rediscovery - harvest, write the profile, then drive /brag from it
argument-hint: "[nothing for the normal run, 'refresh' to re-harvest, or 'profile-only' to stop before the video]"
allowed-tools: Bash(git:*), Bash(ls:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(wc:*), Bash(sed:*), Bash(awk:*), Bash(sort:*), Bash(uniq:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(cp:*), Bash(mkdir:*), Bash(python3:*), Bash(scripts/brag-harvest.sh:*), Bash(npx:*), Bash(ffmpeg:*), Bash(ffprobe:*), Read, Write, Edit, Grep, Glob, Skill
---

Make a launch video for this repository without paying for brand discovery again.

**First, read the full rubric.** It prescribes the cold and warm runs, the profile schema, the
gotchas ledger, the staleness check and the hard rules. It lives at the first of these paths that
exists (check in order):

1. `.claude/shared/brag-profile.md`, for headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/brag-profile.md`, installed as a plugin
3. `shared/brag-profile.md`, working inside the agent-skills checkout

The harvest script sits beside it, at `scripts/brag-harvest.sh` relative to whichever of those
resolved.

Then read, in this order:

- `.claude/brag/profile.md` in **this** repository, if it exists. That is the cache. If it is
  there and the staleness check passes, it replaces the launch-video workflow's project
  inspection step outright.
- The harvest output, if you had to run one. Read the harvest files, not the source they came
  from.
- Every claim or copy module `50-constraints.txt` names, in full.
- This repository's `CLAUDE.md` and `AGENTS.md`, for copy and vocabulary rules.

Treat target-repository hard rules as blockers. A house rule about what the product may claim
wins over anything the rubric or the video workflow suggests.

**Hard rules, which hold even if the rubric file cannot be found:**

- **The budget never comes out of verification.** Run the video workflow's own pre-render gate,
  and look at rendered frames before calling it done. The measured run's visual pass caught four
  defects that no automated gate reported. Skipping it is not a token saving, it is a worse video.
- **The profile caches facts, never creative choices.** Palette, verbatim copy, claim
  constraints, which screens carry the flow. Never the tone, the hook or the storyboard. Cache
  those and every video is the first video again.
- **Verbatim means verbatim.** Every cached line carries its source path. Paraphrasing a
  product's own copy is how an unearned claim reaches a public video.
- **A claim constraint is a promise, not a style note.** Where the repository says a guarantee
  covers one artefact and not another, say exactly that. Do not widen it into marketing voice.
- **Never commit harvest output.** It is scratch, outside the repo. `.claude/brag/profile.md` and
  `.claude/brag/composition.head.html` are the committed artefacts.
- **Re-harvest rather than trust a stale profile.** Run the staleness check before using a cached
  profile, and say in the report which sections came from cache and which were re-read. A
  confidently wrong palette is worse than no profile.
- **Never invent a fact to fill a schema section.** A section the harvest could not answer is
  written as unknown, with the reason. An invented hex or a guessed tagline is worse than a gap,
  because the next run inherits it without the doubt.
- **Don't improvise a video pipeline.** If the launch-video workflow is not installed, do the
  profile half, say what is missing, and stop.
- **Write the changes, then show them.** Don't stop mid-run to ask permission. Never commit, push
  or open a PR. End with a dirty working tree and a report.

End with a short report: which run it was (cold or warm), what the profile covers, which sections
were re-harvested and why, where the video and its share copy landed, and any profile section the
harvest could not answer.

Mode: $ARGUMENTS
