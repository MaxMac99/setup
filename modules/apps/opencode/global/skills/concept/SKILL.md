---
name: concept
description: Only when the user explicitly asks for the concept workflow: turn a rough idea for the next piece of work into a concept in docs/concepts/ - goal, decisions, design and a breakdown into milestones, each one pull request - shaped by an interview with the user.
---

# Concept workflow

Turn the idea in the user's message into a concept: what should be true when
it is done, the decisions that shape it, and its milestones. Each milestone
later gets its own plan (`plan`) and ships as one pull request (`milestone`),
or several where one is technically impossible.
This workflow writes neither plans nor code.

Three levels, never a fourth:

| Level | Artefact | Ships as |
| --- | --- | --- |
| Concept | `docs/concepts/<slug>.md` | several milestones |
| Milestone | `docs/plans/<slug>-m<n>.md` | one PR, more only where technically unavoidable |
| Step | checkbox in the plan | one commit |

## 1. Start or resume

Derive a slug (lowercase, hyphenated) and use `docs/concepts/<slug>.md`. If it
exists, you are resuming: read it and continue where it stopped. Otherwise
write the skeleton right away, so every answer has a home:

```markdown
Status: draft

# <title>

<two or three sentences: the problem, for whom, what done looks like>

## Goals

## Decisions

## Out of scope

## Design

## Milestones

## Open questions

## Clarifications
```

## 2. Intent

Load the `interview` skill and follow it, recording into this file. The first
round is about **intent only**: what problem, for whom, what does done look
like. Answers land under Goals (as checkable outcomes), Decisions, or Out of
scope, plus a line in Clarifications under `### Session <date>`.

## 3. Investigate

Now that the intent is clear, dispatch in parallel, in one message: `explore`
(where the affected areas are, in every repository involved),
`codebase-pattern-finder` (how this codebase already solves the shape),
`analyst-architecture` (decisions, risks, natural seams). Load the
`architecture` skill. Fold the findings into Design, high level: boundaries,
contracts, data, which repositories change. Their open questions become
candidates for the next round.

## 4. Further rounds

Up to two more interview rounds, now grounded in what was found. State your
confidence after each round and stop as soon as it is high.

## 5. Cut the milestones

Each milestone must:

- deliver one checkable outcome and leave everything working,
- have an outcome you can check without reading the code,
- fit a plan of at most about eight steps - bigger means split it,
- ship as one pull request where possible. Several PRs only where one is
  technically impossible: the outcome spans repositories, or an order is
  forced (migration before code, library before consumer). Name the reason.

```markdown
### M1: <outcome, not activity>

- Outcome: what is true afterwards, checkable.
- Repos: <owner/name>
- Depends on: — | M<k>
- Plan: —
- PRs: —
```

`Repos:` is always filled, even for a single repository. A milestone that
touches more than one repository is marked in its heading, and names the
reason and the order:

```markdown
### M2: <outcome> [multi-repo]

- Outcome: …
- Repos: <owner/a>, <owner/b>
- Why multi-repo: <what forces the change into both>
- Order: <owner/a> first, <owner/b> after | independent
- …
```

The marker belongs in the heading so it shows in any outline of the concept.
In the approval summary, list the multi-repo milestones separately.

Order them so each builds on merged predecessors. If two always change
together, merge them. A diagram belongs here only per the `diagram` skill.

## 6. Approve

Open questions must be empty: ask what is left, or record it as an Out of
scope decision. Then show Goals, Design and Milestones and stop.

On approval set `Status: approved` and propose committing the concept on its
own.

If the `github-issues` skill is available, ask once whether to also create the
concept as an epic issue with one story per milestone. Only on yes, follow
that skill; record the numbers as `Issue: #<n>` under the title and under each
milestone.

Next is `/plan <concept> M1` (write the plan first and review it) or
`/milestone <concept> M1` (plan and implement in one go).

## Rules

- Do not write plan steps and do not implement anything.
- The concept file is the source of truth; save after every answer.
- Later workflows update only the `Plan:`, `PRs:` and `Status:` lines. A change
  of goals or milestones goes back through this workflow.
- `Status: done` once every milestone's PRs are merged.
- Write in English unless the repository's docs use another language.
