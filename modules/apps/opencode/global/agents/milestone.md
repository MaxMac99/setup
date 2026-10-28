---
# Build agent with the outward-facing git/gh steps of the milestone workflow
# loosened from `ask` to `allow`. Selected by /milestone; the global rules in
# core.nix stay as they are for every other session. Agent rules apply after
# the global ones and the last match wins, so the denies below must come after
# the broad allows - a `git push *` allow would otherwise also re-open the
# global `git push --force*` deny.
# The body is deliberately empty: a non-empty body replaces the base prompt.
description: Autonomous milestone implementation - may create .work/ worktrees, commit, push feature branches and open PRs. Selected by /milestone.
mode: primary
permissions:
  - { action: shell, resource: "wt new *", effect: allow }
  - { action: shell, resource: "wt list*", effect: allow }
  - { action: shell, resource: "git fetch*", effect: allow }
  - { action: shell, resource: "git -C * fetch*", effect: allow }
  - { action: shell, resource: "git commit *", effect: allow }
  - { action: shell, resource: "git push", effect: allow }
  - { action: shell, resource: "git push *", effect: allow }
  - { action: shell, resource: "gh pr create *", effect: allow }
  - { action: shell, resource: "gh pr edit *", effect: allow }
  - { action: shell, resource: "gh api repos/*/pulls/*/comments*", effect: allow }
  - { action: shell, resource: "gh api repos/*/pulls/*/reviews*", effect: allow }

  - { action: shell, resource: "git push * main*", effect: deny }
  - { action: shell, resource: "git push * master*", effect: deny }
  - { action: shell, resource: "git push *:main*", effect: deny }
  - { action: shell, resource: "git push *:master*", effect: deny }
  - { action: shell, resource: "git push --force*", effect: deny }
  - { action: shell, resource: "git push * --force*", effect: deny }
  - { action: shell, resource: "git push -f*", effect: deny }
  - { action: shell, resource: "git push * -f*", effect: deny }
  - { action: shell, resource: "gh pr merge*", effect: deny }
---
