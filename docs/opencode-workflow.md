# opencode ticket workflow

Design notes for a ticket-driven development pipeline in opencode: rough idea →
refined epic → child tickets → isolated implementation → multi-perspective
review → small commits.

Status: **base config built, pipeline not yet built.** See [Status](#status).

## Pipeline

| # | Step | Command | Scope |
| --- | --- | --- | --- |
| 1 | Rough description → local draft | `/epic` | per-profile |
| 2 | Q&A refinement until confident | `refinement-loop` skill | global |
| 3 | Architecture pass (DDD, deployment fit, mermaid) | `architecture` skill | global |
| 4 | Business viability, only when asked | `/business-case` | personal |
| 5 | Create epic + child tickets | `/epic` (continues) | per-profile |
| 6 | Refine a child ticket | `/refine <id>` | per-profile fetch |
| 7 | Take a ticket → worktree | `/start <id>` | per-profile fetch |
| 8 | Implement | built-in `build` agent | — |
| 9 | Quality / business / security review | `/review-all` | global |
| 10 | Stage small commits, user commits | `/commit` | global |

Steps 8–10 loop until the ticket is done, then `/pr`.

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

## Review triad

`/review-all` fans out to three subagents in parallel, each `edit: deny`,
`write: deny`, read-only bash. Each burns its own context window, which is the
point — findings come back, exploration does not.

| Agent | Answers |
| --- | --- |
| `reviewer-quality` | Conventions and style, test coverage, tests actually green (`cargo clippy -- -D warnings`, `cargo test`, `nix flake check`) |
| `reviewer-business` | Is every requirement in `.work/ticket.md` met? Anything silently dropped or quietly expanded? |
| `reviewer-security` | Injection, authz, secret handling, dependency surface, error paths that leak |

Findings are reported as `file:line` with a suggested fix, not just a complaint.

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

Nothing surveyed contains a single line about Nix, Pulumi or Kubernetes.

**Do not install any of them.** Every installer is incompatible with declarative
Nix management.

## Status

Built:

- `skills/conventional-commits`, `skills/rust-workflow`
- `commands/commit`
- personal `skills/github-personal`, `command/pr`
- permission posture, profile anchor, `.work/` gitignore, Anthropic skills pin

Not built yet:

- `skills/refinement-loop`, `skills/architecture`
- `commands/refine`, `start`, `review-all`
- `agents/reviewer-quality`, `reviewer-business`, `reviewer-security`
- `agents/codebase-locator`, `codebase-pattern-finder` — to be adapted from
  `Cluster444/agentic` (MIT, attribute in a header; strip the dead
  `claude-opus-4-1-20250805` model pin and the JS/Python/Go directory guides)
- personal `command/epic`, `command/business-case`, `skills/github-issues`
- work `command/epic`, `skills/jira-issues`, Rovo MCP config
