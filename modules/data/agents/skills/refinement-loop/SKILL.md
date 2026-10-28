---
name: refinement-loop
description: Use when turning a rough idea, feature request or vague ticket into a specification precise enough to implement - refining an epic, a story, or an existing ticket that is underspecified. Defines how answers land in the ticket's sections and when refinement is finished.
---

# Refinement loop

Turn an underspecified ticket into a spec someone else could implement without
asking you anything.

Ask with the `interview` skill: one question at a time, with background,
options and a recommendation. This skill only adds what is specific to
tickets.

## Where answers go

Log every answer in the ticket's `## Clarifications` section, under a
`### Session <date>` heading. Then route its substance into the section that
owns it:

| Answer is about | Goes to |
| --- | --- |
| behaviour the system must have | Acceptance Criteria, as a testable statement |
| something deliberately excluded | Out of Scope |
| a structural or technology choice | Design |
| a performance or reliability target | Acceptance Criteria, with a number |
| terminology | applied throughout, defined once |

The log is an audit trail, not the spec. A reader must get the full picture
from the sections alone.

## Finishing

Refinement is finished when **Open Questions is empty**: ask what remains, or
record it as an explicit Out of Scope decision.

Then check each acceptance criterion is falsifiable. "Handles errors
gracefully" is not a criterion. "A failed sync is retried three times, then
moved to the dead-letter queue" is.
