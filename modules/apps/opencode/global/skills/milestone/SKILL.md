---
name: milestone
description: Only when the user explicitly asks for the milestone workflow: implement a whole milestone of a plan in docs/plans/ in its own worktree and T3 thread - commit per step, push, open the PR, get the pipeline green, and only then report.
---

# Milestone workflow

Implement every open step of one milestone without stopping between steps,
ship it as one pull request, and report only when the pipeline is green or
you are stuck. This is the autonomous sibling of `plan-next`: same plan file,
same step discipline, but you commit, push and open the PR yourself.

The work never happens in the thread that was asked. It runs in a new T3
thread bound to its own worktree under `<repo>/.work/`, so the main checkout
and the calling thread stay free.

The workflow has three roles. Which one you are follows from the message:

- **Dispatch** - the user ran `/milestone` → sections 1-3.
- **Implement** - the message says `Role: implement` → sections 4-9.
- **Sibling** - the message says `Role: sibling` → section 10.

Whenever something is unclear - which plan, which base, a step that does not
fit the code, a decision only the user can make - load the `interview` skill
and ask in its style, one question at a time. Record the answer in the plan's
Clarifications. Do not guess and do not stop silently.

## 1. Dispatch: find the milestone

The plan is the file the user named, else the one in `docs/plans/` with
`Status: in progress`. Several or none: ask.

The milestone is the one the user named, else the first `### Milestone`
section with an open checkbox. A plan without milestone headings is one
milestone. State "milestone <m> of <n>: <title>, <k> open steps".

The plan must be committed on the base branch below; the worktree only sees
committed files. If it is not, ask whether to commit it first.

## 2. Dispatch: worktree

1. `git fetch origin`.
2. Base:
   - the previous milestone's PR is merged, or this is the first →
     `origin/<default-branch>`;
   - the previous milestone's PR is still open → its branch, as a stacked PR.
     Say so.
3. Branch: `<type>/<plan-slug>-m<m>`.
4. Create the worktree with the `wt` convention, from the repository's main
   checkout:
   - new branch: `wt new <repo-root> <branch> <base>`
   - branch exists (resume): `wt new <repo-root> <branch>`, or reuse the path
     `wt list` already shows for it.

   It prints `<repo-root>/.work/<repo>-<branch-with-slashes-as-dashes>`. Never
   create a worktree elsewhere, never `git switch` in the main checkout.

## 3. Dispatch: launch the thread

1. `t3_project_list` → the project whose `workspaceRoot` is this repository's
   main checkout.
2. `t3_thread_launch` with that `projectId`, title
   `<plan title> · M<m> <milestone title>`,
   `workspaceStrategy: {type: "existing_worktree", worktreePath: <path>, branch: <branch>}`
   and a message carrying everything the new thread needs:

   ```text
   /milestone
   Role: implement
   Plan: docs/plans/<slug>.md
   Milestone: <m> - <title>
   Worktree: <path>
   Branch: <branch>
   PR base: <default-branch or previous milestone branch>
   ```

3. Report the thread as `[<title>](t3-thread://v1/<threadId>)` and the
   worktree path, then stop. Do not wait for it.

Without the T3 tools (plain opencode TUI): create the worktree as above, then
say so and ask whether to continue here after `session_move` into it.

## 4. Implement: orient

Check the binding: `pwd` is the worktree from the message, the branch is the
one named, `git status --short` is clean. Mismatch → ask.

Read the plan's Decisions and Out of scope; they bind every step. Steps
already ticked are done - resume at the first open one.

## 5. Implement: work the steps

For each open step of the milestone, in order, announce
"step <k> of <n>: <title>" and then:

1. Implement, staying inside the step's Files - as in `plan-next` step 2.
2. Verify with the step's "Done when" plus the repository's usual checks, and
   show the real output.
3. Tick the checkbox, stage the step's files and the plan with explicit paths,
   and commit per the `conventional-commits` skill. One step, one commit.

Handle the exceptions like this:

- **Check keeps failing** - after three fix attempts, stop and name the
  doubtful assumption.
