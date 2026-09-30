---
name: brag-profile
description: Cache a repository's brand, copy and claim facts once - palette, fonts, verbatim marketing copy, which screens carry the product flow, and what the repo forbids claiming - so every later launch-video run skips rediscovery and starts from a known-good composition template instead of a blank file.
---

Use the shared MagmaMoose brag-profile workflow.

Read and follow:

- `shared/brag-profile.md`: read this ALWAYS, before running anything
- `.claude/brag/profile.md` in the target repository, if it exists. That is the cache
- The harvest output, if a harvest was needed, in place of the source it came from
- Every claim or copy module that `50-constraints.txt` names, in full
- The target repository's `CLAUDE.md`, `AGENTS.md` and `CONTRIBUTING.md`

Treat target-repository hard rules as blockers. A house rule about what the product may claim
wins over anything the rubric suggests.

Expected input:
- Nothing, for the normal run.
- `refresh`, to re-harvest and rewrite the profile even when the cached one looks current.
- `profile-only`, to build the cache and stop before the video.

## Why this skill exists

A launch video needs a narrow set of facts about a product: what it is called, what it claims,
which two or three screens carry its flow, which hexes and faces are the house's, and which
sentences it is allowed to say out loud. Those facts change on the order of months. Rediscovering
them costs real tokens every run, and a rushed rediscovery is also *worse* than a careful one,
because the expensive files are the ones a hurried pass never opens.

The worst case is a mature design system. A house token file can carry a paragraph of rationale
per token, so the obvious `grep '^\s*--'` returns tens of thousands of tokens of prose to recover
fifteen hex values. `scripts/brag-harvest.sh` strips the prose and keeps the values.

## What it does

**Cold run.** Harvest the repository read-only into seven small files. Read those instead of the
source. Open the claim modules in full, because that is the section with public consequences.
Write `.claude/brag/profile.md` to the schema in the shared rubric and commit it. Then run the
launch-video workflow with its project-inspection step already answered.

**Warm run.** Read the profile. Run the staleness check. Start the composition from the saved
`.claude/brag/composition.head.html`. Read the gotchas ledger before authoring rather than after
a check fails.

**After every run.** Append any finding that cost a round trip to the ledger, and refresh the
saved template if the composition that passed improved on it.

## What it does not do

It does not replace the launch-video workflow's creative rubric, tone system, storyboard, audio
direction or render loop. It does not reduce the cost of reading the video framework's own
contract, which changes between versions and has to be read fresh. It does not save anything on
authoring the composition, which is different every time.

Measured on one cold run that ended at 310k tokens of context, the honest figure is roughly a
third off a repeat run in a profiled repository. The saving is entirely re-derivation. None of it
comes out of verification, and the rubric's hard rules say so explicitly, because on that run the
visual pass caught four defects no automated gate reported.

## Hard rules

- The profile caches facts, never creative choices. Cache the tone or the hook and every video is
  the first video again.
- Verbatim copy is copied with its source path, never paraphrased.
- A claim constraint is a promise. Where the repository scopes a guarantee to one artefact, the
  video scopes it the same way.
- Never commit harvest output. The profile and the template are the committed artefacts.
- Never invent a fact to fill a schema section. Write it as unknown, with the reason.
- Never skip the pre-render gate or the visual pass.
- If the launch-video workflow is not installed, do the profile half, name what is missing, and
  stop rather than improvising a replacement pipeline.
