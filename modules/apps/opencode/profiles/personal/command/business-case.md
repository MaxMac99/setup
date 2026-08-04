---
description: Analyse whether an epic is worth building, and append the assessment to its draft
---

Assess whether this is worth building. This runs only when you ask for it — the
refinement flow never invokes it automatically.

Epic slug, issue number, or nothing: $ARGUMENTS

## 1. Find the subject

`$ARGUMENTS` naming a file or slug — use `.work/epics/<slug>.md`. An issue
number — fetch it with `gh issue view <n> --json number,title,body`. Empty —
use the most recently modified draft in `.work/epics/`, and say which you chose.

## 2. Assess

Be a sceptical reviewer, not an advocate. The useful output here is "this is not
worth it, and here is why" when that is true.

- **Problem.** Who has it, how often, and what does it cost them today? If you
  cannot name who is affected, that is the finding.
- **Current workaround.** What happens today without this? A tolerable
  workaround is the most common reason a feature is not worth building.
- **Value.** What improves, and can it be measured? Prefer a number or a
  falsifiable statement over an adjective.
- **Cost.** Implementation effort from the Design section, plus the ongoing
  cost — maintenance, new dependencies, operational surface, another thing that
  can break at 3am.
- **Alternatives.** Cheaper ways to get most of the value. Doing nothing is
  always a valid alternative and should be stated as one.
- **Risks.** What makes this not pay off: wrong assumption about usage,
  dependency on something unstable, a cost that only appears at scale.
- **Timing.** Is now the moment? Does something else need to exist first?

For a personal project, be honest about the real driver. "I want to learn X" or
"this annoys me daily" are legitimate reasons — but they should be stated as
such, not dressed up as value analysis. Misclassified motivation is how side
projects acquire features nobody uses.

## 3. Append

Add to the draft, above `## Open Questions`:

```markdown
## Business case

**Verdict:** build / build later / not worth it

- **Problem:** …
- **Today:** …
- **Value:** …
- **Cost:** …
- **Alternatives considered:** …
- **Risks:** …
```

If the subject was a GitHub issue rather than a draft, show the section and ask
before updating the issue body.

## Rules

- **A "not worth it" verdict is a success.** Do not soften it into "build
  later" to avoid disagreeing.
- Do not invent metrics. If value cannot be measured, say so.
- Do not restate the epic. Assess it.
- Keep it under a page. This is a decision aid, not a report.
