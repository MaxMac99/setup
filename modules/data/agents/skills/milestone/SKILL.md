---
name: milestone
description: Only when the user explicitly asks for the milestone workflow: implement one milestone - a plan in docs/planning/plans/ or a milestone of a concept in docs/planning/concepts/ - with one worktree and T3 thread per pull request - commit per step, push, open the PR, get the pipeline green, and only then report.
---

# Milestone workflow

Implement every open step of one plan without stopping between steps, ship it
as pull requests, and report only when the pipeline is green or you are
stuck. This is the autonomous sibling of `plan-next`: same plan file, same
step discipline, but you commit, push and open the PRs yourself.

The unit of work is a **section**: one PR in one repository. A plan without
`### PR` sections is a single section. Each section runs in its own T3 thread,
bound to its own worktree under `<repo>/.work/`, so main checkouts and the
calling thread stay free.

Your role follows from the message:

- **Dispatch** - the user asked for the workflow → sections 1-4.
- **Implement** - the message says `Role: implement` → sections 5-11.

Whenever something is unclear - which plan, which base, a step that does not
fit the code, a decision only the user can make - load the `interview` skill
and ask in its style, one question at a time. Record the answer in the plan's
Clarifications. Do not guess and do not stop silently.

## 1. Dispatch: find the milestone

The user names one of:

- **a plan** - `docs/planning/plans/<slug>.md`, or the one with `Status: in progress`
  when nothing is named;
- **a concept milestone** - `<concept> M<n>`, or just the concept: then the
  first milestone without `PRs:` whose `Depends on` are merged.

Several candidates or none: ask. State "M<n>: <title>, plan <path or
missing>". For a multi-repo milestone (`[multi-repo]`, or more than one
repository in `Repos:` or the PR sections), lead with it on its own line:
"Multi-repo: <repo a> → <repo b>, <k> PRs", so the user sees it before
anything is created.

## 2. Dispatch: plan and preflight

1. Plan missing → run the `plan` workflow here, in this thread (the interview
   needs the user). Write it into the worktree of the section in the plan's
   repository (section 3), and commit it there with the concept's `Plan:`
   line as `docs(plan): …`. If no section lives in that repository, the plan
   gets its own `docs/<plan-slug>` worktree and a docs-only PR.
2. Plan exists only in a main checkout's working tree, uncommitted → ask
   whether to move it into the worktree.
3. **Preflight:** every repository a section names must be a T3 project
   (`t3_project_list`, match `repositoryIdentity.canonicalKey` like
   `github.com/<owner>/<name>` lowercase, else `workspaceRoot`). Any missing →
   stop before creating anything, and list which repositories must be added
   to T3.

## 3. Dispatch: worktrees

Per section whose `Depends on` is empty or already has a green PR:

1. `git -C <workspaceRoot> fetch origin`.
2. Base:
   - no predecessor, or it is merged → `origin/<default-branch>`;
   - a predecessor in the same repository with an open PR → its branch
     (stacked PR). Say so.
   - The previous concept milestone counts as a predecessor too.
3. Branch: `<type>/<plan-slug>`, with sections `<type>/<plan-slug>-pr<k>`.
4. `wt new <workspaceRoot> <branch> <base>`; if the branch exists (resume),
   `wt new <workspaceRoot> <branch>` or the path `wt list` shows. It prints
   `<workspaceRoot>/.work/<repo>-<branch-with-slashes-as-dashes>`. Never create
   a worktree elsewhere, never `git switch` in a main checkout.

Sections still waiting for a predecessor get no worktree yet; the
predecessor's thread starts them (section 10).

## 4. Dispatch: launch the threads

Per worktree from section 3, `t3_thread_launch` with the section's
`projectId`, title `<title> · M<n>` (plus ` · PR <k> <repo>` with sections),
`workspaceStrategy: {type: "existing_worktree", worktreePath: <path>,
branch: <branch>}`, and this message. T3 does not expand opencode commands,
so it names the workflow in words:

```text
Run the milestone workflow.
Role: implement
Plan: <absolute path to the plan>
Section: PR <k> - <title>   (omit without sections)
Concept: <absolute path> M<n>   (omit without a concept)
Worktree: <path>
Branch: <branch>
PR base: <branch>
Waits for: <PR k + thread link, …>   (omit if none)
```

Report every thread as `[<title>](t3-thread://v1/<threadId>)` with its
worktree path, list the sections still waiting, then stop. Do not wait.

Without the T3 tools (plain opencode TUI): create the worktree, say so, and
ask whether to continue here after `session_move` into it.

## 5. Implement: orient

Check the binding: `pwd` is the worktree from the message, the branch is the
one named, `git status --short` is clean. Mismatch → ask.

Read the plan's Decisions and Out of scope, and the concept's if there is
one; they bind every step. Work only your section's steps. Steps already
ticked are done - resume at the first open one.

The plan is ticked only where it is committed: in the thread of the plan's
repository. A section in another repository reads the plan from the given
path and leaves it untouched; its commits and PR are the record.

## 6. Implement: work the steps

