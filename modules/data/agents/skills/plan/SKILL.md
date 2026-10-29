---
name: plan
description: Only when the user explicitly asks for the plan workflow: turn one milestone - described directly or taken from a concept in docs/planning/concepts/ - into a step-by-step plan in docs/planning/plans/, shaped by an interview with the user, to be worked off with plan-next or milestone.
---

# Plan workflow

Turn one milestone into a plan someone can work off one step at a time,
across sessions, with nothing but the plan file. A plan is exactly one
milestone: it ships as one pull request, or several where one is technically
impossible (section 4b). This produces the plan; it does not implement
anything.

**Too small for a plan?** A task that fits about three steps, touches one
area and leaves no decision open does not need this workflow. Say so in one
line, with the steps you would take, and offer to do it directly. Continue
only if the user still wants the plan. Resuming an existing plan skips this.

The milestone comes from one of two places:

- **A concept** - the user names a concept and a milestone
  (`<concept> M2`). Read `docs/planning/concepts/<slug>.md` first; its Goals,
  Decisions, Out of scope and Design bind the plan, and its milestone Outcome
  is the plan's goal.
- **The user's message** - a task small enough for one PR that needs no
  concept.

## 1. Start or resume

The path is `docs/planning/plans/<concept-slug>-m<n>.md` for a concept milestone, else
`docs/planning/plans/<slug>.md` with a slug from the task (lowercase, hyphenated). The
caller may give another directory (the `milestone` workflow writes into a
worktree). If the file exists, you are resuming: read it and continue where
it stopped.

Otherwise write the skeleton right away, so every answer has a home:

```markdown
Status: draft
Progress: 0/<n> · next: 1. <title>
Concept: docs/planning/concepts/<slug>.md, M<n>   (omit without a concept)
Repos: <owner/name>

# <title>

<two or three sentences: what changes and why>

## Decisions

## Out of scope

## Steps

## Clarifications
```

For a concept milestone, set its `Plan:` line in the concept to this file.

`Progress:` is the plan's one-line state, for the user and for a resuming
run. Whoever ticks a step updates it in the same edit: `<ticked>/<total> ·
next: <k>. <title>`, with `· pending: <k>` for steps waiting on the user, and
`<n>/<n> · done` at the end. Fill in the real count once the steps exist.

## 2. Explore

Read what the task touches before asking anything. For a large or unfamiliar
area, dispatch in parallel, in one message: `explore` (where things are),
`codebase-pattern-finder` (how this codebase already solves the shape),
`analyst-architecture` (decisions, risks, natural seams). Load the
`architecture` skill when the task involves design. With a concept, explore
only what its Design leaves open.

## 3. Interview

Load the `interview` skill and follow it, recording into this plan file:
each answer becomes a numbered entry under Decisions or Out of scope, plus a
line in Clarifications under `### Session <date>`. Do not re-ask what the
concept already decided.

## 4. Write the steps

Each step must be:

- one focused sitting and one commit,
- verifiable on its own, with a concrete check,
- ordered so the repository works after every step.

```markdown
- [ ] **3. <imperative title>**
  - Goal: what is true afterwards, in one sentence.
  - Files: the paths it touches.
  - Done when: the command or observation that proves it.
```

A step whose check needs something only the user can do (a rebuild with
sudo, a deploy, a manual test) says so in "Done when".

If two steps always change together, merge them. If one has no clear check,
split it or sharpen it. A diagram belongs in the plan only per the `diagram`
skill.

More than about eight steps means the milestone is too big. With a concept,
propose splitting the milestone there instead of writing a long plan; without
one, propose the `concept` workflow.

## 4b. Several pull requests, only if unavoidable

The default is one PR and no sections. Split into PR sections only when one
PR cannot work: the steps span repositories, or an order is forced across a
merge or deploy (migration before code, library release before consumer).
Size alone is no reason - that is a milestone split. Agree the split in the
interview and record why.

```markdown
### PR 1: <owner/name> - <title>

- Repo: <owner/name>
- Depends on: — | PR <k>
- Why separate: <the technical reason>
- PR: —

- [ ] **1. <imperative title>**
  …
```

Steps are numbered continuously across sections. Every step belongs to
exactly one section, every section to one repository. The plan lives in the
repository the concept lives in.

A plan whose sections span more than one repository is marked up front:
`[multi-repo]` at the end of the title, every repository in the `Repos:`
line, and right below the intro one line on the order, e.g.
`Multi-repo: PR 1 (owner/a) → PR 2 (owner/b)`. In the approval step, say so
before showing the steps.

## 5. Approve

Show the steps and stop. On approval, set `Status: in progress` and propose
committing the plan on its own. Next is `/plan-next` (one step, local,
reviewed by the user) or `/milestone` (the whole plan, one worktree and T3
thread per PR).

## Rules

- Do not implement anything, not even the first step.
- The plan file is the source of truth; save after every answer.
- Write the plan in English unless the repository's docs use another language.
