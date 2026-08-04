---
name: refinement-loop
description: Use when turning a rough idea, feature request or vague ticket into a specification precise enough to implement - refining an epic, a story, or an existing ticket that is underspecified. Defines the clarifying-question protocol, how answers are recorded, and when refinement is finished.
---

# Refinement loop

Turn an underspecified request into a spec someone else could implement without
asking you anything. You do that by asking questions, not by guessing.

## Budget

**At most 3 rounds of 3-5 questions.** After each round, state your confidence
and stop as soon as it is high. Never exceed 3 rounds — if the request is still
unclear after ~15 questions, the problem is not missing detail, and you should
say so plainly rather than keep asking.

Stop early when any of these is true:

- The remaining ambiguities no longer change what gets built.
- The user signals completion ("that's enough", "good", "just write it").
- You could hand the spec to another engineer and expect the right result.

## Asking

**One question at a time.** Never reveal the queue in advance — answers reshape
later questions, and showing five at once invites shallow replies to all five.

Every question uses this shape:

```markdown
**Question:** Should a failed sync retry automatically, or surface immediately?

Why it matters: retry semantics decide whether this needs a queue and a
dead-letter path, or just an error return.

**Recommended:** Option B — the existing jobs table already gives you retry
bookkeeping for free, and nothing here needs sub-second feedback.

| Option | Behaviour |
| --- | --- |
| A | Fail fast, surface the error to the caller |
| B | Retry with backoff via the existing job queue |
| C | Retry inline, bounded, then fail |

Reply with a letter, "yes" to take the recommendation, or your own answer.
```

Rules:

- **It must be an interrogative sentence ending in `?`.** A topic label is not
  a question. `Retry semantics (FR-012)` is invalid; `Should a failed sync
  retry?` is valid.
- Exactly one *why it matters* sentence, and it must name a real consequence —
  a component that would exist or not, a boundary that moves. If you cannot
  name a consequence, the question does not matter; drop it.
- Always give a recommendation with your reasoning. The user should be able to
  say "yes" and move on.
- Ask about what you genuinely cannot infer. Do not ask what the codebase can
  tell you — go and read it.

## Recording

Save after **every** answer. Do not batch writes to the end of the round.

Append to a `## Clarifications` section:

```markdown
## Clarifications

### Session 2026-08-04

- Q: Should a failed sync retry automatically? → A: B, retry via the job queue
```

Then immediately route the substance into the right section of the document:

| Answer is about | Goes to |
| --- | --- |
| behaviour the system must have | Acceptance Criteria, as a testable statement |
| something deliberately excluded | Out of Scope |
| a structural or technology choice | Design |
| a performance or reliability target | Acceptance Criteria, with a number |
| terminology | applied consistently throughout, and defined once |

The `## Clarifications` log is an audit trail, not the spec. A reader must get
the full picture from the sections alone, without reading the Q&A.

## When the user corrects you

If an answer reveals you misunderstood something, **do not simply accept the
correction and carry on.** Re-verify: read the relevant code, confirm the
correction is complete rather than partial, and check whether anything already
written rests on the wrong assumption. A misunderstanding usually contaminates
more than the one sentence that exposed it.

## Finishing

Refinement is finished when **Open Questions is empty**. If questions remain,
either ask them or record them as explicit Out of Scope decisions. A ticket
created with open questions in it just defers the thinking to implementation
time, which is where it is most expensive.

Before declaring it done, re-read the Acceptance Criteria and check each one is
falsifiable — someone must be able to say "yes, that happens" or "no, it does
not". "Handles errors gracefully" is not a criterion. "A failed sync is retried
three times, then moved to the dead-letter queue" is.
