# opencode workflow

Design notes for how opencode is set up to work: plan or refine → implement →
review → small commits → pull request. The wiring lives in
`modules/apps/opencode/`; the rework that produced this shape is
[plans/opencode-rework.md](plans/opencode-rework.md).

## Building blocks

| Kind | What it is | Who triggers it |
| --- | --- | --- |
| Knowledge skill | Facts and preferences the model does not have on its own | the model, when relevant |
| Workflow skill | A multi-step procedure with side effects; its description starts "Only when the user explicitly asks for the … workflow" | the user, by asking for it |
| Command | One line that loads a workflow skill, so the TUI has `/name` | the user, TUI only |
| Agent | A separate worker with its own context, permissions and report format | a workflow, in parallel |

One test decides whether a skill exists: **would the model get it wrong
without it?** General knowledge (DDD, framework docs, file formats) fails the
test; your conventions, environment and preferences pass it.

Workflows live once, in the skill. The command only forwards arguments,
because T3 Code does not surface opencode commands; there, ask for the
workflow by name ("run the commit workflow").

Workflow skills are deliberately **not** `disable-model-invocation: true`.
That flag hides a skill from the model's list, and only the TUI resolves
`@skill-id` mentions; a client like T3 Code sends plain text, so a hidden
skill becomes unreachable there (verified with `opencode run`, 2026-10). The
description guard plus the permission prompts on commit, push and `gh`
writes keep an unasked-for run from doing harm.

## Pipelines

**Plan-driven** (everywhere, the only one at kopf3):

| # | Step | Surface |
| --- | --- | --- |
| 1 | Interview → step plan in `docs/plans/<slug>.md` | `/plan` |
| 2 | Implement one step, verify, tick, stage, stop | `/plan-next` |
| 3 | Review the branch | `/review-all` |
| 4 | Stage small commits | `/commit` |
| 5 | Open the pull request | `/pr` |
| 6 | Work through PR review comments | `/review-comments` |

**Ticket-driven** (personal, GitHub issues):

| # | Step | Surface |
| --- | --- | --- |
| 1 | Rough idea → epic with stories as issues | `/epic` |
| 2 | Refine one story | `/refine <n> [--deep]` |
| 3 | Branch from the story, implement | built-in worktrees + `build` agent |
| 4 | Review, commit, PR, comments | as above |

`/interview` runs the question format on its own, for decisions that do not
need a plan.

## Inventory

| Scope | Knowledge skills | Workflow skills + commands | Agents |
| --- | --- | --- | --- |
| global | `architecture`, `conventional-commits`, `rust-workflow`, `interview`, `diagram`, `refinement-loop`, `i-have-adhd` (vendored) | `commit`, `pr`, `review-all`, `review-comments`, `plan`, `plan-next`; command `/interview` | `reviewer-code`, `reviewer-tests`, `reviewer-business`, `analyst-architecture`, `codebase-pattern-finder` |
| personal | `github-issues`, `github-personal` | `epic`, `refine` | — |
| work | — | — | — |

Anthropic's skill collection reaches `~/.claude/skills` through
`modules/apps/claude-code`. opencode scans that directory too, so its 17 IDs
are denied in `permission.skill`: they are general knowledge and only cost
context. claude-code keeps them.

`global/context.md` becomes `~/.config/opencode/AGENTS.md`: the output-style
rules, tool-call narration, the pointer to `interview`, and one line to look
up APIs that may have changed. OpenCode V2 reads `AGENTS.md` only, never
`CLAUDE.md`.

## Decisions

Settled during design; recorded so they are not re-litigated.

| Decision | Choice | Why |
| --- | --- | --- |
| Architecture standard | `architecture` skill states preferences (DDD, inward layers, shipping rules) | The model knows DDD, but not that you want it |
| Questions | One at a time, in chat, never a dialog; background, options, recommendation | A dialog hides the background needed to answer |
| Plans | Committed in `docs/plans/`, kept with `Status: done` | They record why something was built that way |
| Plan steps | Checkbox, goal, files, "Done when"; ticked only when verified | A new session has nothing but the file |
| Tickets at kopf3 | None written by the agent; Jira stays manual | Plans replace tickets for agent work |
| Hierarchy depth | Two levels: Epic → Story | A story is the unit you branch from |
| Ticket template | Context / Acceptance Criteria / Out of Scope / Design / Open Questions | `reviewer-business` checks against the criteria |
| Open Questions at creation | Must be empty | Otherwise the thinking is deferred to implementation |
| Review strictness | Report, blocking marked, never gates | You decide whether to proceed |
| Review team | Three: code, tests, business | Separate reviewers only where input or tools differ |
| Who commits | The user, unless told otherwise | Staging is cheap to undo, a commit less so |
| Model pins on agents | None | A pinned model is what rotted the upstream `agentic` files |

## Working files

```
docs/plans/<slug>.md   committed step plan, built by /plan
.work/
  epics/<slug>.md      epic draft; frontmatter records created issue numbers
  refine-<n>.md        story body during /refine
  pr-body.md           generated PR body
  commit-msg           multi-line commit message, when needed
  review-comments/     reply drafts for /review-comments, one file per thread
  diagrams/            rendered mermaid
```

