---
description: Draw an architecture diagram that is verified against the live system, iterated against its own screenshots, and committed as editable Excalidraw source plus the explanation underneath
argument-hint: "[what to diagram - a system, a repo, a flow, or empty for the repo you are in]"
allowed-tools: Bash(npx:*), Bash(kubectl:*), Bash(flux:*), Bash(helm:*), Bash(kustomize:*), Bash(jq:*), Bash(yq:*), Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(grep:*), Bash(fd:*), Bash(find:*), Bash(ls:*), Bash(python3:*), Bash(node:*), Bash(bash:*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

Draw an architecture diagram using the shared MagmaMoose diagram workflow.

**First, read the full workflow** — it prescribes the verify-before-drawing rule, the
screenshot-and-fix loop, arrow routing, the colour and sizing conventions, the deliverable
structure, and the named failure patterns. It lives at the first of these paths that exists
(check in order):

1. `.claude/shared/diagram-draw.md` — headless runs (installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/diagram-draw.md` — installed as a plugin
3. `shared/diagram-draw.md` — working inside the agent-skills checkout

Then read:
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any existing diagrams in the repository, and match their conventions rather than inventing new ones
- Any `COMMON_MISTAKES` or footgun log the repository keeps

Treat target-repository hard rules as blockers. An existing diagram format or a propose-only
policy in the target repo wins over the workflow.

The two things that most often go wrong, so do them deliberately:

- **Verify where every component actually runs before drawing any box.** Group by deployment
  boundary, never by topic. A box in the wrong boundary survives review and gets built against.
- **Screenshot every render and look at it.** Four to six iterations is normal. The first layout
  is never the one to ship.

Ship the `.excalidraw` source alongside the PNG, the SVG and the markdown. Someone will need to
change the diagram without you.