- **Needs the user** (sudo rebuild, deploy, manual test) - commit what is
  done, add `  - Pending: <what to run>` under the step, leave it open, and
  continue only with steps that do not depend on it.
- **Plan is wrong** (step too big, missing dependency, contradicts the code) -
  interview the user about the change, apply the answer to the plan, log it
  under Clarifications, continue.
- **Needs another repository** - section 6.

## 6. Implement: changes in another repository

1. Identify the repository by its remote (`owner/name`).
2. `t3_project_list`, match on `repositoryIdentity.canonicalKey` (e.g.
   `github.com/<owner>/<name>`, lowercase), else on `workspaceRoot`.
3. **Not a T3 project** → stop the whole run. Report which repository, what
   change it needs, and that it must be added to T3 first. Commit and push
   what is done; open no PR.
4. **A T3 project** →
   1. `git -C <workspaceRoot> fetch origin`, then
      `wt new <workspaceRoot> <branch> origin/<its-default-branch>` with a
      branch named after this milestone (`<type>/<plan-slug>-m<m>`).
   2. `t3_thread_launch` with that project's `projectId`, the new worktree as
      `existing_worktree`, title `<plan title> · M<m> · <repo name>`, and the
      message:

      ```text
      /milestone
      Role: sibling
      Origin: <this repo> PR/branch <branch>, plan docs/plans/<slug>.md
      Worktree: <path>
      Branch: <branch>
      PR base: <its default branch>
      Change: <self-contained brief: what, why, interface both sides rely on,
              how to verify>
      ```

   3. Note the sibling under the step: `  - Sibling: <repo> <thread link>`.
   4. Continue with steps that do not depend on it. Steps that do stay open,
      marked `Pending: sibling <repo>`.

## 7. Implement: open the pull request

When the milestone's steps are done (or pending):

1. Under the milestone heading add `PR: <url>` once known; if no open step is
   left in the whole plan, set `Status: done`. Commit as `docs(plan): …`.
2. Follow the `pr` skill from step 1 on, with the PR base from the message.
   Push and create without asking - this workflow is authorised for that.
   Verification lists the commands from every step; Notes lists pending steps
   and sibling threads.

If a PR already exists for the branch, push and keep it; update the body only
if it is now wrong.

## 8. Implement: get the pipeline green

```sh
gh pr checks <number> --watch --fail-fast
```

Run it with a long timeout (up to 30 minutes). Then:

- **Green** → if the `coderabbit-round` skill is available, load and follow
  it. Then section 9.
- **Red** → `gh run view <run-id> --log-failed`, fix the cause, commit
  (`fix(<scope>): …` or `ci: …`), push, watch again. After three attempts,
  stop and report location, cause and what you tried.
- **No checks** a few minutes after opening → report that there is no
  pipeline instead of waiting.

Do not report "done" while anything is pending or red.

## 9. Implement: report

Only now, in one message:

1. PR URL and pipeline state (green / red with cause).
2. Steps done; steps pending on the user, with what to run.
3. Sibling threads and their state (`t3_thread_read`, no waiting).
4. CodeRabbit outcome, if any.
5. The next milestone's title - not started.

## 10. Sibling: implement a cross-repo change

You were launched by a milestone thread for one change in this repository.

1. Orient as in section 4, with the `Change` brief instead of plan steps -
   the plan lives in the other repository.
2. Implement in as few steps as the change needs, one commit each, verified
   as in section 5. Unclear brief → interview the user.
3. A further repository is needed → section 6 applies here too.
4. Open the PR (section 7, without plan updates; mention the origin PR or
   branch in Notes), get it green (section 8), report (section 9).

## Rules

- Allowed without asking: create worktrees under `.work/`, launch T3 threads
  for them, commit, push the feature branch, open the PR, reply to review
  comments.
- Never: work in the main checkout, push to `main`/`master`, force-push,
  rebase a pushed branch, merge, enable auto-merge, add reviewers or labels,
  remove worktrees (`wt prune` is the user's).
- One milestone per run. Do not start the next one.
- The plan file stays the source of truth: tick as you go, so an interrupted
  run can resume.
