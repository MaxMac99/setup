---
description: Review the current change from several perspectives in parallel - architecture, quality, tests, business, security
---

Review the current change. Run the reviewers **in parallel**, then merge their
findings into one report.

Which reviewers to run (may be empty): $ARGUMENTS

## Selecting reviewers

No arguments — run all five: `reviewer-architecture`, `reviewer-quality`,
`reviewer-tests`, `reviewer-business`, `reviewer-security`.

Arguments — run only those named. `architecture`, `quality`, `tests`,
`business` and `security` all work, with or without the `reviewer-` prefix. Use
this for a fast pass mid-implementation: `/review-all quality tests`.

## Establishing the diff

Work out the base first and state it, so the reader knows what was reviewed:

1. If `$ARGUMENTS` contains a commit hash or branch name, compare against that.
2. Else if the current branch has an upstream or an obvious base (`main`),
   use `git diff main...HEAD` plus any uncommitted changes.
3. Else review uncommitted changes: `git diff` and `git diff --staged`.

Also gather `git status --short` so untracked files are not missed — new files
are exactly where problems hide.

## Dispatching

Launch every selected reviewer **in a single message** so they run
concurrently. Each gets:

- the base and how to reproduce the diff
- the list of changed files, including untracked ones
- the path to `.work/ticket.md` if it exists (essential for `reviewer-business`;
  if it is missing, say so and skip that reviewer rather than guessing at
  requirements)

Do not summarise the diff for them — they read the files themselves, and a
summary would launder your assumptions into their review.

## Merging

Collect all findings and produce one report. Lead with what changed, so a
reader who has not seen the diff can follow the findings:

```markdown
# Review: <base>...HEAD

## What changed
Two or three sentences. Behaviour before → after.

- **Schema:** any persisted-shape change, or "none"
- **Contracts:** API, CLI or wire-format changes, or "none"
- **Structure:** modules or boundaries that moved, or "none"

## Blocking
- **[Gap]** `src/sync/mod.rs:120` — *(tests)* retry path has no test.
  *Fix:* assert three attempts with expected delays.

## Advisory
- **[Scope drift]** `src/config.rs:12` — *(quality)* unrelated rename bundled in.

## Clean
architecture, security — no findings.
```

Rules for merging:

- **Deduplicate.** When two reviewers report the same line, merge into one
  finding and note both perspectives. Never list it twice.
- **Order by severity, then by file.** Blocking first, always.
- Attribute each finding to the reviewer that raised it, in parentheses.
- Name reviewers that found nothing, explicitly. Silence is otherwise
  indistinguishable from failure.
- If a reviewer failed or could not run, say so — do not quietly drop it.
- Include a mermaid diagram only if the change moved something structural and a
  diagram makes it clearer than the prose.

## Rules

- **This reports, it does not gate.** Blocking findings are marked clearly; the
  decision to proceed is the user's.
- Do not fix anything. This is a review. If the user wants fixes, they will ask.
- Do not pad. If all five come back clean, the report is three lines.
