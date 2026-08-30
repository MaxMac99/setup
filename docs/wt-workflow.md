# Worktree workflow (`wt`)

Isolated environments for agent and parallel work, with zero per-workspace setup.
The tool is `wt`, a small shell script packaged by this flake
(`modules/profiles/wt.sh`, wired into `modules/profiles/development.nix`), so it is
on PATH for every machine and every shell.

Status: **built and in use on `photonic`.** Other repos opt in by adopting the
convention (a short AGENTS.md section) — the script works on any repo under
`~/projects` without per-repo configuration.

## The problem it solves

Branches alone do not isolate work: agents need their own checkout while the main
checkout stays usable in the IDE. Fresh checkouts used to cost a manual
`direnv allow`, an IDE "reload environment", and reconfiguring toolchains —
per workspace, every time. This setup makes a fresh isolated environment a
single command and a `cd`.

## Layout

One standard clone per repo, one worktree per workstream, worktrees inside the
repo under `.work/`:

```
~/projects/private/photonic/                    main checkout — the daily IDE window
└── .work/
    └── photonic-feat-42-profile-switching/     one worktree per workstream
```

- The main checkout is a **normal clone**, not a bare repo. That is load-bearing:
  IntelliJ/RustRover's Git → Worktrees node needs a normal `.git` to anchor on,
  and the main checkout keeps its identity (`photonic`) in window titles,
  recent projects, and fuzzy finders.
- Worktree directory names carry the repo (`photonic-<branch>`), so every
  surface that shows a directory name — IDE title bar, window switcher,
  `zoxide` — says which project you are in, not just which branch.
- `.work/` is a single gitignore entry per repo, so diff tools and fuzzy
  finders skip it and `rm -rf .work` cleans everything.

⚠️ Do not use the `.bare` container layout (`.bare` + worktrees as siblings).
It breaks IDEA's native worktree support — no anchor repo, worktree creation
and in-window switching stop working — and its `<branch>`-as-dir-name convention
is what made every IDE window read as `main`.

## Commands

| Command | What it does |
| --- | --- |
| `wt new <repo> <branch> [base]` | Create `~/projects/<repo>/.work/<repo>-<branch>` from `<base>` (default: the repo's current HEAD). Prewarms `cargo fetch` when the worktree has a `Cargo.toml` and cargo is available. Prints the worktree path. |
| `wt list [repo]` | Worktrees with branch and dirty-file count. Without an argument: every repo under `~/projects`. |
| `wt prune [repo] [-y]` | Remove worktrees whose branch is fully merged into the repo's base (`main`/`master`). Asks per worktree unless `-y`. Skips worktrees with uncommitted changes. |

Repos are resolved under `~/projects` (one level of nesting), so `wt new photonic …`
finds `~/projects/private/photonic`. Override the root with `WT_PROJECTS_ROOT`.

Branch names with slashes are sanitized (`feat/42-x` → `photonic-feat-42-x`).
If the branch already exists, the worktree checks it out instead of creating it.

### Examples

```sh
wt new photonic feat/42-xmp-sidecar      # isolated env for an agent task
cd ~/projects/private/photonic/.work/photonic-feat-42-xmp-sidecar
wt list photonic                          # what is running, what is dirty
wt prune photonic                         # clean up merged workstreams
```

## Environment: nothing to set up

- **direnv auto-allows.** `programs.direnv.config.whitelist.prefix` in
  `modules/profiles/development.nix` trusts all of `~/projects`. A fresh worktree
  gets its environment on first `cd` — no `direnv allow`, ever.
- **nix-direnv** caches flake evaluations, so the same flake across worktrees
  evaluates against the same store path; activation is fast and offline.
- **The JetBrains Direnv integration plugin** sources `.envrc` into
  RustRover/IntelliJ, so run configurations and toolchain env stay in sync
  without "reload environment".

## Build cache across worktrees

Repos that use sccache (photonic does, in its devShell: `RUSTC_WRAPPER` +
`SCCACHE_DIR=~/.cache/photonic-sccache`) share one compile cache keyed to the
user, not the checkout. A fresh worktree's first build is mostly cache hits.

## Agents

Agent work must happen in a worktree, never by switching branches in the main
checkout. The convention lives in each repo's `AGENTS.md`/`CLAUDE.md` (see
photonic's for the reference wording). The short version for any agent:

- `wt new <repo> <branch>` — or plain `git worktree add` with the same path and
  naming: `.work/<repo>-<branch>`.
- Never create worktrees outside `.work/`, never name them `<branch>` alone.

The opencode `/workspace <issue>` command follows the same convention and
additionally drops the ticket body into the worktree's `.work/ticket.md`.

## IDE usage

IntelliJ/RustRover's Git tool window has a **Worktrees** node listing every
worktree. Double-click to switch the current window into a worktree and back —
no separate windows needed. The window title / status bar shows the current
branch, and worktree dir names (`photonic-feat-42-xmp-sidecar`) make each
environment self-describing in recent projects and window switchers.

## Shell integration (optional)

`wt new` prints the path; a command cannot change your shell's cwd. To jump
straight in, let your shell do it:

```zsh
wtn() { local d; d="$(wt new "$@")" && cd "$d"; }
```

## Where things live

| Thing | Location |
| --- | --- |
| Script | `modules/profiles/wt.sh` |
| Packaging | `modules/profiles/development.nix` (`pkgs.writeShellApplication`, shellchecked at build time) |
| direnv whitelist | `modules/profiles/development.nix` |
| Repo-side convention | each repo's `AGENTS.md` / `CLAUDE.md` |
| Layout root override | `WT_PROJECTS_ROOT` (default `~/projects`) |
