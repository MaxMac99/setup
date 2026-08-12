# opencode ticket workflow

Design notes for a ticket-driven development pipeline in opencode: rough idea →
refined epic → child tickets → isolated implementation → multi-perspective
review → small commits.

Status: **base config built, pipeline not yet built.** See [Status](#status).

## Pipeline

| # | Step | Command | Scope |
| --- | --- | --- | --- |
| 1 | Rough description → local draft | `/epic` | personal |
| 2 | Q&A refinement until confident | `refinement-loop` skill | global |
| 3 | Codebase grounding + architecture analysis | `codebase-locator`, `codebase-pattern-finder`, `analyst-architecture` | global |
| 4 | Architecture pass (DDD, deployment fit, mermaid) | `architecture` skill | global |
| 5 | Business viability, only when asked | `/business-case` | personal |
| 6 | Create epic + child stories | `/epic` (continues) | personal |
| 7 | Refine a story | `/refine <id> [--deep]` | personal |
| 8 | Take a ticket → worktree | `/workspace <id>` | personal |
| 9 | Implement | built-in `build` agent | — |
| 10 | Architecture / quality / tests / business / security review | `/review-all` | global |
| 11 | Stage small commits, user commits | `/commit` | global |

Steps 9–11 loop until the ticket is done, then `/pr`.

Anything that talks to a tracker is per-profile; anything that only reads
`.work/ticket.md` or the diff is global. That is why `/epic`, `/refine` and
`/workspace` sit in `profiles/personal/` while the reviewers do not.

## Decisions

Settled during design; recorded so they are not re-litigated.

| Decision | Choice | Why |
| --- | --- | --- |
| Hierarchy depth | Two levels: Epic → Story | A story is the unit you branch from; a third level needs its own refinement pass for little gain |
| Ticket template | Context / Acceptance Criteria / Out of Scope / Design / Open Questions | `reviewer-business` checks the implementation against the criteria, so the shape must be consistent |
| Open Questions at creation | Must be empty | Otherwise the thinking is deferred to implementation time, where it costs most |
| Review strictness | Report, blocking marked, never gates | Matches the ask-before-writing posture; you decide whether to proceed |
| Milestones | Untouched | Release containers on a different axis; an epic can span several |
| Refinement budget | ≤3 rounds of 3-5 questions | Bounded, with a confidence check between rounds |
| Analysts at refinement | Architecture only | Automatic in `/epic`, opt-in via `--deep` in `/refine` |
| Security knowledge | In `reviewer-security.md`, not a skill | Only one agent uses it; a skill would be indirection with a standing context cost |
| Model pins on agents | None | A pinned model is what rotted the upstream `agentic` files |

## Tracker-agnostic seam

Only `/epic`, `/refine` and `/start` know which tracker is in play. They write
plain markdown into `.work/`, and every downstream step reads that. This keeps
the tracker-specific surface to three files per profile instead of leaking
GitHub and Jira details into the reviewers and the commit flow.

```
.work/
  epics/<slug>.md    epic draft; frontmatter records created issue numbers
  ticket.md          the ticket currently being implemented
  pr-body.md         generated PR body
  commit-msg         multi-line commit message, when needed
```

`.work/` is ignored globally via `programs.git.ignores` in
`modules/profiles/core-user/git.nix`, so no per-repo `.gitignore` edits.

Worktrees are siblings: `../<repo>-<ticket>`, matching the existing bare-repo
layout.

## Refinement protocol

Adapted from [`github/spec-kit`](https://github.com/github/spec-kit)'s
`/speckit.clarify` (MIT). Its version caps at 5 questions in a single pass; this
one loops.

- **Up to 3 rounds, 3–5 questions per round.** After each round the agent states
  its confidence and stops early when high. Hard stop at 3 rounds.
- **One question at a time.** Never reveal the queued questions in advance.
- **Questions must be interrogative** and end in `?`. A topic label
  ("Acceptance device matrix") is not a question and is invalid.
- Each question carries one *why it matters* sentence, a
  `**Recommended:** Option X — <reasoning>` line, and options as a markdown
  table. The user may answer with a letter, "yes"/"recommended", or free text.
- **Record immediately.** Append to a `## Clarifications` section under a
  `### Session YYYY-MM-DD` heading as `- Q: <question> → A: <answer>`, then route
  the answer into the correct section of the draft (functional → Requirements,
  non-functional → Success Criteria as a measurable metric, edge case → Edge
  Cases) and save. Do not batch writes to the end.

## Ticket hierarchy

### GitHub (personal)

**Milestones are not epics.** They are flat, date-bound release buckets — no
nesting, one per issue, and the only rollup is an issue count. Use them for
releases (`v1.0`), not for work breakdown.

**An epic is an ordinary issue with sub-issues.** GA since November 2025; limits
are 100 sub-issues per parent and 8 levels of nesting. Sub-issues may cross
repositories as long as the owner is the same.

`gh` 2.97.0 supports this natively — no MCP server and no extension:

```sh
gh issue create --title "…" --body-file .work/epics/<slug>.md --label type:epic
gh issue create --parent <epic#> --label type:story --body-file -
gh issue edit <epic#> --add-sub-issue 51,52
gh issue edit 52 --add-blocked-by 51
gh issue view <epic#> --json number,title,subIssues,subIssuesSummary
```

`--body-file -` reads from stdin, which avoids shell-quoting problems with
multi-line markdown.

Gotchas worth not rediscovering:

- **GitHub Issue Types (a real "Epic" type) are organization-only.** Verified:
  `MaxMac99/setup` returns `issueTypes: null`, while `github/docs` returns
  Epic/Feature/Task/Bug. On personal repos, substitute `type:epic` /
  `type:story` labels. Moving personal repos under a free personal org would
  unlock real issue types — the single highest-leverage change for Jira parity.
- The REST sub-issue API (`POST /repos/{owner}/{repo}/issues/{n}/sub_issues`)
  takes `sub_issue_id`, the child's **internal integer id** — not its issue
  number, and not the GraphQL node id that `gh issue view --json id` returns.
  Get it with `gh api repos/O/R/issues/<n> --jq .id`. Only needed for reordering
  (`PATCH …/sub_issues/priority`), which `gh` does not expose. Note `gh api` is
  deliberately *not* in the permission allowlist, so it prompts: `gh api … -f x=y`
  implies POST, and any `gh api repos/*` allow would auto-approve issue creation.
- Bulk creation is subject to secondary rate limiting. Fan out slowly.
- `gh project` and `gh issue create --project` need a scope that is not granted
  by default: `gh auth refresh -s project`.

**Idempotency:** write created issue numbers back into the draft's frontmatter,
so re-running `/epic` never duplicates tickets.

### Jira (work)

Not yet configured — deferred. When it is:

- **Jira Cloud** → Atlassian Rovo MCP, remote at
  `https://mcp.atlassian.com/v1/mcp/authv2`, browser OAuth. Cloud only; no Data
  Center support. Rate limits are per-plan (Free 500/hr).
- Tools: `createJiraIssue`, `editJiraIssue`, `getJiraIssue`,
  `searchJiraIssuesUsingJql`, `getJiraIssueTypeMetaWithFields`.
- `getAccessibleAtlassianResources` is a **mandatory first call** for the
  `cloudId`.
- There is no dedicated parent/child link tool — parenthood is the `parent`
  **field** on create/edit, and its key differs between company-managed and
  team-managed projects. Resolve it at runtime with
  `getJiraIssueTypeMetaWithFields` rather than hardcoding.
- For Data Center, Rovo does not work; use
  [`sooperset/mcp-atlassian`](https://github.com/sooperset/mcp-atlassian)
  (MIT, supports Jira DC 8.14+).
- **Mermaid does not render in Jira Cloud** (descriptions are ADF). Diagrams
  will appear as unrendered code blocks unless the instance has a plugin.
  Mermaid does render natively on GitHub.

## Visualisation

Mermaid is the only diagram format that renders everywhere you need it, which
is why the workflow standardises on it rather than anything richer.

| Surface | How |
| --- | --- |
| GitHub issues and PRs | native mermaid rendering in markdown |
| neovim | `snacks.image` (`nvf/utility.nix`) shells out to `mmdc` for mermaid blocks; Ghostty speaks the kitty graphics protocol |
| opencode TUI | `/diagram` renders with `mmdc` and reads the PNG back as an attachment; opentui detects kitty graphics (`OPENTUI_GRAPHICS`, default on) |
| ad hoc | `mmdc -i x.mmd -o x.png` for SVG/PNG/PDF |
| IntelliJ / RustRover | built-in mermaid preview in markdown |

The same source text therefore renders in the draft you are refining, the
GitHub issue, and the pull request — with no additional infrastructure.

`imagemagick` is in `development.nix` because `snacks.image` calls `identify`
for image dimensions; `mmdc` emits PNG directly, so it is not needed for the
conversion itself. Only mermaid is available — no `d2`, `plantuml` or Graphviz.

## Reviewers

`/review-all` fans out to five subagents in parallel, each `edit: deny`,
`write: deny`. Each burns its own context window, which is the point — findings
come back, exploration does not. A bare `/review-all` runs all five;
`/review-all quality tests` runs a subset for a cheap pass mid-implementation.

Remits are deliberately disjoint, and each file carries an explicit "not your
remit" section, so two reviewers never report the same thing.

| Agent | Owns | Explicitly not |
| --- | --- | --- |
| `reviewer-architecture` | boundaries, layering, coupling, cycles, deployment fit | style, test depth |
| `reviewer-quality` | conventions, naming, readability, error handling, dead code | test depth, structure |
| `reviewer-tests` | meaningfulness, edge/error coverage, determinism, runs the suite | production-code style |
| `reviewer-business` | acceptance criteria in `.work/ticket.md` met, scope drift | how it is built |
| `reviewer-security` | injection, authz, secrets, deps, disclosure | general quality |

Findings carry a severity (**blocking** / **advisory**), a category (**Gap** /
**Bug** / **Verification miss** / **Scope drift**, borrowed from
`agent-watchdog`), a `file:line`, and a concrete fix. `/review-all` merges,
deduplicates, ranks, and names any reviewer that found nothing — silence is
otherwise indistinguishable from failure.

The merged report and the PR body share a structure: behaviour before → after,
then Schema, Contracts and Structure sections, omitted when empty. That
taxonomy is the one genuinely good idea taken from `visual-recap`.

## Prior art

Surveyed before building. Conclusion: **build our own, steal two ideas.**

| Project | Verdict |
| --- | --- |
| [`github/spec-kit`](https://github.com/github/spec-kit) | 125k★, MIT, healthy, officially opencode-integrated. But local-markdown only: `/speckit.taskstoissues` creates one **flat** issue per task — no epic, no parent, no Jira. Steal the `clarify` question protocol. |
| [`mbachorik/spec-kit-jira`](https://github.com/mbachorik/spec-kit-jira) | 33★, MIT, stale. Steal the Epic/Story/Task mapping-config shape. |
| `Fission-AI/OpenSpec` | 63k★, same local-markdown limitation, global npm install. Skip. |
| `Cluster444/agentic` | MIT but abandoned (38 commits, one week, ~11 months cold). Two agent files worth adapting; best idea is enforcing role separation with `read: false` rather than instructions. |
| `darrenhinde/OpenAgentsControl` | 4.7k★, maintained, but `curl \| bash` install, TypeScript/Next.js content, and its `/commit` auto-pushes without asking. Skip. |
| `oh-my-openagent` | 67k★, hyperactive. Mutates `~/.config/opencode`, prebuilt npm binaries, telemetry on by default, auto-merges PRs. SUL-1.0, not open source. Skip. |
| `spec-kit-worktree`, `spec-kit-review` | A paragraph of prose and a quality-only reviewer respectively. Not dependencies. |
| [`BuilderIO/skills`](https://github.com/BuilderIO/skills) | 3.9k★, MIT, actively maintained. Took `read-the-damn-docs` (forked as `docs-first`). Rejected the visual skills — see below. |

Nothing surveyed contains a single line about Nix, Pulumi or Kubernetes.

### Why `visual-plan` / `visual-recap` were rejected

They are well made, and the temptation is real. Three disqualifying reasons:

1. **They refuse to produce markdown.** From their own `references/
   connection.md`: *"The deliverable is ALWAYS a published Agent-Native Plan,
   never inline chat content… Falling back to inline content is a defect, not a
   degraded mode."* This workflow's entire output is markdown in a GitHub issue
   or PR body. GitHub does not render MDX/JSX.
2. **Hosted mode uploads the diff** — real paths, verbatim hunks, schema with
   column types, API routes — to a third-party database. Secret redaction is an
   LLM instruction, not a filter. Unacceptable for work code.
3. **Local mode is not offline and not vendorable.** It needs
   `npx @agent-native/core plan local serve` at runtime, the renderer is still
   `plan.agent-native.com` reading from a localhost bridge, and valid MDX
   requires a live `get-plan-blocks` call because the tag names drift.

What was worth taking: the diff taxonomy — schema change, contract change,
structural move, before/after as the headline — now used in `/pr` and
`/review-all` with mermaid, which renders natively where it is needed.

Also rejected: `plow-ahead` (converts clarifying questions into assumptions —
the exact inverse of the refinement design), `rewind` (a signed macOS
screen-recording app plus an MCP broker installed via npx).

**Do not install any of them.** Every installer is incompatible with declarative
Nix management.

## Status

Built:

- Global skills — `conventional-commits`, `rust-workflow`, `refinement-loop`,
  `architecture`, `docs-first`, plus vendored `i-have-adhd` (pinned from
  `ayghri/i-have-adhd`, on demand via `/i-have-adhd`)
- Global rules — `global/context.md` → `~/.config/opencode/AGENTS.md`, the
  always-on short form of the `i-have-adhd` output rules. Applies to every
  session on both Macs. ⚠️ It also suppresses `~/.claude/CLAUDE.md`, which
  opencode would otherwise use as the global rules file
- Global agents — `analyst-architecture`, `reviewer-{architecture,quality,
  tests,business,security}`, `codebase-locator`, `codebase-pattern-finder`
- Global commands — `commit`, `review-all`, `diagram`
- Personal — `skills/{github-personal,github-issues}`,
  `command/{pr,epic,refine,workspace,business-case}`
- Config — permission posture, profile anchor, `.work/` gitignore, Anthropic
  skills pin, `imagemagick`

Not built yet:

- Work profile: `command/epic`, `command/refine`, `command/workspace`,
  `skills/jira-issues`, and the Rovo MCP server. Deferred until Jira is wanted;
  the GitHub versions are the reference implementation.

Untested:

- The whole pipeline is written but has not been exercised end to end. First
  real run should be a small epic on a personal repository.
- `/diagram` depends on the opencode TUI actually displaying an image
  attachment. The capability exists (`OPENTUI_GRAPHICS`); it has not been
  confirmed in practice.
- Inline mermaid in neovim needs `imagemagick`, added at the same time as this
  batch and not yet verified after a rebuild.
