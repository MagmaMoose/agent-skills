# catchup-write: a welcome-back report for a colleague returning from leave

This drives the `catchup` CLI ([MagmaMoose/catchup](https://github.com/MagmaMoose/catchup)). The
CLI collects from GitHub, Outlook and Teams, and from Grimoire's recorded meeting notes. It
computes every number and list, has one model call write the prose, and renders one
self-contained HTML page that opens with an animated recap.

The agent's job is the part a script cannot do:

- get the inputs right: who, which dates, which meetings;
- make sure the meeting notes are actually in;
- look at the page before anyone else does.

## Why a CLI and not MCP calls

Doing this by hand with connector tools costs hundreds of thousands of tokens. One calendar search
returns 60k characters of attendee lists; a month of an org's pull requests is hundreds of
titles; a Teams channel can be thousands of alert posts. The CLI reads all of it, filters it in
code and hands the writer a pack of facts cut to about 28k tokens. An agent driving the CLI
keeps its own context to a few thousand tokens.

| Never read | Read only when writing the prose yourself |
| --- | --- |
| `raw/*.json` (megabytes) | `facts.md` (about 28k tokens, once) |
| `pack.json` (the page's data) | `catchup schema` (the shape `report.json` must have) |

## The run

### 1. Preflight

```bash
catchup doctor
```

Fix what it reports:

- `gh auth login --hostname <host>` for GitHub.
- `catchup login` for Microsoft 365. This is a device code, so **the user** signs in. Give them
  the code and wait.
- Claude Code (`claude`) for the write-up, or `ANTHROPIC_API_KEY` with the `anthropic` backend.

A missing config is not fatal: copy `config.example.toml` from the catchup repository to
`~/.config/catchup/config.toml` and ask the user for the values only they know (the GitHub
host and orgs, the time zone). Never put that file in a repository.

### 2. Who, and when

```bash
catchup window <who>
```

This reads the dates from the person's own automatic reply in the user's mailbox (Dutch and
English). If it finds none, ask the user for `--from` and `--to`. Do not guess from activity
gaps.

If the leave has not ended yet, the report covers up to today. Say so, and suggest a re-run on
the return day.

### 3. Meeting notes

Recorded meetings come from Grimoire on the machine that holds its library:

- **Teams transcripts.** Some tenants switch off Graph access to transcripts
  (`GraphAccessToTranscriptsDisabled`), and then no script can fetch them. Ask the user to
  download the `.vtt` or `.docx` from Teams or Stream for the meetings that matter, then run:

  ```bash
  transcribe import <files>
  ```

  Dates come from the file names. Use `--at="YYYY-MM-DD HH:MM"` when a name carries none.
- **The digest.** Either set `[meetings] command = "transcribe"` in the catchup config, or, when
  the library is on another machine, run the digest there and point `[meetings] file` at the
  copied JSON:

  ```bash
  transcribe digest --from=<start> --to=<end> --json --out=digest.json
  ```

catchup matches each recording to the reader's calendar by time. A recording that matches none
of the reader's invites is dropped. That is the privacy gate, not a bug.

### 4. Collect, write, render

```bash
catchup run <who> [--from YYYY-MM-DD --to YYYY-MM-DD]
```

This collects for about two minutes, writes for one or two, and prints the path to
`report.html`. Collected sources are cached per run, so `catchup write` and `catchup render` can
be repeated without collecting again. Use `--refresh` only when the data itself must be newer,
such as on the return day.

**Writing the prose yourself** fits when there is no `claude` CLI or API key, or when the user
wants to steer the words. The steps:

1. Run `catchup collect <who>`.
2. Read `facts.md` once.
3. Run `catchup schema`.
4. Write `report.json` in the run folder to that schema.
5. Run `catchup render <dir>`.

Follow the writing rules below.

### 5. Review the page (mandatory)

Open `report.html` with `#report` on the URL to skip the recap, then play the recap once. Check:

- The tone sounds like the user, writing to a colleague they like.
- Nothing private got through: health, family, pregnancy, HR or pay, and nothing from the user's
  own one-to-ones.
- No friction between people and no criticism of anyone.
- Every recap caption fits the number above it.
- The `Waiting for you` items are the reader's, and the links work.
- Claims match `facts.md`. The numbers come from code, but the sentences around them do not.

Fix problems by editing `report.json` and running `catchup render <dir>`, which takes seconds.
Do not rewrite the whole report to fix one line.

### 6. Hand it over

Give the user the path and a three-line summary of what is in it. Sending it to the colleague
is the user's call: never mail it, post it or publish it yourself. Offer the return-day re-run:
`catchup run <who> --refresh`.

## Writing rules (the in-session path)

- Use only the facts. Never invent a project, number, name, date, decision or outcome.
- Take numbers only from "Numbers (exact, computed)".
- Cite pull requests and issues as `repo#number`, exactly as they appear in the facts, so they
  become links.
- The writer is the user and the reader is the colleague. Use their first name.
- Use the config's language (British English by default) and plain words. No em dashes, and no
  "leverage", "robust" or "seamless".
- Warm, with dry humour that is never at anyone's expense. The recap captions can play; the
  sections should inform.
- Lead with what changes the reader's next week: decisions, things that went live, things
  waiting for them, risks. Upkeep is counted, never narrated.
- A calendar entry without notes proves a meeting happened, nothing more.

## Hard rules

- **Privacy lives in the collectors.** Never widen their reach by pasting your own chats, mails
  or private meetings into the facts or the report. Turn on `include_unmatched` only when the
  user names a specific recording.
- **Numbers come from code.** Never edit `pack.json`, and never write a count the facts do not
  state.
- **Never publish.** No artifact, channel post or mail of the report unless the user asks.
- **Never commit run output or the config** to any repository. They name people.
- **No replacement pipeline.** If `catchup` is not installed, offer
  `uv tool install git+https://github.com/MagmaMoose/catchup` and wait for a yes, or stop and
  say what is missing. Rebuilding it from connector calls is the 300k-token path this
  workflow exists to avoid.
