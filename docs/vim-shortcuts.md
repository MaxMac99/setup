# Vim Shortcuts: Neovim (nvf) vs IntelliJ (IdeaVim)

## Navigation

| Action | Neovim | IntelliJ |
|---|---|---|
| Move to left window | `<C-h>` | `<C-h>` (PrevSplitter) |
| Move to right window | `<C-l>` | `<C-l>` (NextSplitter) |
| Move to upper window | `<C-k>` | `<C-k>` |
| Move to lower window | `<C-j>` | `<C-j>` |
| Go back | — | `<C-o>` |
| Go forward | — | `<C-i>` |
| Beginning of line | `H` | `H` |
| End of line | `L` | `L` |
| Next paragraph | `J` | `J` |
| Previous paragraph | `K` | `K` |

## Panels & Tool Windows

| Action | Neovim | IntelliJ |
|---|---|---|
| Toggle file tree | `<C-e>` (Neo-tree) | `<C-e>` (Project) |
| Toggle terminal | toggleterm | `<C-t>` |
| Toggle git view | `<leader>gg` (lazygit) | `<leader>gg` (VCS tool window) |
| Return to editor | `<C-l>` from tree | `<Esc>` |

## Search (Telescope / IntelliJ)

| Action | Neovim | IntelliJ                        |
|---|---|---------------------------------|
| Find files | `<leader>sf` | `<leader>sf` (GotoFile)         |
| Live grep | `<leader>sg` | `<leader>sg` (FindInPath)       |
| Search everywhere | — | `<leader>sa` (SearchEverywhere) |
| Buffers | `<leader>sb` | —                               |
| Help tags | `<leader>sh` | —                               |
| Resume search | `<leader>sr` | —                               |
| Open picker | `<leader>so` | —                               |
| Treesitter | `<leader>st` | —                               |
| Diagnostics | `<leader>sd` | —                               |
| Goto class | — | `gc`                            |
| Goto symbol | — | `gs`                            |
| Text search | — | `gT`                            |

## LSP / Code Intelligence

| Action | Neovim | IntelliJ            |
|---|---|---------------------|
| Go to definition | `gd` | `gd`                |
| Go to type definition | — | `gD`                |
| Go to implementation | — | `gi`                |
| Quick implementations | — | `gI`                |
| Find references | `gr` | `gr` (ShowUsages)   |
| Find all usages | — | `gR` (FindUsages)   |
| Go to super method | — | `go`                |
| Code action | `<leader>ca` | `<leader>ca` / `g.` |
| Format | `<leader>cf` | `<leader>fc`        |
| Rename | `<leader>rn` | `<leader>rn`        |
| Show error | — | `<leader>se`        |
| Inspect code | — | `<leader>ic`        |
| Optimize imports | — | `<leader>oi`        |

## LSP Search (Telescope)

| Action | Neovim | IntelliJ |
|---|---|---|
| LSP definitions | `gd` | `gd` |
| LSP references | `gr` | `gr` |
| LSP implementations | `<leader>sli` | `gi` |
| LSP type definitions | `<leader>slt` | `gD` |
| Document symbols | `<leader>slsd` | — |
| Workspace symbols | `<leader>slsw` | — |

## Git

| Action | Neovim | IntelliJ |
|---|---|---|
| Toggle git view | lazygit (toggleterm) | `<leader>gg` (VCS window) |
| Git blame line | `<leader>gB` | — |
| Git diff this | `<leader>gd` | — |
| Git diff project | `<leader>gD` | — |
| Stage hunk | `<leader>gs` | — |
| Stage buffer | `<leader>gS` | — |
| Reset hunk | `<leader>gr` | — |
| Reset buffer | `<leader>gR` | — |
| Undo stage hunk | `<leader>gu` | — |
| Toggle blame | `<leader>gb` | — |
| Toggle deleted | `<leader>gq` | — |
| Preview hunk | `<leader>gP` | — |
| VCS groups | — | `<leader>v` |
| Git branches | `<leader>svb` | — |
| Git status | `<leader>svs` | — |
| Git stash | `<leader>svx` | — |
| Git commits | `<leader>svcw` | — |
| Git buffer commits | `<leader>svcb` | — |

## Buffers & Tabs

| Action | Neovim | IntelliJ |
|---|---|---|
| Next tab | — | `<Tab>` |
| Previous tab | — | `<C-Tab>` |
| Close buffer/tab | — | `<leader>xx` |
| Close all | — | `<leader>xa` |
| Close others | — | `<leader>xo` |
| Close unpinned | — | `<leader>xp` |
| Pin tab | — | `<leader>p` |
| Split horizontal | — | `<leader>sh` |
| Split vertical | — | `<leader>sl` |