`.work/` is ignored globally via `programs.git.ignores` in
`modules/profiles/core-user/git.nix`. Worktrees follow the `wt` convention at
`.work/<repo>-<branch>` (see [wt-workflow.md](wt-workflow.md)).

## Interview protocol

The `interview` skill, adapted from
[`github/spec-kit`](https://github.com/github/spec-kit)'s `/speckit.clarify`
(MIT) and sharpened in practice:

- Explore the code first; never ask what it can answer.
- **One question per message**, as chat text, ending in `?`.
- Each carries background, one consequence ("why it matters"), two to four
  options and a recommendation, so "yes" is a complete answer.
- **Record immediately** as a decision plus a `- Q: … → A: …` line.
- If the user questions the question, answer that first, then re-ask.
- If an answer exposes an earlier mistake, say so and re-ask that decision.

`refinement-loop` adds only the ticket part: where an answer lands in the
ticket's sections, and that refinement ends with Open Questions empty.

## Reviewers

`/review-all` fans out to three read-only subagents in parallel. Each burns its
own context window, which is the point — findings come back, exploration does
not. `/review-all code tests` runs a subset.

| Agent | Owns | Explicitly not |
| --- | --- | --- |
| `reviewer-code` | structure (per `architecture`), quality, security — tagged per angle | test depth, requirements |
| `reviewer-tests` | meaningfulness, edge/error coverage, determinism, runs the suite | production code |
| `reviewer-business` | requirements met, scope drift | how it is built |

`reviewer-business` finds requirements itself: what it is handed, else
`Closes #n` in the PR, else the issue number in the branch, else the plan in
`docs/plans/`. A Jira key is not readable; it asks for the text instead.

Findings carry a severity (**blocking** / **advisory**), a category (**Gap** /
**Bug** / **Verification miss** / **Scope drift**, borrowed from
`agent-watchdog`), a `file:line`, and a concrete fix. `/review-all` merges,
deduplicates, ranks, and names any reviewer that found nothing.

The merged report and the PR body share a structure: behaviour before → after,
then Schema, Contracts and Structure sections, omitted when empty.

## GitHub issue hierarchy (personal)

**Milestones are not epics.** They are flat, date-bound release buckets — no
nesting, one per issue. Use them for releases (`v1.0`), not for work
breakdown.

**An epic is an ordinary issue with sub-issues.** Limits: 100 sub-issues per
parent, 8 levels of nesting; sub-issues may cross repositories with the same
owner. `gh` handles it natively; the commands and traps are in the
`github-issues` skill.

GitHub's real issue types (an `Epic` type) are organisation-only; personal
repositories use `type:epic` / `type:story` labels instead.

## Visualisation

Mermaid is the only diagram format that renders everywhere it is needed.

| Surface | How |
| --- | --- |
| GitHub issues and PRs | native mermaid rendering |
| neovim | `snacks.image` (`nvf/utility.nix`) shells out to `mmdc`; Ghostty speaks the kitty graphics protocol |
| opencode | the `diagram` skill renders with `mmdc` and reads the PNG back as an attachment |
| IntelliJ / RustRover | built-in mermaid preview |

`imagemagick` is in `development.nix` because `snacks.image` calls `identify`.
Only mermaid is available — no `d2`, `plantuml` or Graphviz. Mermaid does not
render in Jira Cloud.

## Prior art

Surveyed before building. Conclusion: **build our own, steal two ideas.**

| Project | Verdict |
| --- | --- |
| [`github/spec-kit`](https://github.com/github/spec-kit) | MIT, opencode-integrated, but flat issues only. Took the `clarify` question protocol. |
| [`mbachorik/spec-kit-jira`](https://github.com/mbachorik/spec-kit-jira) | Stale. Epic/Story/Task mapping shape noted. |
| `Fission-AI/OpenSpec` | Same local-markdown limitation, global npm install. Skip. |
| `Cluster444/agentic` | MIT but abandoned. Adapted `codebase-pattern-finder`. |
| `darrenhinde/OpenAgentsControl` | `curl \| bash` install, and its `/commit` auto-pushes. Skip. |
| `oh-my-openagent` | Mutates `~/.config/opencode`, telemetry on by default, not open source. Skip. |
| [`BuilderIO/skills`](https://github.com/BuilderIO/skills) | MIT. `read-the-damn-docs` was forked as `docs-first`, later reduced to one line in `context.md`. Visual skills rejected, see below. |

### Why `visual-plan` / `visual-recap` were rejected

1. **They refuse to produce markdown**, while this workflow's output is
   markdown in issues, PRs and `docs/plans/`.
2. **Hosted mode uploads the diff** to a third-party database; secret
   redaction is an LLM instruction, not a filter.
3. **Local mode is not offline and not vendorable.**

Worth taking was the diff taxonomy (schema, contract, structure,
before/after), now used in `/pr` and `/review-all`.

**Do not install any of them.** Every installer is incompatible with
declarative Nix management.

## Untested

- The pipelines have not been run end to end since the rework; the pending
  checks are listed per step in [plans/opencode-rework.md](plans/opencode-rework.md).
- Whether the description guard reliably stops the model from starting a
  workflow nobody asked for.
