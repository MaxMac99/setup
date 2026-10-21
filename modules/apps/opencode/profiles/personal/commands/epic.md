---
description: Turn a rough feature idea into a refined epic and its child stories, then create them as GitHub issues
---

Take a rough idea, refine it until it is implementable, then create the epic and
its stories on GitHub.

The idea: $ARGUMENTS

Load the `refinement-loop`, `architecture` and `github-issues` skills.

## 1. Draft

Write a skeleton to `.work/epics/<slug>.md`, where `<slug>` is derived from the
idea (lowercase, hyphenated). If that file already exists, you are resuming —
read it, including its frontmatter, and continue from where it stopped.

```markdown
---
issue:
children: []
---

# <title>

## Context
## Acceptance Criteria
## Out of Scope
## Design
## Open Questions
```

## 2. First round of questions

Ask 3-5 clarifying questions per the `refinement-loop` protocol: one at a time,
recommendation included, recorded and routed immediately. This round is about
**intent** — what problem, for whom, what does done look like.

## 3. Investigate

Now that intent is clear, dispatch **in parallel, in a single message**:

- `codebase-locator` — where the affected areas are
- `codebase-pattern-finder` — how this codebase already solves this shape
- `analyst-architecture` — implications, decisions needed, risks, decomposition

Fold their findings into the Design section. Their "open questions" become
candidates for the next round.

## 4. Further rounds

Ask up to two more rounds, now grounded in what was actually found — "the
existing job queue already handles retries, reuse it or keep this separate?"
beats anything you could have asked in round 1.

State your confidence after each round and stop as soon as it is high. Three
rounds maximum.

## 5. Decompose

Propose the stories. Each one must be:

- independently deliverable and independently reviewable
- describable in one sentence with its own testable acceptance criteria
- small enough to implement in one focused sitting

If a story cannot be stated with clear acceptance criteria, split it. If two
stories would always change together, merge them. Note any forced ordering.

Two levels only: an epic and its stories. Do not create a third level.

## 6. Approval gate

Show the complete epic body and the proposed stories, then **stop and wait**.
Do not create anything until the user approves. If they change something,
update the draft and show it again.

Before proceeding, check **Open Questions is empty**. If anything remains,
either ask it or move it to Out of Scope as an explicit decision.

## 7. Create

Check the frontmatter first — if `issue:` is set, the epic exists; update it
rather than creating a duplicate.

```sh
gh issue create --title "<title>" --body-file .work/epics/<slug>.md --label type:epic
```

Record the number in `issue:`. Then create each story with `--parent <epic#>`
and `--label type:story`, recording each number in `children:` as you go. Add
`gh issue edit <n> --add-blocked-by <m>` for any ordering you identified.

Create them one at a time — bulk creation trips secondary rate limits. Stop and
report if one fails; do not retry blindly.

## 8. Report

The epic URL, the story numbers with their titles, and the dependency edges.

## Rules

- The draft is the source of truth during refinement. Save after every answer.
- Never create issues before the approval gate.
- Do not implement anything. This command produces tickets.
- If mermaid would clarify the design, include it in the Design section — it
  renders natively in the issue body, and `/diagram` will preview it locally.