## Run & Debug

| Action | Neovim | IntelliJ |
|---|---|---|
| Run context | — | `<leader>rc` |
| Run config | — | `<leader>rx` |
| Rerun | — | `<leader>rr` |
| Run tests | — | `<leader>rt` |
| Stop | — | `<leader>rs` |
| Debug context | `<leader>dc` (DAP continue) | `<leader>dc` |
| Debug config | — | `<leader>dx` |
| Txggle breakpoint | `<leader>db` | `<leader>db` |
| Edit breakpoint | — | `<leader>de` |
| View breakpoints | — | `<leader>dv` |
| Debug hover | `<leader>dh` | — |
| Terminate | `<leader>dq` | — |
| Restart | `<leader>dR` | — |

## Refactoring

| Action | Neovim | IntelliJ             |
|---|---|----------------------|
| Rename | `<leader>rn` | `<leader>rn`         |
| Refactor menu | — | `<leader>re`         |
| Unwrap | — | `<leader>uw`         |
| Surround with | — | `<leader>sw` (visual) |
| Safe delete | — | `<leader>cd`         |
| Generate | — | `<leader>cg`          |
| Go to test | — | `<leader>gt` / `gt`  |

## Hierarchy

| Action | Neovim | IntelliJ |
|---|---|---|
| Call hierarchy | — | `<leader>hc` |
| Method hierarchy | — | `<leader>hm` |
| Type hierarchy | — | `<leader>ht` |

## Menus (IntelliJ only)

| Action | IntelliJ |
|---|---|
| Main menu | `<leader>mm` |
| Analyze | `<leader>ma` |
| Build | `<leader>mb` |
| Code | `<leader>mc` |
| Find | `<leader>mf` |
| Go to | `<leader>mg` |
| Scope | `<leader>ms` |
| Tab popup | `<leader>mt` |
| Tool windows | `<leader>mw` |
| Goto action | `<leader>a` |

## AI (Neovim only)

| Action | Neovim |
|---|---|
| Toggle Copilot Chat | `<leader>aa` |
| Clear Copilot | `<leader>ax` |
| Copilot prompts | `<leader>ap` |
| Toggle Claude Code | `<leader>ac` |

## Multi-cursor (IntelliJ)

Uses the `vim-multiple-cursors` IdeaVim plugin (emulates `terryma/vim-multiple-cursors`).

### Basic workflow

1. Place cursor on a word and press `<C-n>` to select it
2. Press `<C-n>` again to select the next occurrence (adds a new cursor)
3. Keep pressing `<C-n>` to add more cursors at each next occurrence
4. Type your edit — it applies to all cursors simultaneously
5. Press `<Esc>` to exit multi-cursor mode

### Fine-tuning selections

- `<C-x>` — **skip** the current occurrence and jump to the next one (use when a match shouldn't be edited)
- `<C-p>` — **remove** the last added cursor / go back to the previous occurrence

### Select all at once

- `<leader><C-n>` — select **all whole-word occurrences** in the file at once (normal mode)
- `<leader>g<C-n>` — select **all occurrences** including partial matches (normal mode)
- `<leader>so` — select all occurrences via IntelliJ's `SelectAllOccurrences` action

### From visual mode

1. Visually select text first, then press `<C-n>` to find the next matching selection
2. `<C-x>` / `<C-p>` work the same way to skip or remove
3. `<leader><C-n>` / `<leader>g<C-n>` select all matches of the visual selection

### Partial match vs whole-word

- `<C-n>` / `<leader><C-n>` — **whole word** only (e.g. selecting `foo` won't match `foobar`)
- `g<C-n>` / `<leader>g<C-n>` — **partial match** (e.g. selecting `foo` will also match inside `foobar`)

| Action | Mode | Key |
|---|---|---|
| Select next whole-word occurrence | n / v | `<C-n>` |
| Select next partial occurrence | n / v | `g<C-n>` |
| Skip current occurrence | v | `<C-x>` |
| Remove last cursor | v | `<C-p>` |
| Select all whole-word occurrences | n / v | `<leader><C-n>` |
| Select all partial occurrences | n / v | `<leader>g<C-n>` |
| Select all occurrences (IDE) | n | `<leader>so` |

## Other

| Action | Neovim | IntelliJ   |
|---|---|------------|
| Comment line | — | `<leader>c` |
| Comment block | — | `<leader>C` |
| Show nav bar | — | `gn`       |
| Match bracket | — | `gm` / `%` |
| Sessions | `<leader>sp` (Persisted) | —          |
| Clear highlights | `<Esc>` | `<Esc>`   |
| Don't use Ex mode | — | `Q` → `gq` |