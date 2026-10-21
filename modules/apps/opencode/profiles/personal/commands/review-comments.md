---
description: Work through the open review comments on the current PR - judge every comment, fix the justified ones, rebut the rest, one commit per comment, then rebase and push
---

Work through the review comments on the current pull request. Load the
`review-comments` skill and follow it exactly.

PR number or extra instruction (may be empty): $ARGUMENTS

The skill carries the whole workflow (fetch threads → judge each comment →
fix with one commit per justified comment / rebut on GitHub → rebase, push,
post "Fixed" replies). This command only forwards the arguments.

Note: T3 Code does not surface opencode commands — invoke this workflow there
via the skill (`/skill:review-comments`). The command exists for the
opencode CLI.
