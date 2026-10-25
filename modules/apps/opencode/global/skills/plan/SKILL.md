---
name: plan
description: Only when the user explicitly asks for the plan workflow: turn a large task into a step-by-step plan in docs/plans/, shaped by an interview with the user, to be worked off one step at a time with plan-next.
---

# Plan workflow

Turn the task in the user's message into a plan someone can work off one step
at a time, across sessions, with nothing but the plan file. This produces the
plan; it does not implement anything.

## 1. Start or resume

Derive a slug from the task (lowercase, hyphenated) and use
`docs/plans/<slug>.md`. If the file exists, you are resuming: read it and
continue where it stopped.

Otherwise write the skeleton right away, so every answer has a home:

```markdown
Status: draft

# <title>

<two or three sentences: what changes and why>

## Decisions

## Out of scope

## Steps

## Clarifications
```

## 2. Explore

Read what the task touches before asking anything. For a large or unfamiliar
area, dispatch in parallel, in one message: `explore` (where things are),
`codebase-pattern-finder` (how this codebase already solves the shape),
`analyst-architecture` (decisions, risks, natural seams). Load the
`architecture` skill when the task involves design.

## 3. Interview

Load the `interview` skill and follow it, recording into this plan file:
each answer becomes a numbered entry under Decisions or Out of scope, plus a
line in Clarifications under `### Session <date>`.

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

## 5. Approve

Show the steps and stop. On approval, set `Status: in progress` and propose
committing the plan on its own. Next is `/plan-next`.

## Rules

- Do not implement anything, not even the first step.
- The plan file is the source of truth; save after every answer.
- Write the plan in English unless the repository's docs use another language.
