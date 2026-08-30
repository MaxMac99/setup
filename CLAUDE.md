# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Project Overview

NixOS + nix-darwin flake for the whole estate: four Linux hosts across two
physical sites and a public VPS, plus two Macs. It owns everything that must
exist **before** the Kubernetes cluster can — the mesh overlay, k3s itself,
sshd, sops, ZFS/NFS/Samba, and DNS.

The cluster's own workloads live in the **`homelab-k8s`** repo (Pulumi
TypeScript). The rule is:

> **NixOS provides only what must exist before the cluster exists.
> Everything else is Pulumi.**

⚠️ **`docs/multi-site-migration.md` is the source of truth**, not this file.
Read its **Status** table, **Decision log** and the current phase before
changing anything. It records what was measured, what was wrong, and why —
this file is only the short version.

## Commands

```bash
# Format — CI runs `nix fmt -- --check .` and it must pass
nix fmt -- --check .
nix fmt -- <path>

# Evaluate a host without building (works from the Mac, for Linux hosts)
nix eval .#nixosConfigurations.<host>.config.<option>

# Check assertions without a full build
nix eval --raw .#nixosConfigurations.<host>.config.assertions \
  --apply 'as: builtins.toJSON (builtins.map (a: a.message) (builtins.filter (a: !a.assertion) as))'
```

There are no tests. Validation is `nix eval` plus verification on the box.

⚠️ **Flakes only see git-tracked files.** A new file that is not at least
`git add -N`'d does not exist as far as `nix eval` is concerned, and the error
names the file rather than the cause.

## Worktrees (agent isolation)

Parallel/agent work happens in git worktrees, never by switching branches in the main
checkout. The layout is fixed:

```
setup/                              # main checkout (the daily IDE window)
└── .work/setup-<branch>/           # one worktree per workstream
```

- Create worktrees with `wt new setup <branch>`. Plain `git worktree add` is fine as
  long as the path and naming match.
- Never create worktrees outside `.work/`, and never name them `<branch>` alone.
- direnv auto-allows everything under `~/projects`; nix-direnv provides the
  environment on first `cd`. No `direnv allow`, no manual setup.
- List/clean up: `wt list setup` / `wt prune setup`.
- Full details of the convention: [docs/wt-workflow.md](docs/wt-workflow.md).

## Hosts, and how each one deploys

| Host | Site | Arch | Deploy source | Updated as |
|---|---|---|---|---|
| `ionos` | public (VPS) | amd64 | `/home/max/setup` | max |
| `brink-server` | brink | amd64 | `/etc/nixos` (git clone, owned by max) | max |
| `maxdata` | winkel | amd64 | `/home/max/setup` | max |
| `winkel-pi` | winkel | **arm64** | `/etc/nixos` (git clone, owned by max) | max |

On every host the **fetch runs as `max`** and only `nixos-rebuild` runs as root
— `sudo git` fails on brink-server and winkel-pi because root has no
`known_hosts`. ⚠️ `maxdata:/etc/nixos` is a **stale plain directory from Oct
2025** and is not its deploy source; editing it changes nothing.

```bash
# brink-server / winkel-pi
cd /etc/nixos
git fetch origin multi-site; echo "fetch exit=$?"   # ⚠️ check this
git reset --hard origin/multi-site
sudo nixos-rebuild switch --flake /etc/nixos#<host>
```

⚠️ **Never `git pull` on these clones.** `multi-site` has been rebased and
force-pushed before, leaving a clone on an orphaned commit that no ref
contained — invisible locally, and `pull` would *merge* the two histories
rather than fail. Repair and routine update are both
`git fetch && git reset --hard origin/multi-site`. Detect with
`git merge-base --is-ancestor HEAD origin/multi-site`.

⚠️ **A failed `git fetch` makes every later check lie.** It prints an error
that is easy to miss mid-script, and then `merge-base --is-ancestor` cheerfully
reports "fast-forward safe" against a *stale* ref, `reset --hard` resets to the
old commit, and `dry-activate` reports a no-op on a tree missing the change you
came to deploy. Check the exit status, then confirm the file you expect is
actually in the tree.

### ionos is different, and getting it wrong takes the host down

⚠️ **Never run `nixos-rebuild` — including `dry-build` — on ionos.** 1851 MB
RAM, no swap, `zramSwap` deliberately disabled, and `k3s-server` already
resident. It is the flake **evaluation** that is expensive, not the
derivations, so "it's only a config change" is not a safe exception: a
config-only change was `dry-build`-ed there and took sshd, k3s, nginx and
Headscale down, needing a panel power-cycle. Build elsewhere and activate
remotely:

```bash
# on maxdata, from /home/max/setup
nixos-rebuild switch --flake .#ionos --target-host max@100.64.0.1 --elevate=sudo
```

Recovery, if it does happen, is clean: `dry-build` never activates, so a
power-cycle returns to the previous generation.

## Architecture

Four nodes, **three L3 domains, two physical sites**, all addressed on a
WireGuard mesh overlay (Headscale on ionos, Tailscale clients). Both homes are
behind **CGNAT/DS-Lite**, so the overlay is the only path between sites and
ionos is the only rendezvous point.

