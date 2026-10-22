Status: in progress

# opencode rework: skills, agents, commands

Bring the opencode setup in `modules/apps/opencode/` up to OpenCode V2 and cut
it down to what earns its place. One test for every skill: would the model get
it wrong without it?

## Decisions

1. Skills the model loads on its own carry knowledge only: `conventional-commits`,
   `rust-workflow`, `github-issues`, `github-personal`, `interview`, `diagram`.
2. Workflows exist once, as a skill with `disable-model-invocation: true`, plus a
   one-line command for the TUI. T3 Code does not surface opencode commands.
3. The Anthropic collection (`~/.claude/skills`) is removed from opencode
   entirely. claude-code keeps it.
4. `architecture` is rewritten as the user's preferences (DDD, inward layers,
   shipping rules), not a textbook; the agents and `/epic` load it. Its
   mermaid table moves to the diagram workflow. `docs-first` is replaced by
   one line in `context.md`.
5. Workflows kept: commit, pr, review-comments, review-all, epic, refine.
   New: plan, plan-next. Removed: workspace, business-case.
6. Review team: `reviewer-code`, `reviewer-tests`, `reviewer-business`. The
   requirements come from `Closes #n` in the PR, else the branch name, else
   the plan in `docs/plans/` (the only source at kopf3, where tickets live in
   Jira).
7. Agents removed: `commit`, `diagram`, `review-all` (forwarders),
   `codebase-locator` (built-in `explore` covers it).
8. `/pr` and `/review-comments` become global. `/epic`, `/refine`,
   `github-issues`, `github-personal` stay personal (kopf3 uses Jira).
9. Plans live committed at `docs/plans/<slug>.md`, are built with the interview
   format, and are worked off one step per `/plan-next`.

## Steps

- [ ] **1. Wiring for V2 commands**
  - Goal: commands may carry `agent`, `model`, `subagent` frontmatter.
  - Files: `modules/apps/opencode/default.nix` (`profileCommands`),
    `profiles/*/command/` → `profiles/*/commands/`.
  - Done when: `nix flake check` passes and `/api/command` lists every
    profile command.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    check `opencode api get /api/command`.

- [ ] **2. Remove the Anthropic collection from opencode**
  - Goal: no Anthropic skill reaches opencode, claude-code is unaffected.
  - Files: `modules/apps/opencode/default.nix`.
  - First: check the V2 docs for a switch that stops scanning
    `~/.claude/skills`; fall back to `deny` per skill ID.
  - Done when: `/api/skill` lists none of the 17, and `ls ~/.claude/skills`
    still does.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    check `opencode api get /api/skill`.

- [x] **3. Prune knowledge skills**
  - Goal: only the knowledge the model lacks remains.
  - Files: `global/skills/{architecture,docs-first,rust-workflow}`,
    `profiles/personal/skills/github-issues`, `global/context.md`,
    `global/agents/{analyst,reviewer}-architecture.md`.
  - Done when: `docs-first` is gone, `architecture` states preferences only,
    and no skill hard-codes a tool version.

- [ ] **4. Interview skill**
  - Goal: one question at a time, with background, options and recommendation,
    usable everywhere.
  - Files: new `global/skills/interview/`, `global/skills/refinement-loop/`
    (shrinks to the ticket part), new `/interview` command, `global/context.md`.
  - Done when: `/interview` and a plain unclear request both trigger the format.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    try `/interview` with a real topic.

- [ ] **5. Workflow pattern for commit, review-all, diagram**
  - Goal: workflow skill plus thin command; forwarding agents gone.
  - Files: `global/commands/`, new `global/skills/{commit,review-all,diagram}/`,
    `global/agents/{commit,diagram,review-all}.md` (delete).
  - Done when: `/commit` works in the TUI and `@commit` works in T3 Code.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    run `/commit` in the TUI and load `commit` by name in T3 Code.

- [ ] **6. Review team of three**
  - Goal: `reviewer-code` replaces architecture, quality and security.
  - Files: `global/agents/reviewer-*.md`, `global/agents/codebase-locator.md`
    (delete), the review-all skill, epic and refine dispatch lists.
  - Done when: `/review-all` on a test branch returns one merged report from
    three reviewers, and `reviewer-business` finds the ticket without
    `.work/ticket.md`.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    run `/review-all` on a branch with a plan or `Closes #n`.

- [ ] **7. Profiles**
  - Goal: pr and review-comments global; epic and refine converted; workspace
    and business-case gone.
  - Files: `profiles/personal/`, `global/`, fix of the `photonic` path becomes
    moot with `workspace.md` deleted.
  - Done when: in `~/projects/kopf3`, `/pr` exists and `/epic` does not.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    open opencode in `~/projects/kopf3` and type `/`.

- [ ] **8. Plan and plan-next**
  - Goal: big tasks get a step plan in `docs/plans/`, worked off one step per
    run.
  - Files: new `global/skills/{plan,plan-next}/` and their commands.
  - Done when: this very file could have been produced by `/plan`, and
    `/plan-next` ticks a step and stops.
  - Pending: after `sudo darwin-rebuild switch` and `opencode service restart`,
    run `/plan-next` on this file.

- [ ] **9. Docs and final check**
  - Goal: the written docs match the new setup.
  - Files: `docs/opencode-workflow.md`, `docs/wt-workflow.md`, the
    `context` comment in `default.nix` (V2 no longer reads `CLAUDE.md`, so
    "AGENTS.md suppresses CLAUDE.md" is obsolete).
  - Done when: both mention no removed command or agent, and `/api/skill`
    plus `/api/command` show exactly the target set.

## Clarifications

### Session 2026-10-17

- Q: What are skills for? → A: knowledge only; workflows as manual skills
- Q: How do workflows stay reachable in T3? → A: skill + thin command
- Q: Keep explorer agents? → A: drop locator, keep pattern-finder
- Q: Interview as skill or command? → A: auto-invocable skill + thin command
- Q: Which Anthropic skills should opencode see? → A: none
- Q: What happens to `architecture`? → A: dissolve into agents + diagram
- Q: Where do the architecture preferences live? → A: rewritten skill,
  preferences only (corrects the previous answer: the model knows DDD, but
  not that the user wants it)
- Q: Keep `docs-first`? → A: drop it, one line in `context.md`
- Q: Which workflows are used? → A: keep six, drop workspace + business-case
- Q: Review team shape? → A: three reviewers, ticket from PR or branch
- Q: What does the work profile get? → A: no tickets; pr + review-comments
  global; new `/plan`
- Q: How is a plan worked off? → A: checkboxes + `/plan-next`
- Q: What happens to a finished plan? → A: stays committed, `Status: done`