For each open step of your section, in order (`<k>/<n>` counts your
section's steps):

1. Post the progress line `▶ <k>/<n> · <title>`.
2. Implement, staying inside the step's Files - as in `plan-next` step 2.
3. Verify with the step's "Done when" plus the repository's usual checks, and
   show the real output.
4. Commit per the `conventional-commits` skill, staging explicit paths - with
   the ticked plan and its updated `Progress:` line if it lives here. One
   step, one commit.
5. Make the progress visible (section 6b), then post
   `✓ <k>/<n> · <title> · <short sha>`.

Handle the exceptions like this:

- **Check keeps failing** - after three fix attempts, stop and name the
  doubtful assumption.
- **Needs the user** (sudo rebuild, deploy, manual test) - commit what is
  done, add `  - Pending: <what to run>` under the step (or in the report,
  outside the plan's repository), leave it open, and continue only with steps
  that do not depend on it.
- **Plan is wrong** (step too big, missing dependency, contradicts the code) -
  interview the user about the change, apply the answer to the plan if it
  lives here, else in the report; log it under Clarifications, continue.
- **Needs a repository the plan does not name** - section 7.

## 6b. Implement: keep progress visible

The user follows the run from the T3 sidebar and the PR, not from this
thread. After every step's commit:

1. **Thread title** - `t3_thread_update` with `action: "rename"` to
   `<launch title> · <k>/<n>`; later states replace the count:
   `· ⏸ pending`, `· CI`, `· ✓ green`, `· ✗ red`. Without the T3 tools, skip
   this.
2. **Draft PR** - after the first commit, push and open the PR as a draft:
   follow the `pr` skill from step 1 on with the PR base from the message,
   add `--draft`, and put a `## Progress` section first in the body - one
   checkbox per step of your section, ticked as committed. Fill in the
   section's `PR:` line in the plan if it lives here (commit it with the
   next step). If a PR already exists for the branch, keep it.
3. **Every later step** - push, then tick its box in the PR body
   (`gh pr edit <number> --body-file .work/pr-body.md`).

A failing push or edit does not stop the step; say so in the progress line
and retry with the next one.

## 7. Implement: an unplanned repository

The plan should have named every repository; this is the fallback.

1. Interview the user: add it as a new PR section, or stop?
2. On "add": preflight it (section 2.3); not a T3 project → stop the whole run
   and report. Otherwise add the section to the plan if it lives here, then
   create its worktree and thread as in sections 3-4, with a `Section:`
   brief that carries the change, why, the interface both sides rely on and
   how to verify.
3. Continue with steps that do not depend on it; the rest stay open, marked
   `Pending: PR <k>`.

## 8. Implement: open the pull request

When your section's steps are done (or pending):

1. In the plan's repository: set the plan's `Status: done` if no step in any
   section is open, fill in the section's `PR:` line, and with a concept the
   milestone's `PRs:` line - including other sections' PRs you can see via
   `t3_thread_read`. Commit as `docs(plan): …`.
2. Finish the draft from section 6b: rewrite its body per the `pr` skill,
   keeping `## Progress` first. Verification lists the commands from every
   step; Notes lists pending steps and links the other sections' PRs or
   threads. With a concept issue, add `Closes #<story>` to the last PR of
   the milestone. Push, `gh pr edit`, then `gh pr ready <number>` - without
   asking, this workflow is authorised for that. No PR yet (a resumed run)
   → create it now, not as a draft.
3. Multi-repo milestone: the body starts, above Progress, with
   `> Part <k> of <n> of a multi-repo change: <repo a> PR 1 → <repo b> PR 2.
   Merge in this order.` and links the other PRs as they exist.

Rename the thread to `<launch title> · CI`.

## 9. Implement: get the pipeline green

```sh
gh pr checks <number> --watch --fail-fast
```

Run it with a long timeout (up to 30 minutes). Then:

- **Green** → if the `coderabbit-round` skill is available, load and follow
  it. Rename the thread to `… · ✓ green`, or `… · ⏸ pending` when steps wait
  on the user. Then section 10.
- **Red** → `gh run view <run-id> --log-failed`, fix the cause, commit
  (`fix(<scope>): …` or `ci: …`), push, watch again. After three attempts,
  stop, rename the thread to `… · ✗ red` and report location, cause and
  what you tried.
- **No checks** a few minutes after opening → report that there is no
  pipeline instead of waiting.

Do not report "done" while anything is pending or red.

## 10. Implement: start dependent sections

Only when green. For each section whose `Depends on` names yours: if every
other predecessor in `Waits for` is green too (`t3_thread_read`), create its
worktree and thread as in sections 3-4 - base your branch when it is in this
repository, else `origin/<default-branch>`. Otherwise leave it; the last
predecessor to turn green starts it.

## 11. Implement: report

Only now, in one message:

1. Your PR URL and pipeline state (green / red with cause).
2. Steps done; steps pending on the user, with what to run.
3. Sections started from here, and the other sections' state
   (`t3_thread_read`, no waiting).
4. CodeRabbit outcome, if any.
5. If this was the milestone's last section and a concept exists: the next
   milestone's title - not started.

## Rules

- Allowed without asking: create worktrees under `.work/`, launch and
  rename T3 threads for them, commit, push the feature branch, open the PR
  as a draft, edit its body, mark it ready, reply to review comments.
- Never: work in a main checkout, push to `main`/`master`, force-push,
  rebase a pushed branch, merge, enable auto-merge, add reviewers or labels,
  remove worktrees (`wt prune` is the user's).
- One PR per thread, one milestone per dispatch. Do not start the next
  milestone.
- The plan file stays the source of truth: tick as you go and keep its
  `Progress:` line current, so an interrupted run can resume.
