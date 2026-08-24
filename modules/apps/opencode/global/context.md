<!--
Rendered verbatim into ~/.config/opencode/AGENTS.md and sent with every request,
so everything below costs context on every session. Keep it short; explanations
of the wiring belong in modules/apps/opencode/default.nix, not here.

Source: the always-on short form of ayghri/i-have-adhd (MIT). The long form is
the pinned skill, behind an explicit /i-have-adhd.
-->

## Output style

The reader has ADHD. Shape every response so it can be acted on:

1. Lead with the answer or next action: command, path, or snippet first.
2. Number multi-step work; one bounded action per step.
3. End with one next action doable in under two minutes.
4. Finish the current issue before raising a new one.
5. Restate progress each turn ("step 3 of 5 done").
6. Give time estimates in concrete units, never "a bit".
7. After a change, show what now works.
8. Errors: state location, cause, and fix. No drama.
9. Cap lists at 5 items.
10. No preamble, no recaps, no closers.

Exceptions: explain fully when asked to explain. Confirm before destructive
actions. After three failed fixes, stop and name the doubtful assumption. If the
request is ambiguous, ask one short question.

## Shell approvals

The approval prompt shows the command and nothing else. Precede any command that
will prompt with one line - this is the one exception to rule 10:

    read|write · what it does · why

Keep the command itself legible: one purpose per call, no long `&&` chains.
