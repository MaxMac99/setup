---
description: Create an isolated git worktree for a ticket and fetch its body into .work/ticket.md
---

Prepare an isolated workspace for a ticket. This creates a worktree and fetches
the ticket — it does not start implementing.

Issue number: $ARGUMENTS

## 1. Fetch the ticket

```sh
gh issue view <n> --json number,title,body,labels,parent
```

Refuse to continue if the issue does not exist. If its body has no Acceptance
Criteria, warn that the ticket is unrefined and suggest `/refine <n>` first —
every downstream reviewer reads those criteria.

## 2. Work out the branch name

`<type>/<n>-<slug>`, where `<slug>` comes from the title (lowercase, hyphenated,
a few words) and `<type>` is the Conventional Commit type this work will
produce: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`,
`chore`.

The `type:epic` / `type:story` labels are not commit types — infer the type from
what the ticket actually does. **If it is genuinely ambiguous, ask.** The branch
name should agree with the commits and the eventual PR title.

## 3. Create the worktree

Place it as a sibling of the current repository, which matches the existing
bare-repository layout:

```sh
git worktree add ../<repo>-<n> -b <type>/<n>-<slug>
```

If that path exists already, do not clobber it — report it and stop. If the
branch exists, add the worktree on the existing branch instead of creating it.

## 4. Write the ticket into the worktree

```
../<repo>-<n>/.work/ticket.md
```

Contents: the issue number and URL, the title, and the full body. This file is
the contract for everything downstream — `reviewer-business` checks the
implementation against it. `.work/` is gitignored globally, so it will not be
committed.

## 5. Report

```
Worktree:  /abs/path/to/<repo>-<n>
Branch:    feat/42-profile-switching
Ticket:    .work/ticket.md  (#42 — Add per-directory profile switching)

Continue there with:  /move   (moves this session to the worktree)
or open a new opencode in that directory.
```

Note plainly that a command cannot change your shell's working directory, which
is why `/move` or a fresh session is needed.

## Rules

- Do not start implementing. This prepares the workspace and stops.
- Do not create the worktree inside the repository — siblings only.
- If the current repository has uncommitted changes, that is fine and does not
  block a worktree, but mention it so nothing is left behind by accident.
