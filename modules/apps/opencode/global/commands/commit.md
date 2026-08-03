---
description: Group the working tree into small logical commits, stage the first, and propose a Conventional Commit message
---

Prepare the current changes for committing. The user commits; you stage.

Extra instruction from the user (may be empty): $ARGUMENTS

## Steps

1. Inspect the working tree: `git status --short`, `git diff`, and
   `git diff --staged`. Read enough of the changed files to understand *why*
   each change was made — the diff alone is usually not enough to write an
   honest scope and subject.

2. Partition the changes into the smallest set of logical commits. State the
   plan before touching the index, as a short list:

   ```
   1. refactor(opencode): extract profile selection into the wrapper   [3 files]
   2. feat(opencode): add per-directory profile switching              [2 files]
   3. docs: record the ticket workflow                                 [1 file]
   ```

   If everything is genuinely one change, say so and propose a single commit.
   Do not split for the sake of splitting.

3. Stage **only the first group**, with explicit paths. Never `git add .` or
   `git add -A`. If one file carries changes belonging to two groups, say so and
   suggest `git add -p <file>` rather than staging the whole file.

4. Verify what you staged matches the intent: `git diff --staged --stat`.

5. Propose the message and hand over the exact command:

   ```
   git commit -m "feat(opencode): add per-directory profile switching"
   ```

   For a body, write it to `.work/commit-msg` and propose
   `git commit -F .work/commit-msg`.

6. Stop. **Do not run `git commit`.** After the user commits, offer to stage the
   next group.

## Rules

- Follow the `conventional-commits` skill for format, scope derivation, and git
  safety. Do not infer the message style from `git log` — this repository's
  history predates the convention.
- If the change touches Rust, confirm `cargo fmt` has been run and the check
  loop passes before proposing a commit.
- If tests are failing, say so plainly and ask whether to proceed. Do not
  propose a commit message that implies working code when it does not build.
- Never include tool attribution or co-author trailers in the message.
