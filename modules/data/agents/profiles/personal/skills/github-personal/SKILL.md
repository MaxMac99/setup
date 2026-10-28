---
name: github-personal
description: Use in personal (non-work) projects when configuring git remotes, cloning, pushing, or anything that depends on which GitHub identity or SSH key is in play. Covers the personal email, why remotes stay plain git@github.com, and the kopf3 alias that must never appear here.
---

# GitHub identity in personal projects

## Identity is chosen by directory, not by remote URL

`modules/profiles/projects.nix` wires this up:

- `~/projects/private/` → `max_vissing@yahoo.de`, SSH key `~/.ssh/id_github`
- `~/projects/kopf3/` → `max.vissing@kopf3.de`, SSH key `~/.ssh/id_kopf3_github`

Git picks the email with `includeIf` on the repository location. SSH picks the
key by matching on the **current working directory**, via a predicate script
that ssh runs (`~/.ssh/in-kopf3-dir`). Because ssh inherits git's cwd, cloning
from inside `~/projects/kopf3` already uses the work key.

## Consequences

- **Remotes stay plain `git@github.com:owner/repo.git`.** Do not rewrite a
  remote to disambiguate an identity. The directory already does that.
- **Never use the `kopf3.github.com` alias in a personal repository.** It exists
  only as an escape hatch for work remotes that already spell it out, and it
  forces the work key. A personal repo with that alias will authenticate as the
  wrong account.
- **Do not set `user.email` in a personal repo's local config.** It is already
  correct from the directory. A local override silently defeats the mechanism
  and is easy to miss for months.
- If a commit ends up with the wrong author, the cause is almost always the
  repository being in the wrong directory — not a missing git config. Check
  `git rev-parse --show-toplevel` before changing any config.

## Verifying

```
git config user.email          # expect max_vissing@yahoo.de
ssh -T git@github.com          # expect the MaxMac99 account
```

## Clone location

Personal work belongs under `~/projects/private/`. Cloning elsewhere — `~/Git`,
`~/IdeaProjects`, the home directory — gets the personal email by default but
sidesteps the intended layout. Prefer `~/projects/private/<name>`, and note that
opencode's personal profile applies everywhere outside `~/projects/kopf3`
regardless.
