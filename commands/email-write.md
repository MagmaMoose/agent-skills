---
description: Draft or rewrite an email, chat message or letter the user will send, in their own voice, with a planning pass for tense messages and a de-AI pass on every draft
argument-hint: "[who it's to and what it needs to say, or the message you're replying to]"
---

Draft a message using the shared MagmaMoose email writing workflow.

**First, read the full workflow.** It covers where to find the user's voice, when to plan before
writing, the drafting rules and a worked example. It lives at the first of these paths that exists
(check in order):

1. `.claude/shared/email-write.md` (headless runs, installed into the clone)
2. `${CLAUDE_PLUGIN_ROOT}/shared/email-write.md` (installed as a plugin)
3. `shared/email-write.md` (working inside the agent-skills checkout)

The two things that most often go wrong, so do them deliberately:

- **Lecturing the reader on their own field.** Give them the facts they can't know, then ask for
  their judgment.
- **Length and stock phrases.** Keep the body under about 100 words and run the de-AI pass.

Never send the message yourself unless the user asks.
