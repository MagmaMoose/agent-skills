# Email writing workflow

You are drafting an email, chat message or letter that the user will send to another person under
their own name. The deliverable is a draft they can paste and send as it is, because it already
reads as if they wrote it.

Never send the message yourself. Hand over the draft. Sending is the user's call unless they
explicitly ask you to send it.

## Find the user's voice first

Before writing, look for a sample the user has approved as sounding like them: a voice or email
section in their global agent instructions (`CLAUDE.md`, `AGENTS.md`), a personal voice skill, or
memory. Their sample and rules win over everything below, including the greeting and the sign-off.

If there is none, ask for one email they wrote and were happy with, and offer to save it to their
global instructions so the next draft starts from it. Until then, use the defaults below and the
example at the end.

## Steps

1. Decide whether the message carries weight: it asks for something, says no, sets a boundary,
   raises a problem, corrects someone or pushes back on an expert. If it does, plan what to say
   before writing. Use a conversation-planning tool if one is connected, such as
   `wise_mind_plan_conversation` from the wise-mind MCP server, and pass it categories only, never
   names or details.
2. Write the draft with the rules below.
3. Run a de-AI rewriting pass if one is installed, such as the `humanizer` skill, with the user's
   sample as the writing sample. Fix what it flags.
4. Read the draft once as the recipient. Cut anything that reads as a lecture, a stock phrase or a
   second ask.
5. Give the user the final draft in a fenced code block so it copies cleanly.

## Rules

These are the defaults. The user's own sample overrides any of them.

- Keep the body under about 100 words.
- Open with a greeting by first name, a short pleasantry and specific thanks for the last thing
  they did: "Thank you for sending the draft return", not "Thanks for everything".
- Give the reader facts they can't know from where they sit, such as how things work on the
  sender's side, dates and what has already been done. Never explain their own field to them. An
  expert who feels lectured stops helping, however politely it was put.
- Leave the professional call with them. Ask for their judgment ("Do you think the registry would
  accept that?") instead of telling them what will work or what they should do.
- Offer the sender's own research modestly, as background before the question: "From what we've
  read, ...". A precise reference, such as an article, rule or form number, is fine in that frame
  and saves them looking it up.
- Make one clear ask, with "please". Ask for the outcome and leave the method to them: "could you
  please send us an updated agreement?" rather than instructions on how to redraft it.
- Answer every question they asked with the exact fact ("we sold it on 3 March"), never an
  approximation.
- Close with thanks, then the sender's usual sign-off.
- Never promise anything on behalf of someone the sender hasn't confirmed, such as an adviser, an
  agent or a family member.
- Write "we" only when the message speaks for more than one person.

## Format

- One line per paragraph. Hard wraps inside a paragraph break when the draft is pasted into a mail
  client.
- No em or en dashes. Use a comma, a full stop or brackets.
- Straight quotes and apostrophes only, never curly ones.
- Plain words. Cut stock phrases that read as generated, such as "Happy for you to...", "I hope
  this email finds you well", "Please don't hesitate to reach out", "Just to clarify" and "I
  wanted to reach out".
- For chat messages, drop the greeting and the sign-off unless the user's sample keeps them.

## Example

The default voice, for when the user has no sample yet:

```text
Hi Sam,

Hope you're well. Thank you for sending the draft return.

Our bank only issues year-end statements as digitally stamped PDFs. From what we've read, the tax office accepts those for this kind of claim.

Do you think that would be enough? If so, could you please let us know which pages you need?

On your question about the car, we sold it on 3 March.

Thanks again for all your help.

Kind regards,
Alex
```

The thanks names what Sam did. The bank detail is something Sam can't know, and the tax-office
point is offered as background. "Do you think" leaves the call with the expert, there is one ask
with "please", and Sam's question gets an exact date.