- `hosts/nixos/<host>/` · `hosts/darwin/<host>/` — per-host config
- `modules/system/` — NixOS modules (k3s, overlay, DNS, sshd…)
- `modules/apps/`, `modules/profiles/` — mostly Mac-side
- `modules/data/network-config.nix` — **the address plan.** Sites, hosts,
  overlay, VIPs. Change addresses here, not inline.
- `secrets/` — sops-encrypted (`common.yaml`, `k3s.yaml`, `kubeconfig.yaml`)
- `docs/` — the migration doc and its ancestors

**Secrets** are sops-nix only (D11). Every host decrypts under its **own SSH
host key** (`/etc/ssh/ssh_host_ed25519_key`); there are no user-key recipients
left. 1Password holds human/family credentials and is the SSH agent — it is
deliberately outside the secret path.

## Traps that have each cost a real outage

These are the ones that present as something other than what they are. The
migration doc's decision log has the full accounting.

**DNS**

- ⚠️ **An AdGuard rewrite without `enabled = true` is migrated to
  `enabled: false`.** It lands in `AdGuardHome.yaml`, reads as completely
  correct, and does nothing.
- ⚠️ **`site-dns.nix` cannot be tested by hand-editing `AdGuardHome.yaml`.**
  `preStart` runs `yaml-merge <state> <store-config>` on *every* start, so the
  edit is reverted before AdGuard reads it. Merge semantics: recursive dict
  merge, **lists replaced wholesale** — so `filters`/`rewrites`/`upstream_dns`
  are authoritative from Nix while undeclared keys like `users` persist. An
  unknown key is dropped **silently**.
- ⚠️ **`systemd-resolved` never re-elects.** It picks a server, rotates on
  failure, and never rotates back for the life of the boot. `flush-caches` does
  *not* reset it; only a restart does. Any AdGuard restart is a trigger, so
  every deploy touching `site-dns.nix` is one — which is why
  `adguard-resolved-reelect` hangs off `adguardhome.service` rather than off
  `network-online.target`. **The fallback answers everything perfectly well**,
  so the host looks healthy while blocking and split-horizon are bypassed.
  ⚠️ Still uncovered: maxdata, which points at *winkel-pi's* AdGuard and has no
  local signal when that restarts.
- ⚠️ **The UDM SE answers any routed query to `:53`, for any destination, over
  TCP and UDP.** `dig @<anything>` from Brink tells you nothing — it once made
  an overlay-only resolver look like an open resolver. Test from inside the
  target site, or use a discriminator only the intended server can answer
  (`<node>.mesh.mvissing.de` resolves to an overlay address *only* via a
  resolver with the MagicDNS upstream).
- ⚠️ **The public zone is `*.mvissing.de CNAME mvissing.de`** — every name is a
  CNAME to the apex. A pass-through rewrite therefore returns the apex's public
  records and poisons them into every downstream cache. Names that must not do
  this need **explicit A/AAAA records**, not the wildcard.
- ⚠️ **Verify DNS from a client with a warm cache**, after resolving the names
  the host resolves anyway. `dig @<resolver>` proves what the resolver holds
  and nothing about what a client will use.

**Deploys and hosts**

- ⚠️ **`winkel-pi` runs NixOS 26.05 via `nixos-raspberrypi.lib.nixosSystem`**,
  not the fleet's 26.11 (D12). `nix flake update nixpkgs` does not move it.
- ⚠️ **Scripted networking on winkel-pi**: `nixos-rebuild switch`/`test` has
  twice cost a recovery there — once as total silence, once as an applied
  address with **no default route**, which looks healthy from the LAN while
  every outbound connection fails. `dry-activate` first; if a networking unit
  would restart, use `boot` + reboot to sidestep the live transition.
- ⚠️ **`__NIXOS_SET_ENVIRONMENT_DONE` hides new env vars from the shell that
  ran the rebuild.** A correct `environment.variables` change looks like it did
  nothing. Reconnect before concluding it failed.
- ⚠️ **`sops-install-secrets` is never cached** — it ships from the sops-nix
  flake, so every host compiles it and runs its test suite whenever the input
  moves. 20 minutes on ionos.
- ⚠️ **A host accepts overlay routes iff it advertises one**, and accepted
  routes land ahead of `main` in the rule table — so an accepted route covering
  the host's own subnet silently beats its LAN route. Only subnet routers may
  accept routes.

## Couplings to `homelab-k8s` that nothing here references

1. **Alloy → Loki.** `hosts/nixos/maxdata/monitoring.nix` ships logs to
   `networkConfig.lokiVIP`. Repin Loki in Pulumi without changing it here and
   **log shipping stops with no error**.
2. **`hosts/nixos/ionos/public-ingress.nix`** owns `:80` and `:443`, splitting
   by `Host` and SNI. **ACME renewal for every certificate in the cluster runs
   through it**, so breaking it breaks renewal ~30 days later, long after the
   change. Ports are duplicated in `infrastructure/traefik-public.ts` and
   nothing checks that they agree.
3. **Node zone labels** (`topology.kubernetes.io/zone`) are set here via k3s
   flags, and Pulumi schedules on them. ionos's label is `public` — it was
   `external` before the rebuild, so old selectors match nothing.
