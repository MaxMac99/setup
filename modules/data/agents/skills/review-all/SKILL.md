---
name: review-all
description: Only when the user explicitly asks for the review-all workflow: review the current change from three perspectives in parallel - code (structure, quality, security), tests, and business requirements.
---

# Review all

Review the current change. Run the reviewers **in parallel**, then merge their
findings into one report.

## Selecting reviewers

No reviewers named — run all three: `reviewer-code`, `reviewer-tests`,
`reviewer-business`.

Reviewers named in the user's message — run only those. `code`, `tests` and
`business` all work, with or without the `reviewer-` prefix. Use this for a
fast pass mid-implementation: `/review-all code tests`.

## Establishing the diff

Work out the base first and state it, so the reader knows what was reviewed:

1. If the user's message contains a commit hash or branch name, compare
   against that.
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
- for `reviewer-business`: a ticket or plan the user named, if any; otherwise
  it finds the requirements itself and stops if there are none

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
- **[Scope drift]** `src/config.rs:12` — *(code · quality)* unrelated rename
  bundled in.

## Clean
business — no findings.
```

Rules for merging:

- **Deduplicate.** When two reviewers report the same line, merge into one
  finding and note both perspectives. Never list it twice.
- **Order by severity, then by file.** Blocking first, always.
- Attribute each finding to the reviewer that raised it, in parentheses; for
  `reviewer-code`, add its angle (structure, quality, security).
- Name reviewers that found nothing, explicitly. Silence is otherwise
  indistinguishable from failure.
- If a reviewer failed or could not run, say so — do not quietly drop it.
- Include a mermaid diagram only if the change moved something structural and a
  diagram makes it clearer than the prose.

## Rules

- **This reports, it does not gate.** Blocking findings are marked clearly; the
  decision to proceed is the user's.
- Do not fix anything. This is a review. If the user wants fixes, they will ask.
- Do not pad. If all three come back clean, the report is three lines.
