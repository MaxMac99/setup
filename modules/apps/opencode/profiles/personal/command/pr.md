---
description: Push the current branch and open a GitHub pull request with a generated title and body
---

Open a pull request for the current branch.

Extra instruction from the user (may be empty, or may name the base branch): $ARGUMENTS

## Steps

1. Establish the state. Run:
   - `git status --short` — refuse to continue if the tree is dirty; ask the
     user to commit or stash first.
   - `git rev-parse --abbrev-ref HEAD` — refuse if this is `main` or `master`.
   - `git log --oneline <base>..HEAD` where `<base>` is `$ARGUMENTS` if it names
     a branch, otherwise the repository's default branch.
   - `git diff <base>...HEAD` — read the actual changes, not just the subjects.

2. Derive the title from the commits:
   - One commit → reuse its subject verbatim, including type and scope.
   - Several commits → write a Conventional Commit style subject covering the
     whole branch, scoped to the common area.

3. Write the body to `.work/pr-body.md`:

   ```markdown
   ## Summary
   One or two sentences on what changed and why.

   ## Changes
   - Bullet per logical change, not per commit.

   ## Verification
   - Commands actually run, and their outcome.

   ## Notes
   Anything a reviewer needs: trade-offs, follow-ups, deliberate omissions.
   ```

   Drop any section that would be empty. Do not pad. If the branch closes an
   issue, add `Closes #<n>` at the end.

4. Push and open the PR:

   ```
   git push -u origin <branch>
   gh pr create --base <base> --title "<title>" --body-file .work/pr-body.md
   ```

   Both are outward-facing, so they will prompt for approval. Show the commands
   before running them.

5. Report the PR URL.

## Rules

- **Never** pass `--fill`; it produces a body that just restates the commits.
- Do not enable auto-merge. Do not merge. Opening the PR is where this stops.
- Do not add reviewers or labels unless the user asked.
- If a PR already exists for this branch (`gh pr view` succeeds), do not create a
  second one — offer to update the existing body instead.
- The `github-personal` skill covers identity. If the push authenticates as the
  wrong account, the repository is in the wrong directory.
