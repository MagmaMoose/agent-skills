# Architecture diagram workflow

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` and
relevant `README.md` files, plus any `COMMON_MISTAKES` or footgun log it keeps. Treat explicit
hard rules from the target repository as blockers: a propose-only policy, a documented diagram
convention, or an existing diagram format all win over this file.

You are producing an architecture diagram that a senior engineer will argue with, commit, and
still trust in six months. Not a picture. The deliverable is a diagram plus the explanation
underneath it, both in the repository, with the editable source committed next to them.

## The one rule that matters most

**Verify the topology against the live system before you draw a single box.**

A diagram is a claim about reality. The most expensive diagram error is not an ugly layout, it is
a box in the wrong place, because that error survives review, gets built against, and is quoted
back months later as though it were a decision. Repositories describe intent; the running system
describes what is. Draw the second one, and mark intent as intent.

The specific failure to avoid: grouping components by *what they are about* rather than *where
they run*. Putting the knowledge-base tooling in a "knowledge" box and the sync tooling in a
"sync" box reads beautifully and is wrong if both are namespaces in the same cluster. That
implies a network and trust boundary that does not exist, and it is exactly the kind of error
that gets designed against.

So, before drawing:

- Enumerate every component and ask where each one actually runs. One of: this cluster, that
  cluster, a managed cloud service, a third party, a git repository, or nowhere yet.
- `kubectl get ns`, then list workloads across all namespaces, and check the operators too
  (CloudNativePG clusters, HelmReleases, Flux Kustomizations). A database is a workload.
- For anything that does not exist yet, find where the design says it will run and label it as
  not-yet-built. Never draw a proposal and a running system in the same visual style.
- Test the boundaries you are about to draw. If you are drawing an arrow across a network
  boundary, prove the path exists, or draw it and mark it blocked.

Write down what you verified and when. State goes stale and an unmarked diagram is assumed current.

## What the diagram is for

Decide this first, in one sentence, and let it decide every other choice.

- **"Where does everything run?"** Boundaries are the message. Group by deployment boundary, then
  by namespace or account. Flow arrows are secondary and should be thinned or numbered.
- **"What happens when X occurs?"** Sequence is the message. One spine, top to bottom, numbered.
  Boundaries become background.
- **"What talks to what?"** Dependencies are the message. Neither of the above; this wants a
  different shape and probably fewer nodes.

A diagram that tries to be all three is the one that gets redrawn. If you genuinely need two, draw
two, but expect to be told to merge them: readers strongly prefer one diagram with the explanation
underneath, and will accept a denser picture to get it.

## Tooling

Use `mcp-excalidraw-server`. It is MIT, runs locally, needs no API key, and unlike a renderer it
lets you look at your own work.

```bash
npx -y mcp-excalidraw-server start          # auto-starts anyway on first canvas command
npx -y mcp-excalidraw-server status         # browserClients must be >= 1 for screenshot/mermaid
npx -y mcp-excalidraw-server add scene.json # elements as a JSON array
npx -y mcp-excalidraw-server screenshot --out shot.png
npx -y mcp-excalidraw-server export --out diagram.excalidraw
npx -y mcp-excalidraw-server screenshot --format svg --out diagram.svg
npx -y mcp-excalidraw-server clear --yes
npx -y mcp-excalidraw-server stop
```

Open `http://127.0.0.1:3000` in a browser pane first. `screenshot` and `mermaid` return exit code
4 without a browser tab attached.

Two traps that cost real time:

- **`clear` needs `--yes`.** Without it, it fails, and the next `add` merges onto the old scene.
  You will then spend a while debugging a layout that is actually two layouts on top of each
  other. Check `status` reports `elementCount: 0` before re-adding.
- **`add` takes a positional file**, not `--file`.

Generate the scene from a small script rather than writing JSON by hand. Coordinates need to be
computed, and you will re-render a dozen times. Keep every rectangle in one dictionary keyed by
name so arrows can reference `(x, y, w, h)` and anchor by proportion.

If Excalidraw is unavailable, Mermaid via `@mermaid-js/mermaid-cli` is the fallback, but it picks
its own layout, so you cannot fix a boundary that lays out badly. Prefer Excalidraw whenever the
grouping matters, which for architecture is always.

## The loop that actually produces a good diagram

**Never ship the first render.** Expect four to six iterations. Each one is cheap; shipping a
wrong one is not.

1. Generate the scene.
2. `add` it and `screenshot`.
3. **Actually look at the image.** Read it as a reader would, not as the person who placed the
   boxes.
4. Fix the worst problem. Re-render.

What to look for, in order of how badly it hurts:

- **A box in the wrong boundary.** Stop and re-verify against the live system.
- **Text overflowing its box.** Labels do not auto-shrink. Either widen the box, shorten the
  text, or insert explicit newlines. A three-word name in a two-word box reads as a different
  name.
- **An arrow crossing a box it has nothing to do with.** The reader will infer a relationship
  that does not exist. Reroute through a lane, move the boxes, or delete the arrow.
- **Two labels overlapping.** Almost always two arrows between the same pair of nodes in opposite
  directions. Shorten both labels to bare numbers and move the words to the walkthrough.
