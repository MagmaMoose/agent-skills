---
name: diagram-draw
description: Draw an architecture diagram grounded in the live system rather than the repository, iterate it against its own screenshots until it is actually readable, and ship editable Excalidraw source plus the explanation underneath it.
---

Use the shared MagmaMoose diagram workflow.

Read and follow:
- `shared/diagram-draw.md`
- The target repository's `CLAUDE.md`
- The target repository's `AGENTS.md`
- The target repository's `CONTRIBUTING.md`
- Any existing diagrams in the repository, and match their conventions rather than inventing new ones
- Any `COMMON_MISTAKES` or footgun log the repository keeps

Treat target-repository hard rules as blockers. An existing diagram format or a propose-only
policy in the target repository wins over this workflow.

Expected input:
- A hint about what to diagram (a system, a repository, a flow, an environment), or nothing at
  all, which means the repository you are in.

## The two rules that carry most of the value

**Verify where every component actually runs before drawing any box.** A diagram is a claim about
reality, and the expensive error is a box in the wrong boundary, not an ugly layout. Group by
deployment boundary, never by topic: grouping by subject matter reads beautifully and invents
network boundaries that do not exist.

**Never ship the first render.** Generate, screenshot, look at the image as a reader would, fix
the worst problem, repeat. Four to six iterations is normal, each one is cheap, and shipping a
wrong one is not.

Ship the `.excalidraw` source alongside the PNG, the SVG and the markdown walkthrough. The source
is the deliverable that matters, because someone will need to change the diagram without you.
