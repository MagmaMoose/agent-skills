---
name: catchup-write
description: Write a welcome-back report for a colleague returning from leave - what shipped on GitHub, what was discussed in meetings and Teams, what is waiting for them - as one self-contained HTML page with an animated recap, by driving the catchup CLI rather than spending tokens on connector calls.
---

Use the shared MagmaMoose catchup-write workflow.

Read and follow:

- `shared/catchup-write.md`: read this ALWAYS, before running anything
- `catchup schema` output, only when writing the prose yourself
- The run's `facts.md`, once, only when writing the prose yourself. Never `raw/*.json`

Expected input:
- Who: an alias from `~/.config/catchup/config.toml` or an email address.
- Optionally `--from` and `--to`. Without them the dates come from the person's automatic reply.

## Why this skill exists

A colleague back from three weeks away faces hundreds of merged pull requests, dozens of meetings
and a wall of chat. A short, honest report gets them up to speed in five minutes. Building one
by hand through connector calls costs hundreds of thousands of tokens and risks pulling in
things the colleague never saw. The catchup CLI does the collecting, filtering and counting in
code; the agent gets the inputs right, makes sure the meeting notes are in, and reviews the
page.

## Hard rules

- Drive the CLI; never rebuild the pipeline from connector calls.
- The report holds only what the reader could have seen. Never add your own chats, mails or
  private meetings. Leave out health, family, HR and friction between people.
- Numbers come from code. Never edit `pack.json`.
- Review the rendered page before handing it over; fix `report.json` and re-render.
- Never send, post or publish the report. The user decides who sees it.
- The Microsoft 365 sign-in is a device code that the user completes.