- **A label sitting on top of a box.** Arrow labels land at the arrow's midpoint; if that
  midpoint is over a box, the label is unreadable.

### Routing arrows without spaghetti

- **Anchor by proportion, not by edge.** `(0.1, 1)` and `(0.7, 1)` are two different exits from
  the same bottom edge, which is how two arrows between the same pair stop overlapping.
- **Leave lanes.** A 20px gap between columns, and the margin inside a group box, are where
  long arrows travel. Reserve them deliberately instead of discovering you need them.
- **Elbows beat diagonals** for anything travelling past more than one box. A multi-point arrow
  down a lane and along a gutter reads better than a diagonal through three rectangles.
- **Place the boxes to suit the arrows.** If two nodes are connected, put them adjacent. Most
  routing problems are layout problems wearing a disguise, and reordering two boxes is cheaper
  than routing around them.
- **Delete arrows.** A secondary relationship that needs a 600px detour is better as one sentence
  in the text. Ask of every arrow: if I remove this, does the reader misunderstand something? If
  not, remove it.
- **Aggregate honestly.** Three arrows from three workloads to one shared database can be one
  arrow between the two group boxes, *if* you say in the text that you did this and where the
  precise version lives. Silent aggregation is a lie; declared aggregation is a diagram.

### Labels

Put numbers on the spine and the words underneath the diagram. `1`, `2`, `3` never collide;
`1 poll` and `12 PUT action` always do. This also forces the walkthrough to exist, which is the
half of the deliverable people skip.

## Conventions

Consistency matters more than the specific palette. Pick one and apply it.

| Role | Fill | Stroke |
| --- | --- | --- |
| External system, another team's, a SaaS | `#ffd8a8` | `#b45309` |
| Our workload, primary path | `#a5d8ff` | `#2563eb` |
| Our workload, secondary or model-facing | `#d0bfff` | `#7c3aed` |
| Datastore | `#c3fae8` | `#0f766e` |
| Adjacent product, ours but not on this path | `#b2f2bb` | `#15803d` |
| Deployment boundary (cluster, cloud region) | `#dbe4ff` at `opacity: 40` | `#4a9eed` |
| Grouping inside a boundary (namespace) | `#f8f9fa` | `#868e96` dashed |

Sizing, for a diagram that will be read at about 700px wide before anyone zooms:

- Body text 14 minimum, titles 20+. Never below 13.
- Boxes at least 200 x 64 when they carry two lines of text.
- 20px between boxes, 20px of padding inside a group box.
- Keep the whole scene near 4:3. Taller is fine when the flow is a sequence, but past about 1.5:1
  the text is unreadable before the reader thinks to zoom.

### Naming

Name things for what they do, not for the vendor they happen to talk to. A workload named after
the log store it queries reads as though it belongs to whoever owns that store, and the name rots
the day the store changes. The same applies to a name that conflates a workload with the identity
it authenticates as: those are two different things and only one of them is the workload.

Raise naming problems while drawing. A diagram is the first time everyone sees all the names
side by side, which makes it the cheapest moment to fix them.

## The deliverable

Commit four things, next to each other:

1. `<name>.excalidraw`, the editable source. **This is the important one.** Someone will need to
   change this diagram without you.
2. `<name>.svg`, which scales without limit, for zooming.
3. `<name>.png`, for pasting into slides and for inline rendering, which is guaranteed to work
   everywhere SVG is not.
4. `<name>.md`, the diagram inline with the explanation underneath.

Reference the PNG inline and link the SVG behind it, so it renders on every forge:

```markdown
[![Alt text](name.png)](name.svg)
```

The markdown must contain, in this order:

- **What the diagram is for**, in a sentence, and what it deliberately does not show.
- **The diagram.**
- **Where the source is** and how to edit it.
- **Any simplification you made**, named explicitly. Aggregated arrows, a second environment not
  drawn, a proposal drawn beside a running system.
- **The numbered walkthrough**, matching the numbers on the spine.
- **The decisions and why**, including the ones that were rejected. This is the part that is
  still useful in six months.
- **What is not built yet**, as a table, with evidence and a date. A diagram of the intended state
  reads as a description of the current state unless you say otherwise on the same page.

## Failure patterns

- **The beautiful wrong grouping.** Grouped by topic instead of by where things run. Passes
  review because it reads well. See the rule at the top.
- **Shipping render one.** The first layout is never the best one and you have a screenshot tool.
- **The orphan box.** A component with no arrows because routing to it was hard. Either connect
  it or cut it.
- **Silent aggregation.** Collapsing edges for readability without saying so, so the reader takes
  the simplification for the design.
- **Intent drawn as fact.** Proposed components in the same style as running ones. Always
  distinguish them, and always date the state.
- **The undated diagram.** Correct when drawn, quoted as current two quarters later.
- **A picture with no words.** The diagram carries the shape; the text carries the reasoning. A
  diagram alone loses every "why" the moment you leave the room.
- **Mermaid for a boundary-heavy diagram.** The layout engine will put your boundary box where it
  likes, and you will spend longer fighting it than you would have spent placing boxes.
