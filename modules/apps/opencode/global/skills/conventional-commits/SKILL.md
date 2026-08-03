---
name: conventional-commits
description: Use when writing a git commit message, staging changes for commit, splitting work into commits, or running any git history operation (rebase, force-push, reset, cherry-pick). Covers the Conventional Commits format with scopes, commit granularity, and git safety rules.
---

# Commits and git safety

## Do not imitate the surrounding history

Most repositories here predate this convention. `git log` will show short
imperative subjects like `Add gclone`, `Fix kopf3 setup`, `Disable ligatures`.
**That is the old style. Do not copy it.** New commits use Conventional Commits
with a scope. Never infer the format from the existing log.

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:** `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`,
`chore`.

**Scope is required** whenever a sensible one exists. Derive it from the area
actually changed, not from the ticket:

| Change touches | Scope |
| --- | --- |
| `modules/apps/opencode/` | `opencode` |
| `modules/profiles/core-user/nvf/` | `nvf` |
| `hosts/nixos/maxdata/` | `maxdata` |
| a Rust crate | the crate name |
| several unrelated areas | omit the scope, or split the commit |

If you cannot name a single scope, that is usually a sign the commit is doing
too much. Prefer splitting.

**Subject:** imperative mood, lowercase after the colon, no trailing period,
under ~72 characters. `fix(opencode): stop tui plugin loading from opencode.json`,
not `Fixed the bug where...`.

**Body:** only when the change is not self-evident. Explain *why*, not what —
the diff already says what. Wrap at 72 columns.

**Footer:** `BREAKING CHANGE: <description>` for incompatible changes, and issue
references such as `Refs #42` or `Closes #42`.

## Granularity

One logical change per commit. A commit should be revertible on its own without
taking unrelated work with it. Concretely:

- Never mix a refactor with a behaviour change. Do the refactor first, commit,
  then change behaviour.
- Formatting-only churn goes in its own `style`-ish `chore` commit, so it does
  not bury real edits in a wall of whitespace.
- A commit should build. Do not commit a half-applied rename.

When staging, group by logical change rather than by file. Use `git add <path>`
per group, or `git add -p` when one file contains two unrelated changes.

## Git safety

These rules are absolute unless the user explicitly asks otherwise.

- **Act only on what was asked.** If the request is investigative — "why did
  this change", "what happened here" — report findings and stop. Do not commit,
  rebase, push, reset, or stash as a side effect of answering a question.
- **Never `git add .` or `git add -A`.** It sweeps up unrelated work and
  untracked files. Stage explicit paths.
- **Never rewrite shared history.** No rebase, amend, or force-push on `main`,
  `master`, or any branch that has been pushed and may be shared.
- **`--force-with-lease`, never plain `--force`.** Plain force discards commits
  that arrived after your last fetch, silently.
- **Never `git reset --hard`** unless the user asked for it in those words.
  Uncommitted work destroyed this way is unrecoverable.
- **Check before destructive operations.** `git status` and `git stash list`
  first; a dirty tree changes what is safe.
- Prefer `git revert` over history rewriting for anything already pushed.

## Who commits

Stage the changes and propose the message. **The user runs `git commit`.** Show
the exact command so it can be pasted:

```
git commit -m "feat(opencode): add per-directory profile switching"
```

For a multi-line message, write the body to a file and show
`git commit -F <file>`, rather than chaining `-m` flags.
