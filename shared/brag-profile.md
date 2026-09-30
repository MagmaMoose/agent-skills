# brag-profile: make the second launch video cost a fraction of the first

This wraps the launch-video workflow (`/brag` where it is installed) so a repository pays for
brand and product discovery **once** instead of on every run.

It is not a different video workflow. The creative rubric, the storyboard, the tone system, the
audio direction and the render loop all stay with `/brag`. This adds a cache in front of it, a
template behind it, and a ledger of the failures that cost round trips the first time.

## The honest token arithmetic

Measured on one cold run: build a 21.8s launch video for a React/Vite console with a
CI-enforced design system. That session ended at **310k tokens** of context.

Roughly where it went, and whether a second run can avoid it:

| Cost | Cold run | Avoidable | How |
| --- | --- | --- | --- |
| Product and brand discovery | ~15k | **yes, nearly all** | harvest + profile |
| Reading the whole tone catalogue to pick one tone | ~2.5k | **yes** | tone pinned in the profile |
| Composition boilerplate: `@font-face`, token `:root`, scene CSS | ~6k | **yes** | saved template |
| Round trips fixing the same lint and check findings | ~4k | **yes** | gotchas ledger |
| Catalog detour that ended in a deleted block | ~2k | **yes** | ledger records the dead end |
| Video framework references (composition contract, animation, CLI) | ~19k | no | external, and the contract changes between versions |
| Authoring the composition itself | ~20k | no | it is different every time |
| Render verification (contact sheets are images) | ~4k | no | this is the check that catches real defects |

So: **roughly a third off a repeat run in a profiled repository**, concentrated entirely in
re-derivation. Anyone promising more than that is proposing to skip the verification, which is
the part that caught four real defects in the measured run.

The saving compounds differently than it looks. The profile is also *better* than what a cold
run reconstructs under time pressure, because the harvest reads files a cold run never opens.

## Two runs

### Cold run: no `.claude/brag/profile.md` in the target repo

1. **Harvest.** From the agent-skills checkout or the installed plugin:

   ```bash
   scripts/brag-harvest.sh <repo-root> ./harvest/brag
   ```

   Read-only. Writes seven small files outside the repo. On a 1,500-file repository the whole
   output is around 18 KB, and `10-tokens.txt` alone replaces a grep over a design-token file
   that can cost five figures in tokens when every token carries a rationale comment.

2. **Read the harvest, not the source.** `00-identity`, `10-tokens`, `20-fonts`, `30-copy`,
   `40-surfaces`, `50-constraints`. Open original files only where the harvest points at
   something it could not resolve, and only the lines it named.

3. **Read `50-constraints.txt` properly.** This is the section with public consequences. Open
   every claim module it lists, in full. A launch video is permanent and external; a claim the
   repository forbids is not a style nit.

4. **Write `.claude/brag/profile.md`** in the **target** repo, to the schema below. Commit it.

5. **Run the launch-video workflow** with step 1 (project inspection) already answered by the
   profile. Hand the profile in place of a fresh inspection.

6. **After `check` passes**, save two artefacts back into the target repo:
   - `.claude/brag/composition.head.html`, holding the `@font-face` block, the token `:root` block and
     the shared scene CSS from the composition that just passed. Not the scenes.
   - the gotchas section of the profile, updated with every finding that cost a round trip.

### Warm run: the profile exists

1. Read `.claude/brag/profile.md`. That is the whole of step 1.
2. Re-run the harvest **only** if the staleness check below trips.
3. Start the composition from `.claude/brag/composition.head.html`.
4. Read the gotchas section before authoring, not after `check` fails.
5. Everything else is the normal launch-video workflow.

## The profile schema

`.claude/brag/profile.md` in the target repository. Target 120 lines. It is a **facts** file:
what the product is and what the house rules are. Creative decisions belong in each run's plan,
not here, because baking them in produces the same video twice.

