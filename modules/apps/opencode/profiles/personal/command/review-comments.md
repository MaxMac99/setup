---
description: Work through the open review comments on the current PR - judge every comment, fix the justified ones, rebut the rest, one commit per comment, then rebase and push
---

Process the open review comments on the current pull request. Every comment
gets an answer, and you judge it yourself: fix what is justified, rebut what
is not, ask the user before guessing. Nothing is left unanswered.

PR number or extra instruction (may be empty): $ARGUMENTS

## 1. Establish the PR

- `git status --short` — refuse on a dirty tree; ask the user to commit or
  stash first. The per-comment commit flow needs a clean base.
- `gh pr view` — the PR named in `$ARGUMENTS`, else the PR for the current
  branch. Record number, `baseRefName`, `headRefName`, URL. No PR → stop and
  offer `/pr`.

## 2. Fetch the review threads

One GraphQL call, so reading everything costs a single approval (`gh api` is
deliberately not allowlisted):

```sh
gh api graphql -f query='
query($owner:String!,$repo:String!,$number:Int!){
  viewer{login}
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:50){
        nodes{
          id isResolved isOutdated path line startLine
          comments(first:20){nodes{
            databaseId body diffHunk author{login} createdAt
          }}
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F number=<number>
```

`gh pr view --json` has no review-comment field (gh 2.100), which is why this
is GraphQL. `<owner>/<repo>` comes from
`gh repo view --json nameWithOwner -q .nameWithOwner`.

Reduce to the work list:

- Drop threads with `isResolved: true`.
- Drop comments by `viewer.login` — your own comments are not under review.
- A thread's unit of work is its **latest non-viewer comment**; older comments
  in the chain are context.
- If a thread's newest comment is already yours, skip it — the ball is with
  the reviewer. List it in the final report as pending.
- `isOutdated` threads stay in the list; the code may have moved, so judge the
  comment against the code as it is now.

State the work list before touching anything: `path:line`, reviewer, one-line
summary. Empty list → say so and stop; do not invent work.

## 3. Judge each comment

Work threads one at a time, in file order. Announce each as
"thread <k> of <n> — <path>:<line>". Read the code at `path:line` plus enough
context to be sure (and `git log -L` when history matters), then pick one
verdict and state it before acting:

- **Justified** — the objection is factually right and the change is worth
  making. Fix it.
- **Unjustified** — wrong on the facts, already handled elsewhere, or it
  contradicts a documented convention the reviewer could not have known.
  Rebut it.
- **Question** — asks for information, not a change. Answer it.

Standard of proof: review comments from a competent reviewer are usually
justified. Rebutting is the exception and needs a reason you could defend line
by line — cite the file, the convention (with its path), or the commit that
already handles the point. "It is fine as it is" is not a rebuttal. Do not
change code merely to end a discussion.

If a justified fix needs a decision you cannot make alone — a trade-off,
missing context, a product choice — ask in **this chat** (the `question`
tool), never as a GitHub comment. Take the answer and continue. GitHub
receives verdicts only, never questions.

## 4. Act on the verdict

**Justified → fix, commit, draft the reply.**

1. Make the smallest change that answers the comment. No drive-by refactors.
2. Verify per this repository's conventions — formatter, typecheck, and the
   tests that cover the touched code. A fix that fails verification is not
   done.
3. Stage exactly this fix's files and commit immediately, before the next
   thread. **One commit per comment, never two comments in one commit.**
   Follow the `conventional-commits` skill. Make the subject unique within the
   run (a file name in the scope helps) — step 6 finds the commit by subject.
4. Draft the reply into `.work/review-comments/reply-<k>.md`: one line on
   what changed and why it answers the comment. The final hash is added after
   the rebase (it rewrites the shas), so this reply is not posted yet.

**Unjustified or Question → reply now.** Write the answer — the rebuttal with
its citation, or the answer to the question — to
`.work/review-comments/reply-<k>.md`. Match the reviewer's language; short
and factual. Show the text in the chat, then post it as a reply to that
comment:

```sh
gh api repos/<owner>/<repo>/pulls/<number>/comments/<latest-comment-id>/replies \
  -F body=@.work/review-comments/reply-<k>.md
```

These post immediately because they reference nothing the rebase will move.
You are answering an argument, not winning one.

If a fix fails verification or a call fails, stop that thread, report it, and
move on. Failed threads surface as open in the final report.

## 5. Rebase and push

Only once every thread is handled:

1. `git fetch origin <base>` — check the exit status before trusting the refs.
2. `git rebase origin/<base>` with the step-4 commits stacked. On conflicts:
   attempt only resolutions you are certain of, state each one, and
   `git rebase --abort` + hand over when in doubt. `git reset --hard` is
   denied in this setup and is not a recovery path.
3. `git push`; if the remote rejects a rewritten branch,
   `git push --force-with-lease` (prompts; the lease refuses to clobber a
   remote someone else moved).

## 6. Post the "Fixed" replies

Now the hashes are final. Map each draft to its commit — `git log
--format='%h %s' <base>..HEAD`, match by subject — and make the final text
`Fixed in <hash>. <draft line>`. Show each final text and post it as in
step 4.

Then ask **once** whether to resolve the threads that were fixed. Only on
yes, per thread:

```sh
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id=<thread-id>
```

Rebutted threads stay open — the reviewer decides those, not you.

## 7. Report

One table: thread → verdict → outcome (commit hash / reply posted / question
asked / pending with reviewer). Name anything open and why. Close with the
branch state: base, commits added, pushed or not.

## Rules

- Every open comment gets an answer — silence is the only unacceptable
  outcome.
- One commit per justified comment. Never bundle fixes.
- Questions to the user live in this chat. Never post a question to GitHub.
- Do not respond to CI checks or mergeability here; comments only.
- If the run stops before step 6, the drafts remain in
  `.work/review-comments/`; finish posting them on the next run or by hand.
- If the PR has no open review comments, say so and stop.
