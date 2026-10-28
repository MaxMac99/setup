---
name: coderabbit-round
description: Use at the end of the milestone workflow, once the PR's pipeline is green - work through CodeRabbit's review comments in exactly one round, push the fixes, and stop if CodeRabbit comments again.
---

# CodeRabbit round

One round of answering CodeRabbit on the current PR, autonomously. Exactly
one: whatever CodeRabbit says after your push goes to the user, not into a
second round.

## 1. Wait for the review

CodeRabbit reports as a check on the PR, so the green `gh pr checks --watch`
of the milestone workflow already waited for it. If no CodeRabbit check or
comment exists, say "no CodeRabbit review" and stop.

## 2. Collect

```sh
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate
gh api repos/<owner>/<repo>/pulls/<number>/reviews --paginate
```

Keep only comments by `coderabbitai[bot]` that start a thread
(`in_reply_to_id` empty). From the review bodies, also take the items under
"Outside diff range comments". Nitpicks count only where they are plainly
right and cheap; skip the rest silently.

State the work list (`path:line`, one-line summary). Empty → stop, nothing to
do.

## 3. Judge and act

Per comment, announce "comment <k> of <n> - <path>:<line>", then judge as in
the `review-comments` skill section 3 (justified / unjustified / question,
same standard of proof). Differences from that workflow:

- Do not ask the user mid-round. A fix that needs a decision you cannot make
  alone is left open and goes into the report.
- Justified: smallest fix, verify, one commit per comment.
- Unjustified or question: reply on the comment with the reasoning and its
  citation, via
  `gh api repos/<owner>/<repo>/pulls/<number>/comments/<id>/replies -F body=@.work/coderabbit/reply-<k>.md`.
- No rebase, no force-push. The fix commits stack on the branch.

## 4. Push and check once

1. Note the time, then `git push`.
2. Reply `Fixed in <hash>. <one line>` on each fixed comment.
3. `gh pr checks <number> --watch --fail-fast` - the pipeline and
   CodeRabbit's incremental review.
4. Red pipeline: fix as in the milestone workflow section 8.
5. Fetch both endpoints again. Any CodeRabbit comment or review created after
   the noted time - including answers to your rebuttals - ends the run. Do not
   act on it.

## 5. Hand back

For the milestone report: a table comment → verdict → outcome (commit hash /
reply posted / left open), plus every new CodeRabbit comment after the round
with its link and a one-line summary. Those are the user's to decide.