```markdown
# Brag profile: <product>

Harvested from <commit sha> on <date>. Re-harvest when the staleness check trips.

## Identity
Name, one-line description, the domain, what it actually does in one sentence.

## Verbatim copy
The lines a video may use word for word, each with its source path. Hero, sub, the
step names, the pricing fineprint, the outro line.

## Palette
Only the tokens a video uses: ground, raised surface, code ground, accent (and its
gradient end), text at each step, status colours, hairline. Name, hex, and what the
house uses each one for. Fifteen lines, not the whole token file.

## Type
Display face, body face, mono face. Where the files are. Which roles each face is
pinned to, and which roles it must never take.

## Surfaces worth filming
The two or three screens that carry the product's flow: entry, key action, result.
Name the component that renders each, so a run can rebuild it rather than invent it.

## Claim constraints
What may be asserted, what may not, and the file that decides. Quote the exact
allowed phrasing. Name the test that enforces it.

## Copy rules
Vocabulary bans, punctuation bans, identifier bans. Each with its source line.

## Assets
Logo or badge path, favicon, any brand SVG a video can inline.

## Gotchas
See below. Append-only.

## Staleness
The paths whose change invalidates this profile.
```

## The gotchas ledger

Append-only, inside the profile. One line per finding that cost a round trip, with the fix.
This is the section that stops the second run rediscovering the first run's afternoon.

A finding earns a line when it was **silent**: the build was green, the check passed, or the
failure looked like something else. A typo does not earn a line.

From the measured run, as a shape to copy:

- `white-space: pre` in a code or terminal panel preserves the **source** line breaks, so a
  command formatted across several source lines wraps mid-token in the render. Put each rendered
  line on one source line.
- A masked line reveal needs `line-height` near 1.16 and a small `padding-bottom` on the mask, or
  descenders clip at rest.
- Entry states belong in CSS (`opacity: 0`), not a page-load `set`: a later scene's children are
  painted between its clip opening and their own tween. Never pair a CSS `transform` with a tween
  on the same property.
- A static gain plus a tween on the same audio property fight rather than compose. Let one carry
  the level, and give the hold between fades its own explicit keyframe.
- Two `fromTo` calls on one element need `immediateRender: false` on the later one, or its
  from-values become the resting state for every seek before the first tween.
- Check the component catalog before hand-authoring a named visual, but record the dead ends:
  installing and deleting a block that carries its own palette costs two round trips and buys
  nothing when the brand is strict.

## Staleness

Re-harvest when any of these changed since the profile's recorded commit:

```bash
git diff --stat <profile-commit>..HEAD -- \
  '**/tokens.css' '**/theme*.css' '**/fonts*.css' \
  '**/[Ll]anding.*' '**/claims.*' 'CLAUDE.md' 'AGENTS.md'
```

Empty output means the profile stands. Anything else means re-harvest those sections, not the
whole file, and update the commit line.

A profile older than six months gets re-harvested regardless. Silent drift is the failure mode
this whole workflow exists to avoid, and a confidently wrong palette is worse than no profile.

## Hard rules

- **The profile records facts, never creative decisions.** Palette, copy, constraints, surfaces.
  Not tone, not the storyboard, not the hook. Cache the second kind and every video is the first
  video again.
- **Verbatim copy is copied, not paraphrased.** Every line in the profile's copy section carries
  its source path so a run can check it is still true. A paraphrase is how an unearned claim gets
  into a public video.
- **Claim constraints are not advisory.** If the repository says a guarantee holds for one
  artefact and not another, the video says exactly that. Widening it in a marketing voice is the
  specific failure these files exist to prevent.
- **Never skip `check`, and never skip the visual pass.** The token budget does not come out of
  verification. Snapshot the key frames and look at them; on the measured run that pass caught
  wrapped terminal text, an orphaned headline word, a footnote sitting inside a panel, and a
  decorative element below video-legible opacity, none of which any automated gate reported.
- **The template is a starting point, not a lockfile.** If the framework's contract moved, the
  saved head is wrong. Re-read the composition contract when its version changed.
- **Never commit the harvest output** into the target repository. It is scratch. The profile is
  the committed artefact.
- **Do not fork this workflow per product.** The mechanism lives here; every product-specific
  fact lives in that product's own `.claude/brag/profile.md`.

## When the launch-video workflow is not installed

This wrapper degrades to its useful half: run the harvest, write the profile, and stop. Say
plainly that the video step needs the launch-video workflow and name what is missing. Do not
improvise a replacement video pipeline.
