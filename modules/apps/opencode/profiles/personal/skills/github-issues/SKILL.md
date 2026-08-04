---
name: github-issues
description: Use when creating, linking or updating GitHub issues - epics and their child stories, sub-issue hierarchy, labels, dependencies. Covers why milestones are not epics, the gh commands that work, and the API traps.
---

# GitHub issues as a Jira-style hierarchy

## Milestones are not epics

A milestone is a **release container**: flat, date-oriented, one per issue, and
the only rollup is a count of open and closed issues. There is no nesting and no
parent milestone. Use milestones for `v1.0` and sprints. An epic can span
several milestones.

**An epic is an ordinary issue that has sub-issues.** That is GitHub's real
hierarchy, generally available since November 2025. Limits: **100 sub-issues per
parent**, **8 levels of nesting**. Sub-issues may live in a different repository
as long as the owner is the same.

## Issue types are organisation-only

GitHub's native issue types — a real `Epic` type — are configured at
organisation level. **On a personal account the field is `null`**, and
`gh issue create --type` will not work. Verified: `MaxMac99/setup` returns
`issueTypes: null`, while an org repository returns Epic/Feature/Task/Bug.

So substitute labels: **`type:epic`** and **`type:story`**. Create them if they
do not exist — this is idempotent enough to run before first use:

```sh
gh label create "type:epic"  --color 5319E7 --description "Epic-level work item" 2>/dev/null || true
gh label create "type:story" --color 1D76DB --description "Story under an epic"  2>/dev/null || true
```

(Moving personal repositories under a free personal organisation would unlock
real issue types. Worth knowing; not required.)

## Commands that work

`gh` 2.97+ supports sub-issues natively. No extension, no MCP server.

```sh
# Create an epic
gh issue create --title "…" --body-file .work/epics/<slug>.md --label type:epic

# Create a story directly under it
gh issue create --title "…" --body-file - --parent 42 --label type:story

# Adopt issues that already exist
gh issue edit 42 --add-sub-issue 51,52

# Express ordering between stories
gh issue edit 52 --add-blocked-by 51

# Read the tree back
gh issue view 42 --json number,title,body,subIssues,subIssuesSummary
gh issue list --json number,title,parent,subIssuesSummary --limit 100

# Replace a body after refinement
gh issue edit 51 --body-file .work/ticket.md
```

`--body-file -` reads from stdin. Prefer it for anything multi-line — it avoids
shell-quoting problems with markdown, backticks and mermaid blocks entirely.

## Traps

- **The REST sub-issue API takes an internal integer id, not the issue number.**
  `POST /repos/{owner}/{repo}/issues/{n}/sub_issues` wants `sub_issue_id`, which
  is the child's database id. `gh issue view --json id` returns the *GraphQL node
  id* (`I_kwDO…`), which will not work. Get the right one with
  `gh api repos/O/R/issues/<n> --jq .id`. You only need this for reordering
  (`PATCH …/sub_issues/priority`), which `gh` does not expose — everything else
  is covered by the commands above.
- **`gh api` is not in the permission allowlist** and will prompt, deliberately:
  `gh api … -f x=y` implies POST, so allowing it would auto-approve issue
  creation.
- **Bulk creation hits secondary rate limits.** Creating a dozen stories in a
  tight loop will start failing. Create them one at a time and stop on error
  rather than retrying blindly.
- **Projects need an extra scope.** `gh project` and `gh issue create --project`
  fail until `gh auth refresh -s project` has been run once.

## Idempotency

Record what you created in the draft's frontmatter, and check it before
creating anything:

```yaml
---
issue: 42
children: [51, 52, 53]
---
```

If `issue:` is already set, the epic exists — update it with `gh issue edit`
rather than creating a duplicate. Same for each child. Re-running a creation
command must never produce a second copy.
