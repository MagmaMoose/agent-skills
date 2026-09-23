# Docs anonymisation: the human half

Before acting, read the target repository's `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` and
relevant `README.md` files. Treat explicit hard rules there as blockers.

[docs-distributor](https://github.com/MagmaMoose/docs-distributor) publishes private
documentation into a public docs site, anonymised through a private mapping and stopped by a
deterministic leak gate whenever something slips through. It decides nothing a human should
decide: which words are sensitive, what stands in for them, and whether a blocked run's
proposals are right. This workflow is that human half.

It covers three jobs:

1. **The policy**: what gets replaced, what is kept on purpose, and the placeholder scheme.
2. **Triage** a run the novelty gate blocked, and extend the mapping.
3. **Onboard** a new source with `docs-distributor onboard`.

It does not restate how the pipeline works or what the model is asked; that is the tool's
`README.md` and `prompts/`, versioned with the code. Read the README's trust model once
before your first triage.

## Hard rules

- **Real values never go anywhere public.** Not in the tool's repository, not in the docs
  repository, not in a commit message, pull-request body, issue, chat message or code
  comment. The mapping lives in the secret store and in `~/.config/docs-distributor/`
  (mode 0600) on the maintainer's machine, nowhere else.
- **Public text does not point at a leak either.** A public PR that says which page still
  shows a real name tells every reader where to look. Report a leak privately, fix it in the
  mapping, and describe the fix without describing what it fixed.
- **Fail closed.** If you are unsure whether a term identifies the source, map it. A wrong
  "sensitive" costs a stand-in; a wrong "public" publishes a name, and a published name
  cannot be taken back: forks, caches and search indexes keep it after any force-push.
- **Never loosen the gate to get a run through.** An allowlist entry is a verified-public
  fact with a reason a stranger can check. If the gate flags something real, change the
  mapping; if it flags something public, allowlist it with its `why`.
- **Private output stays private.** Run reports, proposals, `audit --show-matches` output
  and a `plan --out` tree from a failed run can all hold real values. Keep them under
  `~/.config` or `~/.cache`, never in a repository or a paste.

## The policy

### Replace

| What | Why it identifies | Typical stand-in |
|---|---|---|
| The organisation, its business units and their abbreviations, in every spelling and case | Obvious | `example-org`, `example-corp` |
| Repository, cluster, account and resource names built from those abbreviations (`hbx-prod-web`, `hbxlogsprod`) | Compound identifiers carry the brand | the same shape with the stand-in prefix |
| Customers, their domains and the departments or sites in them | A customer list identifies its supplier | `client-j`, `client-j.example` |
| People: names, initials, handles, mailbox local parts, home-directory paths | Obvious, and handles are searchable | `engineer-e`, `platform-lead@example.org`, `~` |
| Internal products, systems, bots and codenames | Unique names are searchable | `product-C`, or a plain descriptive name |
| Vendors small or regional enough to narrow the field, and the places they operate from | A small vendor plus a city is a short list | `vendor-C`, `Site-A` |
| National or sector standards, regulators, laws, and local-language words in English text | Together they narrow the country and the sector to a handful of organisations | a generic name (`StandardA`), or the English word |
| Every opaque identifier: subscription, tenant, zone and vault-item IDs, ticket numbers, key recipients | Unique by construction | a stand-in of the same shape |
| Tools, bots and orgs whose owner is public | The owner's public profile leads back to the source | a name for what it does |

### Keep, on purpose

- **Public technology**: products, projects, protocols, file formats, cloud services and
  region names used by thousands of organisations. Removing them destroys the technical
  value and hides nothing.
- **Large public vendors** whose mention narrows nothing (a hyperscaler, a CDN, a code host).
- **Private addresses** (RFC 1918) and generic internal names (`wiki`, `backoffice`) that
  identify nothing on their own. The gate allows RFC 1918; public addresses always move to
  RFC 5737.
- **Anything the reader needs to act on the page**: command shapes, file layouts, the
  reasoning behind a decision.

When a term is both (a public product name that is also the source's internal nickname),
map the internal use with a longer, more specific rule and let the public one through.

### The placeholder scheme

The published corpus already uses a scheme, recorded in docs-distributor's
`src/docs_distributor/rules/vocabulary.yml`. Extend its series rather than starting new
ones: the next customer is the next `client-*`, the next vendor the next `vendor-*`, the
next person the next `engineer-*`. The tool assigns series stand-ins itself, and refuses a
placeholder that would fail the gate on its own (a stand-in on a real TLD is somebody's
domain; use `.example`, `example.com/.net/.org`, RFC 5737 and the vocabulary's UUID and
account shapes).

A stand-in must never contain the value it replaces, any part of it, or a near-spelling. If
the tool refuses a rule because "its placeholder contains a real value", believe it.

## Triage a blocked run

A run that meets a name nobody has decided about publishes nothing and exits `2`. It files
(or updates) one issue on the tool's repository with counts, classes and proposed stand-ins,
naming no term, and writes the full proposal to its private run report.

1. **Get the proposal.** It is `<run>/mapping-proposal.yml` under the reports directory on
   the CronJob's state volume. The job's pod is gone by then, so `kubectl cp` it from a
   short-lived pod that mounts the claim, into `~/.config/docs-distributor/`. Or reproduce
   it locally with `plan --offline` (step 4): without the model, the same terms come out
   undecided in the local report.
2. **Decide each term.** Map it (sensitive), allow it (public), or add it to `deny:` (must
   never appear, and has no stand-in). The model's classification is a suggestion; the
   decision is yours. Read the term in its context first: the same word can be a public
   product in one line and a customer in the next.
3. **Write the rule well** (see *Writing rules*).
4. **Prove it locally** before touching the secret. The mapping is read from
   `~/.config/docs-distributor/mapping.d` by default:

   ```bash
   docs-distributor plan --config ~/.config/docs-distributor/plan-config.yml \
     --source <alias>=<local checkout> --offline \
     --out ~/.cache/docs-distributor/plan-out
   ```

   Add `--docs-repo <checkout>` to plan against a local copy of the docs site. Iterate until
   it exits `0`: no candidates, all three gate layers passed, and parity, links and
   `mkdocs build --strict` green. A blocked or failed plan says what to fix in its private
   run report (`report.dir` in the config; pass `--report-dir` to keep it under `~/.cache`).
5. **Read the output** the way the gate cannot (see *The human read*).
6. **Update the secret** behind the chart's `secrets.keys.mapping`, then run the job by hand
   (`kubectl create job --from=cronjob/<cronjob> <cronjob>-manual`) or wait for the next
   scheduled run.

## Writing rules

- **Case.** The gate matches every real value case-insensitively, whatever the rule says.
  Use `case: preserve` when the stand-in should follow the original's case (`Hollowbrook`
  → `Example-org`, `hollowbrook` → `example-org`). Use `case: exact` only to split one value
  into per-spelling rules (`HollowBrook` → `ExampleCorp`, `hollowbrook` → `example-corp`),
  and cover every spelling that appears, or the gate stops the run on the one you missed.
- **Boundaries.** The default matches values under five characters as whole words only.
  Use `boundary: none` for a distinctive long token that also appears glued inside
  identifiers (`hollowbrookStacks`, `hollowbrook_staging`); never for a short or common one.
- **Short values.** An abbreviation that is also an ordinary word (`MAP`) would hit every
  use of the word, because the gate ignores case. Map its specific forms instead
  (`MAP platform`, `map-prod`).
- **Compound identifiers.** Map the brand-bearing prefix with `boundary: none` and keep the
  generic remainder: `hbxlogsprod` → `exlogsprod` still reads as the same kind of thing.
- **Truncations.** Put the FULL value in the mapping, even when the docs only ever show
  `1a2b3c4d…`: find it in the source's IaC. The substituter then turns any truncation into
  the same-length prefix of the stand-in, and the gate's truncation check has something to
  test against.
- **One word, two meanings.** When the same word names two things in the source (a place
  and a customer, a product and a team), map the more specific forms with longer rules
  (`eastside-portal`, `Eastside Logistics`) and let a general rule take the rest. The longest
  match wins.
- **Time zones.** Replace a revealing zone with one on the same UTC offset and daylight
  saving rules (`America/Toronto` → `America/New_York`), so every documented schedule stays
  correct.
- **Paths.** Real names in file and directory names are replaced like any other text. Give
  a page a readable name with `sources.<alias>.rename` when the automatic one is clumsy.
- **Links.** Add a private host to `links.private_hosts` and every link into it becomes a
  code span of its text. A public site that would identify the source (a national
  regulator, a sector standard's home page) belongs there too.
- **Regex rules** exist, and they are the last resort: their `to` may not copy groups, and
  the gate cannot derive a literal from them.
- **Reviewed lists.** Terms you have read and judged safe go in the private mapping as
  `allow_terms: {why: ..., values: [...]}`, so they are never asked about again. Only a
  generic public fact belongs in the tool's committed `allow.yml`.

## Onboard a new source

1. **Candidates.** Run `docs-distributor onboard <checkout> --name <alias> --out
   ~/.config/docs-distributor/onboarding/proposal.yml`, or add `--offline` to list the
   candidates without asking the model. Choose the alias carefully: it appears in branch
   names, nav markers and logs, so it must not name the organisation.
2. **Sweep what novelty cannot see.** The scan only asks about words that look like names
   and are not English. Grep the source yourself for domains, emails, UUIDs, public
   addresses, `@handles`, local-language words, and names that are also common words;
   `docs-distributor audit <checkout>` is a quick first pass.
3. **Build the mapping**, one private file per concern under `mapping.d/` if it helps, then
   iterate with `plan --offline` (see *Triage*) until the run is green.
4. **The human read** below, on the full generated tree.
5. **Wire it up.** Add the source to the chart values with its public alias and target
   directory only; its clone URL goes in the private mapping as `sources.<alias>.url`. Add a
   read-only token for it to the secret. Split the mapping across several secret keys when
   the store has a size limit; the chart merges them in order.

## The human read

The gate proves the absence of what the mapping and the pattern classes know about. It
cannot prove the absence of what nobody told it about. Before the first publish of a
source, and after any large mapping change:

- skim the generated index page, and the pages with the most organisation-specific content,
  in full;
- grep the tree for first names, local-language function words, brand fragments, sector
  vocabulary and anything that still reads like one particular organisation;
- check nav titles and file names, not just page bodies;
- confirm binaries (screenshots, diagrams) were left out, unless someone cleared their hash
  under `sources.<alias>.binaries` after looking at them.

Findings go back into the mapping, never into a hand edit of the published pages: the next
sync would overwrite the edit and republish the problem.
