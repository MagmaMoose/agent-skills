# claude-skills

Shared [Claude Code](https://code.claude.com) skills for the MagmaMoose stack — one
source of truth for the slash commands used both **locally** (Caleb's Claude Code apps)
and **in-cluster** (the headless agents like Nievah that run `claude -p` against the
self-hosted LiteLLM gateway).

The point of this repo: these rubrics used to be hand-copied into each consumer (local
`~/.claude/commands/`, the Nievah image, comment-commander). That drifts. Now there is
**one definition** here, and every consumer installs it.

## Skills

| Command | What it does |
| --- | --- |
| `/claude-skills:pr-review` | Review a PR end to end (correctness, security, repo conventions, tests) and post one consolidated GitHub review with inline comments + a verdict. |
| `/claude-skills:pr-triage` | Read every PR comment (GHAS, Copilot, code-quality, human), fix the code, reply, and resolve each thread. |

Both adapt to the target repo automatically — they read that repo's own `CLAUDE.md` /
`AGENTS.md` / `CONTRIBUTING` and treat its stated hard rules as blockers. So you do **not**
fork these per-project: put house rules in the target repo, not in a copy of the skill.

## Install (local Claude Code)

```bash
claude plugin marketplace add magmamoose/claude-skills
claude plugin install claude-skills@magmamoose
```

Then invoke with `/claude-skills:pr-review` (and `/claude-skills:pr-triage`).

## Install (headless / in-cluster)

The same two CLI calls work non-interactively at image-build time, after the `claude`
CLI is installed:

```Dockerfile
RUN npm install -g @anthropic-ai/claude-code \
 && claude plugin marketplace add magmamoose/claude-skills \
 && claude plugin install claude-skills@magmamoose
```

Then the worker runs e.g. `claude -p "/claude-skills:pr-review 123"`.

## License

MIT © Caleb Sargeant
