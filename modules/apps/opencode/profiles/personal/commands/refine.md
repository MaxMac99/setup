---
description: Refine an existing GitHub issue until it is implementable, then update it
---

Refine a ticket that is too vague to implement.

Issue number, optionally followed by `--deep`: $ARGUMENTS

Load the `refinement-loop` and `github-issues` skills.

## 1. Fetch

```sh
gh issue view <n> --json number,title,body,labels,parent,subIssues
```

Write the body to `.work/refine-<n>.md`. If the issue has a parent, fetch that
too and read it — an epic's Context and Out of Scope constrain its stories, and
refining a story against the wrong assumptions is worse than not refining it.

Bring the body up to the standard template, preserving what is already there:

```markdown
## Context
## Acceptance Criteria
## Out of Scope
## Design
## Open Questions
```

## 2. Investigate, if asked

With `--deep`, dispatch in parallel before questioning: `codebase-locator`,
`codebase-pattern-finder`, `analyst-architecture`. Fold their findings into
Design.

Without `--deep`, skip this. A story under an already-refined epic usually
inherits enough context, and the fan-out is not free.

## 3. Question

Up to 3 rounds of 3-5 questions per the `refinement-loop` protocol. State your
confidence after each round; stop as soon as it is high.

Focus on what makes this ticket *implementable*: what exactly changes, how you
would know it works, what is deliberately excluded.

## 4. Show and confirm

Present the refined body and wait for approval. Check **Open Questions is
empty** — if anything remains, ask it or record it as an Out of Scope decision.

## 5. Update

```sh
gh issue edit <n> --body-file .work/refine-<n>.md
```

Report the issue URL and summarise what changed — criteria added, ambiguities
resolved, scope newly excluded.

## Rules

- **Never silently discard existing content.** If something in the original body
  is wrong or obsolete, say so and get agreement before removing it.
- Do not change the title unless asked, and do not touch labels, parent or
  sub-issue links — this command refines the body only.
- Do not implement anything.
