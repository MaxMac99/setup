---
name: plan-next
description: Only when the user explicitly asks for the plan-next workflow: work off the next open step of a plan in docs/plans/ - implement it, verify it, tick it, stage it, and stop for the commit.
---

# Plan-next workflow

Do exactly one step of a plan, then stop.

## 1. Find the step

The plan is the file the user named, else the one in `docs/plans/` with
`Status: in progress`. Several or none: ask which.

Take the first step whose checkbox is open. Read the plan's Decisions and Out
of scope before touching code; they bind this step. Start with the progress
line, on its own:

```text
▶ <k>/<n> · <title>
```

## 2. Implement

Make the smallest change that reaches the step's goal. Stay inside its Files;
if the step needs more, say which and why before going further. Follow the
repository's conventions and the skills that apply (`architecture`,
`rust-workflow`, …).

## 3. Verify

Run the step's "Done when" check and show its real output. Also run the
repository's usual checks for the touched code (formatter, typecheck, build,
tests).

- Check passes: tick the checkbox and update the plan's `Progress:` line
  (`plan` section 1).
- Check needs the user (rebuild, deploy, manual test): leave the box open, add
  `  - Pending: <what to run>` under the step, and say so.
- Check fails: fix it, or stop and report location, cause and fix. Do not
  tick.

## 4. When the plan is wrong

If the step is too big, depends on something not yet done, or contradicts what
you found, stop before improvising. Propose the change to the plan (split,
reorder, new decision), apply it on the user's yes, and log it under
Clarifications. Correcting an earlier decision is fine; hiding it is not.

## 5. Hand over

1. If this was the last open step and nothing is pending, set
   `Status: done` at the top.
2. Stage the step's files and the plan update together, with explicit paths.
3. Propose a commit message per the `conventional-commits` skill and stop.
   Commit only if the user tells you to.
4. End with the progress line and the next step, then stop - do not start
   it:

   ```text
   ✓ <k>/<n> · <title> · next: <k+1>. <title>
   ```

   A pending step reads `⏸ <k>/<n> · <title> · pending: <what to run>`.
