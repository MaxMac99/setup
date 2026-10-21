---
name: interview
description: Use when a task has several open decisions only the user can make - shaping a plan, a feature, a refactor or a ticket - or when the user asks to be interviewed. Asks one question at a time in the chat, each with background, options and a recommendation, and records every answer.
---

# Interview

Turn open decisions into recorded answers, one question at a time, in the chat.

## Before the first question

Explore first. Read the code, config and docs the decisions touch, so every
question is grounded in what exists. Never ask what the codebase can answer.

Then list the decisions to yourself, ordered so that answers which reshape
later questions come first. Do not show the list.

## One question

One question per message, as plain chat text. Never the `question` tool or
any other input dialog: the user needs the background to answer, and a dialog
hides it.

```markdown
## Question 3 of ~8

**Should a failed sync retry automatically, or fail immediately?**

**Background:** what exists today and what the choice touches, with paths.
Two to five sentences.

**Why it matters:** the one concrete consequence - a component that would
exist or not, a boundary that moves, a cost.

| Option | What it means |
| --- | --- |
| A | Fail fast, surface the error |
| B | Retry with backoff via the existing job queue |

**Recommendation: B.** The reason, in one or two sentences.

Reply with a letter, "yes" for the recommendation, or your own answer.
```

- The question is a real interrogative ending in `?`, not a topic label.
- If you cannot name a concrete consequence, the question does not matter.
  Drop it.
- Two to four options. Always recommend one; "yes" must be a complete answer.
- Write in the user's language.

## After each answer

1. Record it at once, before the next question: the decision in its own
   words, plus one line in a `## Clarifications` log
   (`- Q: … → A: …`). Use the file the caller named, else
   `.work/interview-<slug>.md`.
2. State progress, then ask the next question. Raise the estimate openly when
   answers open new decisions.

## When the user pushes back

- **They question the question** ("do we need this at all?", "what does X
  do?"): answer that first, with evidence you looked up, then re-ask a revised
  question. The pushback often removes an option or the whole question.
- **An answer exposes an earlier mistake of yours:** say so plainly, explain
  what was wrong, and re-ask that decision. Fix the record; keep the old line
  in the log with the correction next to it.
- **They correct a fact:** re-verify against the code before carrying on. A
  misunderstanding usually affects more than the sentence that exposed it.

## Finishing

Stop when the remaining open points would not change what gets built, or when
the user says so. Then summarise the decisions in at most five bullets and
hand over to whatever produces the result: a plan, a ticket, a change.
