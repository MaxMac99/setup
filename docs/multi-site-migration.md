# Multi-Site k3s Migration

Consolidate two physical sites plus a public VPS into a single k3s cluster over a
mesh overlay, remove the microVM layer on maxdata, and bring a new x86 node
(brink-server) online at Brink.

**Strategy:** spring-clean. Fresh cluster, no PV adoption. Preserve only
irreplaceable state via app-level dumps. Regenerate monitoring history, caches,
indexes and TLS certs (carefully, to avoid Let's Encrypt rate limits).

**Downtime:** unconstrained.

**Supersedes:** `docs/k3s-Migration.md` (single-site, pi-as-control-plane plan —
never executed). That document and `docs/proxmox/` are deleted in Phase 13.

---

## Status

One session per phase. Read this section first, update it last.

| # | Phase | State | Date | Notes |
|---|-------|-------|------|-------|
| 0 | Groundwork and inventory | ✅ done | 2026-08-05 | Router state captured; addresses verified on the wire |
| 1 | Backups | ✅ done | 2026-08-05 | Restore rehearsal passed (0 errors). UniFi `.unf` exported — confirm where it is stored |
| 2 | Overlay spike | ✅ done | 2026-08-05 | **Headscale + Tailscale** — see [`overlay-evaluation.md`](./overlay-evaluation.md). Direct over native IPv6, MTU 1280, p99 6.8 ms, zero relay fallback. Spike torn down; IONOS ports closed and spike DNS records deleted |
| 2b | Secret hygiene | ✅ done | 2026-08-06 | Rescoped then closed. 1Password is *not* the infrastructure vault (D11 revised); overlay keys go in sops-nix, which is all Phase 3 needed. SSH agent live. Remaining items moved to the phases that touch those hosts, one dropped — see 2b.3 |
| 3 | Overlay rollout | ✅ done | 2026-08-06 | **Headscale v0.29.3 on ionos**, dual-stack 443, LE cert via HTTP-01 (no DNS credential), embedded DERP region 999. Five nodes; both subnet routes approved and serving. **Unmodified client ↔ unmodified client verified both ways**; path **direct over native IPv6**, overlay MTU **1280 measured exactly** → flannel **1230**. ionos now on a **host** age key, proven across a cold boot. Survives reboot of the control server *and* of a client. Two design errors found and fixed the hard way — see 3.6. Open: 24 h sampling **waived** (3.5), GUI deferred to Phase 10 |
| 4 | DNS | ✅ done | 2026-08-06 | **AdGuard native on brink-server (`192.168.1.2`) and winkel-pi (`192.168.178.3`)**, one per site, from a shared `modules/system/site-dns.nix`. Split-horizon, MagicDNS forwarding, blocking and **failover all verified on the wire** at both sites. Nothing was restored from Phase 1 — the backup is a stock config (4.2). **Both routers cut over the same day** and real clients are on the new resolvers at both sites, over **both address families** — a Winkel client appears in the query log at `fd06:f10a:ebec:178:1806:…`, so per-client visibility survived (4.5). Three traps found the hard way — inert rewrites, a DNS-intercepting UDM SE, and clients preferring the RA-advertised IPv6 resolver, which is why each resolver has a **ULA** (4.4) |
| 5 | brink-server + pi relocation | ✅ done | 2026-08-06 | **5.1 and 5.2 are both done.** brink-server installed at Brink on `192.168.1.2` — root-on-ZFS (`main`, native mountpoints), UEFI, no failed units, sops host key enrolled, decrypt proven on the box. Pi **renamed `k3s-pi` → `winkel-pi`**, `hostId` `03030303` → `7a943cc4`, on static `192.168.178.3`, sops host key wired and **decrypt proven on the box** — all verified after a reboot. Both self-update from GitHub over read-only deploy keys. Nothing Phase-5-owned remained; its last open criterion was **Phase 4's** AdGuard, closed the same day. **Phase 6 is now the next step, and the first irreversible one** |
| 6 | maxdata microVMs out | ✅ done | 2026-08-06 | ⚠️ **The irreversible step is taken.** All three microVMs destroyed and `/var/lib/microvms` deleted — **67 G**, gone. sops decrypt of `k3s.yaml` under maxdata's **host** key re-proven on the box *immediately* before deletion (`cc44af01…`, exit 0), which was the one check whose failure could not be undone. Deployed `build → dry-activate → dead-man → test → verify → boot → reboot`; **dry-activate showed networkd would only be *reloaded*, never restarted**, so 6.5's bridge hazard never fired and `20-vmbr0.netdev` was left byte-identical on purpose. maxdata moved off the deprecated `dns.servers` onto `sites.winkel` — the last host at either site not using its own site resolver — and the whole single-site model was deleted with the microVMs. 6.2's k3s-server/k3s-agent refactor was **deliberately not done** (see 6.2); ARC **deliberately not raised** (6.3). One real defect found and fixed: **systemd-resolved never re-elects**, so maxdata silently answered from the FritzBox — bypassing blocking *and* split-horizon — on every boot; fixed and **verified across a cold boot** (see the decision log). **Phase 7 is now the next step** |
| 7 | Fresh cluster | ✅ done | 2026-08-07 | **All 4 nodes `Ready`** over the overlay — `INTERNAL-IP` is the 100.64.0.x address on every one, so D3 holds in practice. Three etcd servers across three L3 domains plus winkel-pi as agent. **`flannel.1` came up at exactly 1230 on all four**, the predicted 1280−50. Cross-site pod-to-pod verified with a **byte-exact 20 MB TCP transfer**, not just ping. 7.1 closed and re-verified with the cluster live. Token rotated and the `K3S_TOKEN=` double-wrap removed. ⚠️ **24 h etcd soak WAIVED** (as 3.5 was) — closed on a snapshot instead: `/healthz` ok, 3 members `Ready`, exactly **1** election event. Baseline for later drift is 1, not 0. Storage/local-path deliberately deferred to Phase 8. **Phase 8 is now next** |
| 8 | Storage and site affinity | 🚧 in progress | 2026-08-07 | **Code complete, foundation deployed.** MetalLB split into `brink-pool`/`winkel-pool` with zone-selected `L2Advertisement`s and **`autoAssign: false`** on both, so an unpinned service now sits visibly Pending instead of winning an address by allocation order. **local-path-provisioner deployed in Pulumi** (v0.0.37) with a per-node `nodePathMap` covering only maxdata and brink-server, and a **PVC bind proven end-to-end on maxdata**. Every LB IP pinned, every local-path workload pinned to a *node* rather than a site, MongoDB and in-cluster AdGuard deleted, Time Machine out of `default`. 8.2 extended beyond its table: **Authentik now survives the loss of maxdata** — CNPG scaled to 2 instances with zone anti-affinity, a dedicated Redis at Brink, pods and media on brink-server. ⚠️ Not sufficient alone: Brink has no ingress until Phase 9. Four traps found, all of which present as something else — see the decision log. Open: HA/Mosquitto data copy to Brink, the `tank/k8s/timemachine` 689 G move, UDM SE DHCP confirmation, and a PVC bind proven at Brink. `trustedInterfaces` **moved to Phase 12** (its consumers do not exist yet) |
| 9 | Ingress and certificates | not started | | |
| 10 | Workloads and bootstrap | not started | | |
| 11 | Backups that exist | not started | | |
| 12 | Monitoring | not started | | |
| 13 | Cleanup | not started | | |

## Decision log

Values later phases depend on. Fill in as they are measured, not assumed.

| Item | Value | Source |
|---|---|---|
| Overlay product | **Headscale + Tailscale** | Phase 2, 2026-08-05 |
| Secret mechanism | sops-nix for all infrastructure secrets; 1Password for human/family credentials and the SSH agent only (D11, revised) | Phase 2b, 2026-08-05 |
| Cross-site RTT / jitter | **p50 5.8 ms · p95 6.1 ms · p99 6.8 ms · jitter 0.45 ms**, both directions. 347 samples/direction over 5 h 55 min, zero loss, zero relay fallback. Relayed via ionos = 23–25 ms | Phase 2, 2026-08-05 → D4 |
| Overlay path (direct vs relayed) | **Direct**, over native IPv6. Asymmetric: brink→winkel over IPv6, winkel→brink over CGNAT IPv4 | Phase 2 |
| Overlay MTU → flannel MTU | overlay **1280** → flannel **1230** (VXLAN −50). ✅ **Re-measured on the production overlay 2026-08-06**, not just the spike: the cliff is exactly between 1280 and 1281 bytes total (`ping -M do -s 1252` passes, `1253` fails) against a 1500-byte same-LAN baseline | Phase 2 → D3, confirmed Phase 3 |
| **`ip_forward` on subnet routers** | ✅ **solved by the module, not by hand.** `services.tailscale.useRoutingFeatures = "server"`/`"both"` sets `net.ipv4.conf.all.forwarding` and `net.ipv6.conf.all.forwarding` itself. Phase 2's finding that "neither overlay sets it" is true of the *products* but not of the NixOS module | Phase 3, 2026-08-06 |
| IONOS Cloud firewall | **default-deny, only 22/80/443 inbound** — invisible from inside the VPS; the control plane needs an explicit opening | Phase 2, 2026-08-05 |
| Control-plane TLS | **mandatory** — plain HTTP on an alternate port wedges clients permanently after any control outage | Phase 2 |
| `ip_forward` on subnet routers | `0` on both pi and maxdata; neither overlay sets it — must be declared | Phase 2 |
| Cold start needs the control server | a host rebooting while ionos is unreachable loses the overlay entirely (both products) | Phase 2 → Phases 6, 7, 13 |
| UniFi OS Tailscale app | **no first-party app found** — §2.2/§3.2 premise looks wrong; third-party pkg only, **unverified** | Phase 2 |
| Brink DHCP range | `192.168.1.6-.199` — shrink from auto `.6-.254` | UDM SE, 2026-08-05 |
| Winkel DHCP range | `192.168.178.20-.200` — already clear, no change | FritzBox, 2026-08-05 |
| Overlay IPs per host | **ionos `100.64.0.1` · brink-server `100.64.0.2` · winkel-pi `100.64.0.3` · iphone `100.64.0.4` · maxdata `100.64.0.5`** — sequential allocation, recorded in `networkConfig.hosts.*.overlayIPv4`. These become `--node-ip` in Phase 7 (D3) | Phase 3, 2026-08-06 |
| **Headscale deployment** | **v0.29.3** on ionos, dual-stack `:443` (binds `[::]` despite logging `0.0.0.0`), gRPC on `:50443` (host-firewalled), embedded **DERP region 999** + STUN `udp/3478`, public DERP map disabled. TLS by Headscale's own ACME **HTTP-01** — no DNS credential, unlike Phase 2's manual DNS-01. Policy is a HuJSON file deployed from the store | Phase 3, 2026-08-06 |
| **Overlay route acceptance** | ⚠️ **A host accepts routes iff it advertises one.** Accepted routes land in table 52 at `ip rule` priority 5270, *ahead* of main at 32766, so an accepted route covering the host's own subnet silently beats its LAN route. Broke maxdata, silently displaced ionos's `wg0` path to Winkel — see 3.6.1 | Phase 3, 2026-08-06 |
| **IONOS Cloud firewall openings** | Only **UDP 3478** had to be added: 22/80/443 were already permitted, so Headscale on 443 with ACME on 80 needed no panel change. A firewalled port **times out** (~8 s); a rejected one fails in ~170 ms — useful for telling the cloud firewall apart from a local one | Phase 3, 2026-08-06 |
| **Site resolvers** | **brink-server `192.168.1.2` · winkel-pi `192.168.178.3`**, recorded in `networkConfig.sites.*.adguard`. `modules/system/site-dns.nix` **asserts** this equals the host's own `lanIPv4` — the routers' DHCP is configured from the former while AdGuard binds the latter, and nothing else would catch them drifting. AdGuard **0.107.78**, identical module in both nixpkgs despite 26.05 vs 26.11 (D12) | Phase 4, 2026-08-06 |
| **AdGuard rewrites need `enabled: true`** | ⚠️ **A rewrite that omits `enabled` is migrated to `enabled: false`.** The rules land in `AdGuardHome.yaml`, read as completely correct, and do nothing — every `*.mvissing.de` name still resolved publicly. Not documented in the NixOS module. Caught only because the resolver was queried directly before anything was pointed at it | Phase 4, 2026-08-06 |
| **`site-dns.nix` cannot be tested imperatively** | ⚠️ The module's `preStart` runs `yaml-merge <state> <store-config>` on **every** service start, so a hand-edit to `AdGuardHome.yaml` is reverted before AdGuard reads it. Two "tests" silently re-ran the original config before this was spotted. Valid technique: run a second AdGuard on its own ports and work directory. **Note `yaml-merge` is a recursive dict merge with lists replaced wholesale** — so undeclared keys like `users` persist, while `filters`/`rewrites`/`upstream_dns` are authoritative from Nix | Phase 4, 2026-08-06 |
| **MagicDNS answers despite `--accept-dns=false`** | ✅ `100.100.100.100` resolves node names even though no client accepts Tailscale DNS — the flag only stops tailscaled rewriting `/etc/resolv.conf`. So AdGuard forwards `mesh.mvissing.de` there with a dnsmasq-style domain upstream, and **overlay addresses are never duplicated into DNS config**; new nodes resolve with no config change. Verified `winkel-pi.mesh.mvissing.de → 100.64.0.3` | Phase 4, 2026-08-06 |
| **Split-horizon exclusions** | `*.mvissing.de` → the site's own `ingressVIP`, with **pass-through** rewrites (`answer: A` / `AAAA` = "keep the upstream's records") for `headscale.mvissing.de` and the MagicDNS zone. Two entries per name, since `A` preserves only A and `AAAA` only AAAA. ⚠️ **The Headscale exclusion is load-bearing**: the public zone has a wildcard onto ionos, so swallowing it would cost both sites the overlay — including the hosts serving DNS. The apex is *not* rewritten, because AdGuard's `*.x` wildcard excludes `x` itself | Phase 4, 2026-08-06 |
| **UDM SE intercepts DNS on routed traffic** | ⚠️ Queries **crossing** the UDM SE to port 53 are answered by it regardless of destination: `dig @192.168.178.99` and `@192.168.178.250` — addresses with no host at all — returned valid, ad-blocked answers, while same-subnet Brink addresses with no server timed out correctly. **Cross-site DNS testing from Brink is therefore meaningless**; it produced a false "winkel-pi is broken" reading when the pi was correct. Test from inside the site, or on the box | Phase 4, 2026-08-06 |
| **Clients prefer the RA-advertised IPv6 resolver** | ⚠️ **The DHCPv4 DNS setting alone does not redirect clients.** On the Brink Mac `nameserver[0]` was `2a00:6020:b444:bb00::1` — the UDM SE via RDNSS — with the DHCPv4 server only second, so `paperless.mvissing.de` still resolved to the dead public ingress. Both routers must advertise the resolver over IPv6 as well, which is what forced the ULA below | Phase 4, 2026-08-06 |
| **Resolver ULA** | **`fd06:f10a:ebec::/48`** — brink `…:1::/64`, resolver `…:1::2`; winkel `…:178::/64`, resolver `…:178::3`. Host part mirrors the IPv4 last octet. Random per RFC 4193 §3.2.2, and deliberately clear of **Tailscale's `fd7a:115c:a1e0::/48`** and of **`fda8:a1db:5685::/48`**, which ionos's `wg0` still carries. A ULA rather than an address in the delegated prefix because D2 forbids depending on the DG prefix — it changes unannounced, and the router would go on advertising the old address. ⚠️ **The FritzBox already advertises `fda8:a1db:5685::/64`** at Winkel (winkel-pi holds SLAAC addresses in it) — proof ULA advertisement works there, and a Phase 13 cleanup item | Phase 4, 2026-08-06 |
| **brink-server must ignore RA RDNSS** | `networkd` appended the UDM SE's own address to the link's DNS list, giving a third resolver present nowhere in this repo, which resolved may fail over to — bypassing blocking *and* split-horizon, intermittently. Fixed with `ipv6AcceptRAConfig.UseDNS = false`. winkel-pi is unaffected: `dhcpcd` is off and nothing writes RDNSS into `resolv.conf` | Phase 4, 2026-08-06 |
| **AdGuard rate limiting disabled** | Default is 20 q/s bucketed by `ratelimit_subnet_len_ipv4 = 24` — i.e. the **whole /24 shares one bucket**, not each client. On a site resolver that is a self-inflicted outage waiting for a busy evening; AdGuard's own guidance permits disabling it when the server is not internet-facing, which holds under CGNAT | Phase 4, 2026-08-06 |
| **DNS failover, measured** | AdGuard stopped → `example.com` still resolved in **37 ms** via the router (port unreachable gives immediate fallback, not a timeout). Blocking leaked (`doubleclick.net` → a real address) and split-horizon was lost, both as designed: **leaky, not absent**. Blocking returned immediately on restart | Phase 4, 2026-08-06 |
| **`network-setup.service` does not exist on winkel-pi** | ⚠️ 6.5 is version-drifted. NixOS 26.05 splits scripted networking into per-interface units: the pi has **`network-addresses-end0.service`** plus `networking-scripted.target`, and no `network-setup.service` at all. Same failure class, different unit name — and `nixos-rebuild boot` + reboot sidesteps the live transition entirely, which is how the ULA was applied there | Phase 4, 2026-08-06 |
| **`systemd-resolved` never re-elects its DNS server** | ⚠️ **The single most dangerous finding of this phase, because it is silent.** Measured on maxdata: `23:02:29.290` resolved switches to the global fallback (no link DNS yet) → `23:02:30.221` networkd configures `vmbr0` and hands it `[winkel-pi, FritzBox]` → `23:02:33.391` `vmbr0` **gains carrier, 3.2 s later**. resolved's first query to winkel-pi therefore cannot be answered, it rotates to the FritzBox, and **stays there for the life of the boot** — confirmed over six varied queries and a 60 s idle period. Nothing logs a complaint, and the FritzBox answers everything perfectly well, so the host looks healthy while `doubleclick.net` returns a real address and `*.mvissing.de` returns the **dead public ingress** instead of the site VIP. Blocking and split-horizon are both bypassed. `DNSSEC` was checked and ruled out (`no/unsupported`); reachability was ruled out (tcp/53 open, 2.4 ms when selected). Fixed with a `resolved-reelect-primary` oneshot ordered after `network-online.target`. ✅ **Verified across a cold boot, with no manual intervention** — `23:27:25.185` resolved starts → `23:27:30.260` carrier → `23:27:32.076` network-online → `23:27:32.101` the unit stops resolved → `23:27:32.113` it restarts and re-elects. Result: `Current DNS Server: 192.168.178.3`, `paperless.mvissing.de → 192.168.178.240` (the site VIP, not the dead public ingress), `doubleclick.net → 0.0.0.0`, and `winkel-pi.mesh.mvissing.de → 100.64.0.3` so MagicDNS forwarding survives the restart. ⚠️ **Only maxdata can hit this** — brink-server and winkel-pi *are* their sites' resolvers and point at themselves, so their primary is up as soon as their link is. Any future host pointing at a *remote* resolver with a fallback inherits it | Phase 6, 2026-08-06 |
| **maxdata deployment source** | ✅ **verified, not assumed.** Deploys from **`/home/max/setup`**, a git clone tracking `origin/multi-site` — the **ionos** pattern, *not* the `/etc/nixos` clone that brink-server and winkel-pi use. ⚠️ **`/etc/nixos` on maxdata is a stale plain directory from Oct 2025** and is not the deployment source; editing it would change nothing. `root` already has `safe.directory = /home/max/setup` in `/root/.gitconfig`, so the ionos `safe.directory` trap does not bite here — still undeclared in the config, though. Update with `git fetch && git reset --hard origin/multi-site`, never `pull` (5.2) | Phase 6, 2026-08-06 |
| **Disk reclaim is not immediate — snapshots hold the blocks** | Deleting `/var/lib/microvms` dropped `fast/root` **REFER 132 G → 65.1 G** at once, but pool `AVAIL` did **not** move: `USEDSNAP` is 268 G across **85** snapshots, and every snapshot older than the deletion still pins those blocks. Under sanoid's `production` template (`hourly 48, daily 30, monthly 6`) the bulk returns within 30 days and the tail out to 6 months. ⚠️ Two further traps: `df` immediately after `rm` still showed the **old** figure, because ZFS frees asynchronously — re-read it a minute later before concluding anything; and `zfs list` `USED` includes snapshots while `df` shows only `REFER`, so the two legitimately disagree by 268 G. No snapshots were destroyed to accelerate this: Phase 6 never touches the pools, and 402 G is free | Phase 6, 2026-08-06 |
| **`tank/k8s/timemachine` is shadowed by a directory** | ⚠️ **Pre-existing, not caused by Phase 6 — but it means the 689 G of Time Machine data is not where it looks.** The *dataset* `tank/k8s/timemachine` holds **96 K** and has **never been mounted**; the 689 G lives in a plain directory of the same path inside the parent `tank/k8s` (692 G REFER), which is what NFS actually exports. Cause is exactly D13's argument against `mountpoint=legacy`: the child has no `fileSystems` entry in `hardware-configuration.nix`, so NixOS never mounts it and the parent's directory silently wins. Same shape as `tank/fast-backup/{k8s,vms}`, also legacy and also unmounted. Consequence: the Time Machine data inherits `tank/k8s`'s properties and **cannot be snapshotted or replicated independently**. It *is* covered by the recursive `tank@pre-multi-site`, so Phase 1's protection holds. Phases 8/11 own the fix | Phase 6, 2026-08-06 |
| **ARC deliberately left at 8 GB** | 6.3 called for raising `zfs_arc_max` once the microVMs freed 18 GB. **Not done, by decision.** That 18 GB was a *fixed* reservation backing workloads that ran inside the guests, and the same workloads return as native pods from Phase 7 — spending it on ARC would only mean reclaiming it under memory pressure later, which ARC resists. It stays as k3s headroom: 8 GB ARC, ~23 GB for the OS and cluster. The three copies of the value (two in `default.nix`, one in `zfs.nix`) still agree; only the stale "18GB reserved for 3x 6GB microVMs" comment changed. **The exit criterion "ARC max raised and confirmed via `arc_summary`" is therefore withdrawn, not skipped** | Phase 6, 2026-08-06 |
| **microVM RAM actually reclaimed** | `available` went **3.4 GB → 28 GB** across the phase (32 GB box). This is the "18 GB" the exit criteria mean — **RAM, not disk**; the 67 G of `/var/lib/microvms` is a separate reclaim with separate mechanics (above). Do not conflate them | Phase 6, 2026-08-06 |
| **`KUBECONFIG` is unset on cluster nodes** | ⚠️ **Looks like a broken cluster, is a missing environment variable.** `kubectl` on a node falls back to its built-in default of `localhost:8080` and reports *"connection refused"* or *"current-context is not set"*. Every earlier session worked around it by exporting the path by hand (Phase 1.2 even bakes `export KUBECONFIG=…` into its instructions) without anyone declaring it. Fixed in `k3s-cluster.nix` via `environment.variables.KUBECONFIG`. ⚠️ **Servers only** — k3s writes `/etc/rancher/k3s/k3s.yaml` on servers and **not on agents**, so setting it fleet-wide would point winkel-pi at a nonexistent file, trading one confusing error for another. Verified live: three servers have it at mode **644**, winkel-pi has none — on the pi `kubectl` still fails with `localhost:8080 connection refused`, **correctly**, because `/etc/rancher/k3s/` does not exist there at all; run kubectl against a server instead. Note 644 means the file is world-readable cluster-admin credentials — inherited from `--write-kubeconfig-mode=644` and deliberately left alone, but worth revisiting if these hosts ever gain a second human user | Phase 8, 2026-08-07 |
| **`__NIXOS_SET_ENVIRONMENT_DONE` hides new env vars from the session that rebuilt** | ⚠️ **A correct `environment.variables` change looks like it did nothing.** `/etc/zshenv` sources `/etc/set-environment` only when this guard is unset, and it is **exported** — so every shell descended from a session that began *before* the rebuild inherits the guard, skips re-sourcing, and shows the old environment. Checking with `zsh -l -c 'echo $KUBECONFIG'` from inside the ssh session that ran `nixos-rebuild switch` returned empty while `/etc/set-environment` plainly contained the export. **Reconnect before concluding an env-var change failed** — a fresh ssh session showed it immediately. Same class as the AdGuard trap: the state you are inspecting is not the state you just wrote | Phase 8, 2026-08-07 |
| **A stale `~/.ssh/config` is deployment lag, not repo drift** | The Mac still offered `k3s-node1/2/3` aliases for the destroyed microVMs *after* Phase 6 removed them from `personal-ssh.nix`. The repo was correct; `~/.ssh/config` is a **home-manager symlink into a store path**, so it does not change until the Mac is rebuilt. Check `ls -la ~/.ssh/config` and compare the store path's date against the commit before concluding the config is wrong. Separately, **brink-server had no ssh alias at all** — built in Phase 5 without one while every other host had had one for months; added in Phase 8 | Phase 8, 2026-08-07 |
| **flannel MTU, confirmed on the real cluster** | ✅ **1230 on all four nodes**, exactly as predicted from `tailscale0`'s 1280 − 50. There is **no `--flannel-mtu` flag** in k3s v1.35.6; naming `--flannel-iface` is the only lever, and it works. Pod `eth0` is 1230 end-to-end and a **20 MB cross-site TCP transfer arrived byte-exact**. ⚠️ **Test with bulk TCP, never with ping**: D3's blackhole is TCP-with-DF stalling while ICMP succeeds, so a large ping passing proves only that fragmentation works. Also **busybox `ping` has no `-M do`** — the cliff test printed usage and exited 1, which reads like a failure and is not one | Phase 7, 2026-08-07 |
| **A failed `git fetch` makes the ancestry check lie** | ⚠️ **Nearly acted on a meaningless activation plan.** On brink-server `sudo git -C /etc/nixos fetch` failed with *Host key verification failed* (root's `.ssh` is empty; `/etc/nixos` is owned by **max**, and fetching as max works). `git fetch` printing an error is easy to miss mid-script — and the next two commands then compared against a **stale** `origin/multi-site`: `merge-base --is-ancestor` cheerfully said "fast-forward safe" and `reset --hard origin/multi-site` reset to the *old* commit. `dry-activate` then built a tree with no `k3s-cluster.nix` in it and reported nothing would change, which looks exactly like a safe no-op. **Check `git fetch`'s exit status explicitly before trusting any ref comparison**, and confirm the artefact you expect is actually in the tree | Phase 7, 2026-08-07 |
| **Deploy user differs per host** | maxdata and ionos: clone at `/home/max/setup`, updated as **max**. brink-server and winkel-pi: clone at `/etc/nixos`, **owned by max**, also updated as **max** — `sudo git` fails there for lack of a root `known_hosts`. So on every host the *fetch* runs as max and only `nixos-rebuild` runs as root. ⚠️ maxdata's `/etc/nixos` is a stale plain directory from Oct 2025 and is **not** its deploy source | Phase 7, 2026-08-07 |
| **A stale `kubernetes:kubeconfig` presents as a Helm chart error** | ⚠️ **The single most misleading finding of this phase.** `Pulumi.default.yaml` pinned `kubernetes:kubeconfig: ~/.kube/k3s-config`, a file deleted when the Mac moved to a sops-rendered `~/.kube/config`. The provider could not reach the cluster, so it fell back to a **default `kubeVersion` of v1.20.0** — and every chart then failed its own constraint with *"chart requires kubeVersion: >=1.29.0-0 which is incompatible with Kubernetes v1.20.0"*. That reads as a chart or cluster-version problem and is neither; the cluster is v1.35.6. ⚠️ `kubectl` worked perfectly throughout, because it uses `KUBECONFIG`/`~/.kube/config` and never sees the stack setting — so the two tools disagreed with no indication why. **Any `v1.20.0` in a pulumi-kubernetes error means "no cluster connection", not a version mismatch.** Fixed by `pulumi config rm kubernetes:kubeconfig`, letting the provider use normal resolution | Phase 8, 2026-08-07 |
| **Traefik chart renders only `service.spec`** | ⚠️ `templates/_service.tpl` emits `.Values.service.spec` verbatim and nothing else, so `service.type`, `service.ipFamilyPolicy` and `service.ipFamilies` are **silently discarded** — not rejected, because only the *root* of `values.schema.json` sets `additionalProperties: false`, and `service` does not. The chart's own default `service.spec.type: LoadBalancer` is what has been creating the Service all along. Consequence: the `ipFamilyPolicy: RequireDualStack` in `infrastructure/traefik.ts` was **never in effect** and never broke anything, contrary to first reading — but single-stack was never in effect either. Anything belonging in the Service spec must go under `service.spec`. Separately, `logs` was renamed to **`log` + `accessLog`** in 41.x, and *that* one fails the render outright because it sits at the root | Phase 8, 2026-08-07 |
| **pulumi-kubernetes replaces ConfigMaps, and a fixed name makes that fail** | ⚠️ Any change to a ConfigMap's `.data` is a **replacement**, not an update, and replacement is create-before-delete. With an explicit `metadata.name` the replacement collides with the object still present: *`configmaps "local-path-config" already exists`*. The replacement then cascades to dependents, so the Deployment failed the same way. Fix is to **omit `metadata.name`** and let Pulumi auto-name. That also repairs a quieter bug: with a fixed name the Deployment mounts the same name before and after, so a `nodePathMap` edit would change the ConfigMap **without restarting the provisioner**, which would go on serving the old paths | Phase 8, 2026-08-07 |
| **brink-server's `main/k8s` mounts at `/var/lib/k8s`, not `/main/k8s`** | ⚠️ Caught only by looking at the box. The pool `main` has `mountpoint=none` and every dataset carries an explicit path, so **`/main` does not exist at all**. `main/k8s` was already created and mounted (`mounted yes`, `canmount on`, empty, writable) — D13's native mountpoints working exactly as intended, and the precise opposite of `tank/k8s/timemachine`, which never mounted because `mountpoint=legacy` needs a `fileSystems` entry. A `nodePathMap` of `/main/k8s/local-path` would have left every Brink PVC Pending. ⚠️ **The shadowing hazard is not gone, only relocated**: `/var/lib/k8s` sits under `/var/lib` on `main/root`, so if the dataset ever fails to mount, local-path writes to the root dataset at that path and nothing complains — root fills while `zfs list` shows `main/k8s` at 96 K. `/fast/k8s` on maxdata has the same shape. Phase 12 should alert on *not mounted*, not on usage | Phase 8, 2026-08-07 |
| **MetalLB pools, and why `autoAssign` is off** | `brink-pool` `192.168.1.240-250` and `winkel-pool` `192.168.178.240-250`, each with an `L2Advertisement` selecting `topology.kubernetes.io/zone`. **No `public` pool** — ionos has no L2 segment to ARP on, and its `edge=true:NoSchedule` taint kept a speaker off it without any extra configuration. **`autoAssign: false` on both is deliberate**: a LoadBalancer with no explicit address then gets none and stays visibly Pending, rather than taking whatever is free. That is the exact failure this phase exists to end — the old cluster's Traefik held `192.168.178.10` by allocation order, not configuration, while six DNAT rules on ionos depended on it. Pins: traefik `.240` (= `sites.winkel.ingressVIP`, already what AdGuard resolves to), loki `.241`, timemachine `.242`, unifi `.243`, mosquitto **`192.168.1.241`** — moved to Brink with Home Assistant | Phase 8, 2026-08-07 |
| **local-path lives in Pulumi; the datasets do not** | Decided rather than assumed. The provisioner is a cluster workload nothing needs at boot, so the layering rule puts it in Pulumi — and changing a path must not require a `nixos-rebuild` on **brink-server**, the unattended box. The filesystem underneath stays with the host, but note this is *not* a NixOS declaration: D13 leaves data datasets to `zfs-mount.service`, so they are created with `zfs create` and appear in no config. `WaitForFirstConsumer` is load-bearing — it delays binding until the pod is scheduled, so the workload's `nodeSelector` picks the disk. `Retain` departs from upstream's `Delete` because these volumes have no replica. ⚠️ **ionos and winkel-pi are deliberately absent from `nodePathMap`**: a node with no entry fails provisioning loudly instead of writing to its root disk | Phase 8, 2026-08-07 |
| **Every local-path workload pins to a node, not a site** | Winkel has **two** nodes, so a zone selector still permits winkel-pi's USB-SATA boot disk. ⚠️ The rationale is narrower than it first appears: local-path stamps `nodeAffinity` onto the PV it creates, so a *bound* volume already prevents the pod moving — Kubernetes enforces that without help. What the pin actually controls is **which node gets the volume on first binding**, which on a greenfield cluster is every volume, and is permanent. `databases/postgresql.ts` also loses its "shared via virtiofs" claim, true only while every node was a microVM on maxdata | Phase 8, 2026-08-07 |
| **Authentik survives maxdata — locality, not replication** | Authentik gates forward auth for **every** ingress at both sites, so a single-instance Postgres plus a maxdata-pinned Redis made one site's outage a total authentication outage — including for Home Assistant running on brink-server metres away. Fixed by moving Authentik's dependencies to Brink rather than by replicating them: CNPG **`instances: 2`** with zone anti-affinity (two, not three — only maxdata and brink-server can hold a local-path volume at all; CNPG elects via the Kubernetes API, and etcd keeps quorum without maxdata), a **dedicated Redis at Brink** (Redis has no cross-site failover, so a second small instance beats replication; Paperless keeps the Winkel one), and pods plus media on brink-server. Two clusters per site were considered and rejected — Paperless and Grafana are pinned to maxdata and are down in that scenario anyway, so the split bought only ~6 ms. ⚠️ **NFS was the wrong answer** and worth recording: an NFS media volume would fail in exactly the scenario it was meant to survive, because maxdata *is* the NFS server. ⚠️ **Not sufficient alone** — Traefik is at Winkel and Brink's `192.168.1.240` serves nothing until Phase 9, so a Brink client still cannot reach any of it by name while maxdata is down | Phase 8, 2026-08-07 |
| **`tank` has 8.42 T free — do not confuse it with `fast`** | Phase 6 recorded "402 G free", which is **`fast`** (NVMe, now 444 G). `tank` is at 43 % with **8.42 T** available, so copying the 689 G of Time Machine data into the properly-mounted `tank/k8s/timemachine` is comfortably feasible — the reason to fix it rather than defer. ⚠️ And it is not cosmetic: the empty dataset already carries a **3 T quota** (`AVAIL 3.00T`), so the limit meant to bound a shared family backup target currently enforces nothing while the real data grows unbounded in the parent. Also reclaimable: `tank/fast-backup/{k8s,vms}` holds **917 G** for the destroyed microVMs, and `/fast/k8s/local-path-provisioner` still holds the old cluster's **124 G** — the new provisioner deliberately uses a fresh `/fast/k8s/local-path` so neither is disturbed before Phase 11 proves the backups | Phase 8, 2026-08-07 |
| **The Mac reaches brink-server directly from Winkel** | Phase 3's static routes work for unmodified clients as designed: `192.168.1.2:22` answers from a Winkel LAN address in ~9 ms, via winkel-pi as subnet router. ⚠️ This was nearly recorded as a blocker, because **maxdata cannot** SSH to brink-server — root has no `known_hosts` and the attempt fails with *Host key verification failed*, which looks like unreachability and is only missing trust. Check from the machine you are actually on before concluding a host is unreachable | Phase 8, 2026-08-07 |
| **`trustedInterfaces = ["vmbr0"]` moved to Phase 12** | `hosts/nixos/maxdata/networking.nix` deferred this to Phase 8 on the grounds that Phase 8 "wires NFS up against a real consumer". It does not: Paperless, Time Machine and Prometheus are all deployed in Phases 10/12, so removing the blanket trust now would be untestable — the situation Phase 6 deferred it to avoid. Established meanwhile: **Samba is safe** (`smb.nix` sets `openFirewall` for Samba and Avahi independently), **the exporters are not** (`node` 9100 and `smartctl` 9116 have no `openFirewall`; `zfs-prometheus-exporter` 9134 does), and **k3s is already covered** (`k3s-cluster.nix:157-159` opens 6443 on `lanInterface` explicitly, written for exactly this). ⚠️ Unsettled: Prometheus scrapes from a *pod*, so packets reach `192.168.178.2:9100` via `cni0`/`flannel.1`, not `vmbr0` — meaning the blanket trust may never have been what made scraping work, and adding the ports to `allowedTCPPorts` may not be sufficient either. Measure it once Prometheus exists | Phase 8, 2026-08-07 |
| **NFS exports need no widening** | Both exports stay `192.168.178.0/24`. Paperless and Time Machine are the only remaining consumers and both pin to maxdata, so the mount is node-local and the source address is `192.168.178.2`. Moving Home Assistant and Mosquitto to local-path removed the one case that would have needed the overlay in the export list — a Brink pod arrives from `100.64.0.2`. The Time Machine export path is unchanged by the dataset fix; only what is mounted there changes | Phase 8, 2026-08-07 |
| ionos → home RTT (existing wg0) | ~13 ms | Phase 0, `ping` from ionos |
| Winkel WAN IPv6 prefix | `2a00:6020:b481:e300::/56` — record only, never depend on it (D2) | FritzBox, 2026-08-05 |
| UDM SE static routes | present and configurable — Phase 3 unblocked | UDM SE, 2026-08-05 |
| FritzBox static routes | table present, empty, configurable | FritzBox, 2026-08-05 |
| Address availability | `192.168.178.3`, `.240-.250`, `192.168.1.2`, `192.168.1.240-.250` all free — verified on the wire | Phase 0, 2026-08-05 |
| **winkel-pi name and hostId** | **renamed from `k3s-pi` 2026-08-06**; `hostId` `03030303` → **`7a943cc4`**, ending the collision in form with the microVMs' number-derived IDs. Site-first, matching `brink-server`. Renamed with it: host dir, `rpiHosts` + flake attribute, `networkConfig.hosts` key, `.sops.yaml` anchor, ssh alias, deploy key (`id_winkel_pi`), and `k3s-pi-installer` → `rpi-installer` | Phase 5.2, 2026-08-06 |
| **winkel-pi age recipient** | `age1acjwunaejf345typ42284yxlreqqp39ndcfjqvcf8frsawwntf6sq3u23k`, from `/etc/ssh/ssh_host_ed25519_key` — **already a host key, and unchanged by the rename.** Re-deriving from the live key reproduced the existing `&k3s-pi` recipient exactly, so the "dead recipiency" was only missing wiring. 6th recipient of `common.yaml`; `k3s.yaml` needed no `updatekeys`. Decrypt proven on the box (`a342c743…`, matching the Mac) | Phase 5.2, 2026-08-06 |
| winkel-pi location | **Winkel**, static `192.168.178.3` since 2026-08-06 (was `.118` by DHCP). MAC `dc:a6:32:22:a2:a1`; verified across a clean reboot | Phase 5, 2026-08-06 |
| winkel-pi nixpkgs | **NixOS 26.05** via `nixos-raspberrypi`'s own nixpkgs, not the fleet's 26.11 (D12). `nix flake update nixpkgs` does not move it | Phase 5, 2026-08-06 |
| winkel-pi self-management | `/etc/nixos` is a git clone on `multi-site`, pulled over SSH with a read-only deploy key; `git pull && nixos-rebuild switch` runs on the pi. First rebuild after the rename needs the attribute spelled out (`#winkel-pi`), since the old one no longer exists | Phase 5, 2026-08-06 |
| **Self-updating clones vs rewritten history** | ⚠️ `multi-site` was rebased and force-pushed after the pi cloned it, leaving `/etc/nixos` on an **orphaned** commit no ref contained — invisible locally, and `git pull` would have *merged* the two histories rather than failing. Repair on a pull-only clone is `git fetch && git reset --hard origin/multi-site`, never `pull`. Detect with `git merge-base --is-ancestor HEAD origin/multi-site`. **brink-server checked and clean** — cloned after the rewrite, fast-forwards normally | Phase 5.2, 2026-08-06 |
| brink-server hardware | **installed and self-managing** — `git pull && nixos-rebuild switch` proven on the box; build from a clean clone is bit-identical to the running system | Phase 5.1, 2026-08-06 |
| brink-server config | **written and evaluating**, install in progress. `hostId = b21961a5`; ZFS pool **`main`**, single vdev, zstd, **native mountpoints + `zfsutil`** (D13); systemd-networkd; sops host key declared with zero secrets | Phase 5.1, 2026-08-06 |
| brink-server age recipient | `age1pqhavyh47c882zd3h20a8q0mng5kdm5qsz7d4f2vayrjfndcsyxq4m7d3a`, derived from `/etc/ssh/ssh_host_ed25519_key` — a **host** key (D11/2b.2). 5th recipient of `common.yaml`; decrypt proven on the box, plaintext hash unchanged. Deliberately *not* added to `k3s.yaml`: that token belongs to the cluster Phase 7 destroys. **Re-proven after winkel-pi's enrolment re-wrapped the data key** — same hash `a342c743…`, so all three recipients (Mac, brink-server, winkel-pi) verify against the re-keyed file | Phase 5.1, re-verified 2026-08-06 |
| brink-server NIC | `eno1`, MAC `84:a9:38:4c:9a:71` (altnames `enp0s31f6`, `enx84a9384c9a71`) | Phase 5.1, 2026-08-06 |
| Repo layout | **bare repo + worktrees** (`setup/.bare`, worktrees `main`/`multi-site`/`opencode`). `.git` is a 76-byte pointer file, so rsyncing a worktree to another machine breaks every git-based flake fetch — copy without `.git`, or clone properly | 2026-08-06 |
| brink-server NVMe | Samsung MZVLB1T0HBLR-000H1, 953.9 GiB, serial `S4GRNX0R315239`. Arrived with a Windows layout (499 M ESP / 128 M MSR / 943.7 G / 9.5 G recovery), zapped | Phase 5.1, 2026-08-06 |
| brink-server installer media | NixOS **26.05** minimal x86_64, on the Mac, SHA-256 matches published `7f5df09b…f870` | 2026-08-06 |
| Winkel reachable from off-site | **yes, verified** — `ssh -J max@212.132.82.102 max@192.168.178.{2,3}` returns `maxdata` / `winkel-pi` (`k3s-pi` before the rename); ionos `wg0` up at `.201`, 0% loss, ~14 ms. This jump is the only route into Winkel until Phase 3; neither ssh alias carries a `ProxyJump` | 2026-08-06 |
| maxdata networking stack | **systemd-networkd — confirmed live, question closed.** `systemd-networkd` active+enabled; `network-setup.service` and `dhcpcd.service` **do not exist as units at all**; `vmbr0` built from `20-vmbr0.netdev` + 3 `.network` files, `networkctl` routable/online. 6.5's scripted-networking claim was wrong, so its failure mode cannot occur on maxdata — Phase 6 must guard a networkd/bridge restart instead | Live check on the box, 2026-08-06 |
| **ionos deployment source** | ✅ **reconciled 2026-08-06.** `/home/max/setup` now tracks **`multi-site`**; upgraded `26.05.20260427` → **`26.11.20260802.6438090`** (gen 50, gen 49 kept as rollback), **verified across a reboot**. `/etc/nixos` is still a plain directory, unlike the pi/brink-server clone pattern. ⚠️ Requires `safe.directory` for root — set imperatively in `/root/.gitconfig`, **not yet declared in the config**, and invisible to `systemd-run` unless `HOME=/root` is passed | Phase 3.0.4, 2026-08-06 |
| **ionos build capacity** | ⚠️ **no remote builders; builds locally on a small VPS and cannot cope.** A full `nixos-rebuild build` starved sshd for 20+ min — ping and the TCP handshake still succeeded while no login could complete — and needed a panel power-cycle. Use `--max-jobs 1 --cores 1` under `tmux`, check `free -m`/`df -h` first. ⚠️ A `nix.buildMachines` remote builder **cannot** fix this: it needs ionos to dial out to the builder, and brink-server is behind CGNAT. Invert it — build on brink-server and push with `nixos-rebuild --flake …#ionos --target-host max@212.132.82.102 --use-remote-sudo`. ⚠️ **Qualified 2026-08-07: this applies to input-moving rebuilds, not to config-only ones.** The starvation happened during the **26.05 → 26.11 upgrade**, where `sops-install-secrets` compiled and ran its test suite. With nixpkgs unmoved, 7.1's firewall change `dry-build`-ed to **4 trivial derivations** and switched in seconds with 1.2 GB free. **Run `nixos-rebuild dry-build` first and let it decide** — assuming the expensive path cost a session's worth of avoidance for a change that did not need it. ⚠️ Also note the inversion is not currently *possible*: brink-server cannot SSH to ionos (`Permission denied (publickey)`; its only key is the GitHub deploy key `id_brink_server`), and granting access means a `.pub` in `modules/data/keys/` plus an ionos deploy — so it needs one ionos build to bootstrap regardless | Phase 3.0.5, 2026-08-06; qualified Phase 7.1, 2026-08-07 |
| **`sops-install-secrets` is never cached** | It ships from the sops-nix flake, not nixpkgs, so `cache.nixos.org` has no build: every host compiles it and runs its test suite whenever the input moves — 20 min on ionos. Fix fleet-wide with the `nix-community.cachix.org` substituter, or per-run via `--option extra-substituters` | Phase 3.0.5, 2026-08-06 |
| **ionos host age recipient** | ✅ **live source since 2026-08-06.** `age19ylfvg7p6zw67t7dkutrj4d0dg5wllnf8ltwjzdlttuu33wt69ssv0mxlm`, from `/etc/ssh/ssh_host_ed25519_key`. Enrolled additively first, then `age.sshKeyPaths` flipped and **verified across a cold boot** — `k3s_token` written at boot, `k3s.service` up. The old user-key recipient `age100thyt…` remains in `.sops.yaml` as a one-line rollback | Phase 3.0, 2026-08-06 |
| **maxdata host age recipient** | `age1ewxtypj7pkugz8vnf4pxtkgrnma8eg66p5shsq58kwdsku55vutsr2n2u7`, from `/etc/ssh/ssh_host_ed25519_key`. maxdata's **first sops block ever** — it had been a declared recipient consuming nothing since before Phase 0. Went straight to a host key because nothing consumed sops there, so no transition had to be staged. Decrypt of **both** files proven on the box before the config was written. **This is Phase 6.1's highest-risk item, done early and in isolation** | Phase 3, 2026-08-06 |
| **User-key age identities** | ✅ **none left.** ionos and maxdata were the last two; both now derive from `/etc/ssh/ssh_host_ed25519_key`, satisfying D11/2b.2 across the fleet | 2026-08-06 |
| ionos public ingress | 80/443 still DNAT'd to `192.168.178.10`, which is **dead** — ingress already broken, so 443 is free for the control server (3.0) | 2026-08-06 |
| FritzBox VPN peers | `192.168.178.201/32`, `.202`, … — FritzBox is the WireGuard *server* today | FritzBox, 2026-08-05 |
| Effective ionos↔home throughput | ~3 MB/s | Phase 0, scp over wg0 |
| Winkel MetalLB pool | `192.168.178.240-250` | Phase 0 address plan |
| Brink MetalLB pool | `192.168.1.240-250` | Phase 0 address plan |
| brink-server LAN IP | `192.168.1.2` | Phase 0 address plan |
| winkel-pi LAN IP (at Winkel) | `192.168.178.3` | Phase 0 address plan |

---

## Target topology

| Host           | Site       | Network              | Router | Role |
|----------------|------------|----------------------|--------|------|
| `brink-server` | **brink**  | `192.168.1.0/24`     | UDM SE | k3s **server** (etcd) · site DNS · subnet router · Home Assistant · user-facing workloads |
| `maxdata`      | **winkel** | `192.168.178.0/24`   | FritzBox | k3s **server** (etcd) · ZFS · NFS/SMB · Paperless · UniFi · Time Machine |
| `winkel-pi`    | **winkel** | `192.168.178.0/24`   | FritzBox | k3s **agent** · site DNS · subnet router · out-of-band anchor |
| `ionos`        | public     | fixed IPv4 + IPv6    | —      | k3s **server** (etcd) · overlay control server · public edge |

Decommissioned: `k3s-node1`, `k3s-node2`, `k3s-node3` (microVMs on maxdata).

**Site naming.** Sites are named after their street, since both are in Borken and
a role-based name (`home`, `dad`) would age badly the moment anyone moves:

| Key | Location | Was |
|-----|----------|-----|
| `brink` | Brinkstraße, Borken — own apartment | Site A |
| `winkel` | Nina-Winkel-Straße, Borken — parents' house | Site B |
| `public` | ionos VPS, no LAN | — |

These are the literal keys in `networkConfig.sites` and the values of
`topology.kubernetes.io/zone`. Note `brink` (the site) and `brink-server` (the
host at it) are different things — prose always spells out the host in full.

**Hardware**

- `brink-server` — Lenovo ThinkCentre M70q, i5-10500T, 32 GB DDR4, 1 TB NVMe (single disk, no redundancy)
- `maxdata` — AMD, 32 GB, ZFS `tank` (4× 4 TB RAIDZ1 + mirrored special/SLOG + L2ARC) and `fast` (NVMe)
- `winkel-pi` — Raspberry Pi 4, PoE+ HAT, USB-SATA boot disk (was `k3s-pi`)
- `ionos` — VPS, `212.132.82.102` / `2a02:2479:5c:a00::1`

**Facts that shape everything below**

- Both sites are on Deutsche Glasfaser DS-Lite: no usable public IPv4, CGNAT.
- The IPv6 /56 at each site is *not* reliably static. It normally survives a
  router reboot (stable DUID) but changes unannounced. Nothing may hardcode a
  site prefix.
- `ionos` is the only host with a fixed, reachable address. It is therefore the
  overlay rendezvous point and the public ingress.
- You are at Brink long-term. All smart-home devices are at Brink. Family
  (Michael, Anna) and the UniFi switches/APs are at Winkel.

---

## Layering rule

> **NixOS provides only what must exist before the cluster can exist.
> Everything else is Pulumi/k3s.**

| Layer | NixOS (this repo) | k3s / Pulumi (`homelab-k8s`) |
|---|---|---|
| Bootstrap | overlay client + subnet router per host; overlay control server on ionos; k3s itself; sshd; sops | — |
| Hardware-bound | ZFS pools, NFS server, Samba on maxdata | — |
| DNS resolver | **AdGuard native on brink-server + pi** | — |
| Overlay GUI | — | Headplane / NetBird dashboard (pod, talks to control server over its API) |
| Monitoring agents | node / ZFS / smartctl exporters | Prometheus, Grafana, Loki, Tempo, Alloy, alerting |
| Applications | — | all of them |

Two things are deliberately *not* in the cluster:

1. **The overlay control server and clients.** All three home hosts are behind
   CGNAT; the only path between them for pod-to-pod traffic is the overlay. Its
   control plane cannot depend on the thing it bootstraps.
2. **AdGuard.** Chosen to run natively so DNS survives cluster rebuilds. Routers
   keep DHCP and hand out the site's AdGuard as primary resolver, themselves as
   secondary — so a cluster outage makes ad-blocking leaky, not the house
   offline.

---

## Design decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| **D1** | Drop cluster dual-stack IPv6 | `--cluster-cidr=10.42.0.0/16,fd01::/48` / `--service-cidr=10.43.0.0/16,fd02::/112` (`modules/system/k3s-node.nix:123-124`) existed only as a DS-Lite workaround so ionos could reach home. The overlay replaces it. Native IPv6 remains as site-to-site transport and public termination at ionos. |
| **D2** | Never hardcode a site IPv6 prefix | DG /56 changes unannounced. Rendezvous is ionos's fixed address. Rules out hand-rolled site-to-site WireGuard with static endpoints. |
| **D3** | Node IPs and flannel ride the overlay | Four nodes across three L3 domains have exactly one mutually-routable address family. Generalises the existing `--flannel-iface=wg0` (`hosts/nixos/ionos/default.nix:122`). **MTU must be pinned explicitly** — VXLAN inside WireGuard inside a 1280-byte overlay; a wrong MTU blackholes large payloads while ping succeeds. |
| **D4** | Tune etcd for WAN: `heartbeat-interval=500`, `election-timeout=5000` — **confirmed by measurement** | Three members across two consumer uplinks plus a VPS. Defaults (100 ms heartbeat / 1000 ms election) cause spurious leader elections. Phase 2 measured p99 6.8 ms on the direct path and 23–25 ms relayed via ionos, so these values sit 73× and 735× above p99, and 14× above the worst single echo seen in six hours. Adopted as measured rather than assumed. Phase 7's "etcd stable 24 h, no leader elections" gate is the empirical test. |
| **D5** | One MetalLB L2 pool per site; every LB IP pinned | L2 mode requires a shared segment, which no longer holds. Today Traefik, `adguard-dns` and UniFi are unpinned and will drift on rebuild. UDM SE DHCP defaults to `.6–.254` and must be shrunk to free a pool. |
| **D6** | No cross-site replicated storage | Longhorn/Ceph over consumer uplinks is a reliability trap. Every `local-path` PVC gets an explicit site pin. `databases/postgresql.ts:291` (`// can run on any k3s node since /mnt/k8s-fast is shared via virtiofs`) becomes false the moment maxdata is a real node. |
| **D7** | hostNetwork Traefik on ionos | Today `iptables DNAT` + `MASQUERADE -o wg0` (`hosts/nixos/ionos/default.nix:63-77`) hides every public client IP from Traefik. |
| **D8** | cert-manager DNS-01 via IONOS webhook | Domain stays at IONOS (`ns*.ui-dns.*`). Needs the community `cert-manager-webhook-ionos` rather than a built-in solver. Removes the inbound-port-80-per-hostname dependency and enables a wildcard, cutting issuance volume. Note `CLAUDE.md:51` already falsely claims DNS-01; the code is HTTP-01 (`infrastructure/cert-manager.ts:72-80`). |
| **D9** | AdGuard native on brink-server + pi | Per above. Overlay DNS layered on top for node names. Split-horizon for `*.mvissing.de`. |
| **D10** | Pi lives at Winkel | Brink already has an always-on x86 node. Winkel's only machine is the unattended one — with the pi there, a `nixos-rebuild` on maxdata does not simultaneously kill Winkel's DNS, subnet router and your only route in. Cost: Brink becomes single-node for site infra. |
| **D11** | sops-nix is the single mechanism for infrastructure secrets. 1Password holds human and family credentials, and is the SSH agent — it is deliberately *outside* the secret path | **Revised 2026-08-05.** Originally "1Password is the vault; sops-nix stays the on-host delivery." The offline rule that motivated the split — *if a host needs a secret before the network is up, it must decrypt offline* — turned out to exclude every boot-critical secret from 1Password anyway, leaving one laptop token as the sole candidate for opnix. That does not justify a flake input, a service account and a token file per host. sops-nix already does this offline, in git, with per-host scoping. See Phase 2b.1 for the full reasoning, including why host age identities can never live in the vault. |
| **D12** | The pi is built with `nixos-raspberrypi.lib.nixosSystem`, and so tracks *that* flake's nixpkgs rather than the fleet's | **Added 2026-08-06.** The pi's configuration did not evaluate at all: nixos-raspberrypi's kernel overlay and nixpkgs' own `hardware/device-tree.nix` are version-coupled, and building the host from our nixpkgs while injecting their overlays fails with `attribute 'buildDTBs' missing`. Updating the input does not help — latest `main` fails identically. Their `lib.nixosSystem` is the documented drop-in that defaults to the matching nixpkgs. Consequence: the pi runs NixOS 26.05 while the fleet runs 26.11, and `nix flake update nixpkgs` does not move it — only the `nixos-raspberrypi` input does. `lib` must travel with it, because it passes through `specialArgs` where it overrides the module system's own and a foreign `lib` recurses through `_module.args`. See `flake.nix` `rpiHosts`. |
| **D13** | brink-server's single ZFS pool is named **`main`**, uses **native mountpoints** (`-o zfsutil`) rather than `mountpoint=legacy`, and compresses with **zstd** | **Added 2026-08-06, revised the same day during the install.** The first draft named the pool `fast` to match maxdata, arguing it made `/fast/k8s/local-path-provisioner` mean the same thing on both k3s servers. That argument was too strong — local-path's `nodePathMap` is per-node, so the paths never had to match — and `fast` only earns its name on maxdata by contrast with `tank`. On a single-pool box it says nothing, so `main`. **The mountpoint half matters more.** `mountpoint=legacy` makes NixOS the only thing able to mount a dataset, so every dataset created later needs a matching `fileSystems` entry or it silently never mounts — which is exactly how maxdata acquired the SMB datasets that Phase 0.1 found "appear nowhere in `hardware-configuration.nix`". Native mountpoints make `zfs list` authoritative and reduce relocating a dataset to `zfs set mountpoint=`, with no rebuild. Cost: NixOS must mount with `-o zfsutil`, because plain `mount -t zfs` refuses any dataset whose mountpoint is not `legacy`. Only boot-critical datasets are declared; data datasets are left to `zfs-mount.service` on purpose. Compression: zstd gives materially better ratios at negligible CPU cost on a 10th-gen i5, and one unmirrored disk makes capacity worth more than the last few percent of throughput. Replication is unaffected — compression is per-dataset and re-applied on receive. |
| **D14** | brink-server uses **systemd-networkd**, not scripted networking | **Added 2026-08-06.** On a scripted-networking host `nixos-rebuild test`/`switch` stops `dhcpcd` — deleting every address and route — without starting `network-setup.service`, leaving the interface bare. That cost two recoveries on the pi (6.5), once as total silence and once, worse, as an applied address with **no default route**: LAN-reachable and apparently healthy while every outbound connection failed. brink-server is Brink's subnet router and primary DNS; it is precisely the host that must not be losable to a routine rebuild. networkd also handles RAs itself, so it needs no `accept_ra=2` sysctl to keep IPv6 once Phase 3 turns on forwarding. |

---

## Phase overview

**Phases 0–5 are additive and reversible. The first irreversible step is Phase 6.**

| # | Phase | Reversible | Gate |
|---|-------|-----------|------|
| 0 | Groundwork and inventory | read-only | address plan written, both repos tagged |
| 1 | Backups | additive | Postgres restore rehearsed |
| 2 | Overlay spike: Headscale vs NetBird | throwaway | comparison doc + decision |
| 2b | Secret hygiene | additive | ✅ secret policy settled (D11); overlay keys go in sops-nix |
| 3 | Overlay rollout and site-to-site | additive | unmodified client ↔ unmodified client, both directions |
| 4 | DNS | additive | both sites resolve via local AdGuard, failover verified |
| 5 | brink-server bring-up + pi relocation | additive | Winkel reachable without maxdata |
| 6 | **maxdata: microVMs out** | ⚠️ **irreversible — taken 2026-08-06** | ✅ maxdata reachable, ZFS intact, 18 GB RAM reclaimed (ARC deliberately not raised) |
| 7 | Fresh cluster | ✅ done 2026-08-07 | ✅ 4 nodes Ready, full-MTU cross-site verified; 24 h etcd soak waived |
| 8 | Storage and site affinity | 🚧 in progress 2026-08-07 | every PVC pinned, every LB IP pinned — **plus** a provisioner that can serve them, and Authentik off maxdata |
| 9 | Ingress and certificates | — | wildcard issued, real client IPs in logs |
| 10 | Workloads and bootstrap | — | all apps up, HA re-commissioned, UniFi re-adopted |
| 11 | Backups that actually exist | — | restore tested from a real backup |
| 12 | Monitoring | — | dead-man's switch fires on simulated outage |
| 13 | Cleanup | — | docs match reality |

---

# Phase 0 — Groundwork and inventory

**Read-only. No changes to any host.**

## 0.1 Capture live state

Neither repo records the following. Run on `maxdata` and save the output into
`docs/inventory-pre-multi-site.md` (gitignored or committed, your call).

```sh
# Pool topology, health, capacity
zpool status -v
zpool list -o name,size,alloc,free,frag,cap,health

# Dataset occupancy — especially the imperatively-created SMB datasets that
# appear nowhere in hardware-configuration.nix
zfs list -o name,used,avail,refer,mountpoint,compression -r tank fast

# Are the timemachine-* datasets actually in use? They are created by
# setup-smb-datasets.sh:13-24 but shared nowhere in smb.nix.
zfs list -o name,used tank/timemachine-max tank/timemachine-michael

# What is actually in the local-path store?
sudo du -sh /fast/k8s/local-path-provisioner/* | sort -h

# Existing snapshots
zfs list -t snapshot -o name,used,creation -s creation | tail -50
```

From any host with cluster access:

```sh
# The three unpinned LoadBalancers — capture what MetalLB assigned, because a
# rebuild will not reproduce it
kubectl get svc -A -o wide | grep LoadBalancer

# Current node inventory before tear-down
kubectl get nodes -o wide --show-labels

# PVC inventory with storage class and node binding
kubectl get pvc -A -o custom-columns=\
NS:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName,SIZE:.spec.resources.requests.storage
```

From the routers:

- **UDM SE** — current DHCP range (default `192.168.1.6–192.168.1.254`), static
  reservations, whether static routes are configurable in the UI.
- **FritzBox** — current DHCP range, static reservations, static route support,
  MyFRITZ! name, current WAN IPv6 prefix (record it, do not depend on it).

## 0.2 Multi-site address plan

`modules/data/network-config.nix` is single-site by construction — flat
`gateway`, `subnet`, `dns`, and a single `staticIPs` map. It needs a site
dimension. Proposed shape:

```nix
options.networkConfig = {
  sites = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule { options = {
      subnet          = ...;   # "192.168.1.0/24"
      gateway         = ...;   # "192.168.1.1"
      dnsServers      = ...;   # [ <site adguard> <router> ]
      metallbPool     = ...;   # "192.168.1.240-192.168.1.250"
      dhcpRange       = ...;   # documentation only, enforced on the router
    };});
  };
  hosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule { options = {
      site      = ...;   # "a" | "b" | "public"
      lanIPv4   = ...;   # static LAN address
      overlayIP = ...;   # assigned by the overlay control server
    };});
  };
};
```

Final allocation, reconciled against the live router config on 2026-08-05:

| Site | Subnet | Gateway | DHCP | MetalLB pool | AdGuard |
|------|--------|---------|------|--------------|---------|
| brink | `192.168.1.0/24` | `.1` | `.6–.199` — **shrink** from auto `.6–.254` | `.240–.250` | brink-server, `.2` |
| winkel | `192.168.178.0/24` | `.1` | `.20–.200` — **no change needed** | `.240–.250` | pi, `.3` |

Two notes from that reconciliation:

- **The FritzBox needs no DHCP change.** Its pool already stops at `.200`, so
  `.240–.250` is clear, `.2/.3/.5/.6/.7` are clear, and ionos's `wg0` address
  `.201` sits just outside. Only the UDM SE has to move, because its "auto" range
  claims everything up to `.254`.
- **Latent one-address conflict at winkel today:** the current MetalLB pool is
  `.10–.20` and the DHCP pool starts at `.20`. They overlap on exactly one
  address. Nothing has collided yet, but it is another argument for D5's move to
  `.240–.250`.

Keeping the UDM SE's DHCP *start* at `.6` rather than moving it to `.100` is
deliberate: existing leases in `.6–.99` survive (the laptop is at `.93`), and the
static space `.2–.5` is still free for brink-server.

Static host addresses:

| Host | LAN IPv4 |
|------|----------|
| brink-server | `192.168.1.2` |
| maxdata | `192.168.178.2` (unchanged) |
| winkel-pi | `192.168.178.3` |

Overlay addresses are assigned by the control server in Phase 3 and recorded
back into `networkConfig.hosts.*.overlayIP`.

**Note:** Winkel's MetalLB pool moves from the current `192.168.178.10–20` to
`.240–.250`. That is a deliberate change to keep the two sites symmetric and to
get the pool out of the way of the old static assignments. Every pinned LB IP
changes with it (see Phase 8).

## 0.3 Promote the undeclared ingress VIP

`192.168.178.10` is hardcoded in six iptables rules
(`hosts/nixos/ionos/default.nix:64-73`) and declared nowhere in either repo. It
is a MetalLB-assigned LoadBalancer IP for Traefik that nothing reserves. Promote
it into `networkConfig` now so the Phase 9 rewrite has a single source of truth,
even though D7 replaces the DNAT path entirely.

## 0.4 Tag both repos

```sh
cd ~/projects/private/setup/multi-site && git tag pre-multi-site
cd ~/projects/private/homelab-k8s/main  && git tag pre-multi-site
pulumi stack export > ~/backup/pulumi-stack-pre-multi-site.json
```

## 0.5 Fix sops drift

`.sops.yaml:10-17` declares four recipients for `secrets/common.yaml`
(macbook, kopf3-NB-26, maxdata, ionos) but the file has only three `enc:`
blocks. **ionos cannot decrypt `common.yaml` today.**

```sh
sops updatekeys secrets/common.yaml
```

Also note for later phases:

- `k3s-pi` is still a recipient of `secrets/k3s.yaml` (`.sops.yaml:27`) despite
  having no sops config since commit `adfcc70`. It regains one in Phase 5.
  ⚠️ **Resolved 2026-08-06, and this framing was wrong.** Calling it "dead"
  implied stale key material. Re-deriving from the live host key reproduced the
  recipient exactly: the key was always right and only the host-side `sops`
  block was missing. Fixed by the rename to `winkel-pi` — see 5.2 item 8.
- `ionos` derives its age key from a **user** SSH key,
  `/home/max/.ssh/id_ed25519` (`hosts/nixos/ionos/default.nix:131`), while the
  microVMs correctly use a host key. Standardise on host keys in Phase 7.

## 0.6 Exit criteria

- [x] `docs/inventory-pre-multi-site.md` written with all 0.1 output
- [x] Address plan agreed; `modules/data/network-config.nix` refactored to
      `sites` + `hosts`, legacy options kept and marked deprecated so the
      microVMs and maxdata keep evaluating until Phase 6
- [x] Ingress VIP promoted into `networkConfig.legacy.{ingressVIP,ingressVIPv6,lokiVIP}`
      and wired into ionos's 12 DNAT rules and maxdata's Alloy config.
      Rendered output verified byte-identical — zero behaviour change
- [x] `pre-multi-site` tagged in both repos (local only — not pushed);
      `pulumi stack export` → 302 resources, 17 MB
- [x] `sops updatekeys -y secrets/common.yaml` run; ionos added as the 4th
      recipient; plaintext verified identical to `HEAD`
- [ ] **Router state** — the two DHCP ranges and static-route capability. Needs
      the UDM SE and FritzBox web UIs; see `inventory-pre-multi-site.md` §5

## 0.7 What the inventory changed

Full detail in [`inventory-pre-multi-site.md`](./inventory-pre-multi-site.md).
The load-bearing surprises:

1. **The cluster is degraded right now.** `k3s-node3` has been `NotReady` since
   2026-08-05 04:16 while remaining a voting etcd member — quorum is 2 of 3, so
   one more failure loses the cluster. Authentik, Grafana, Homepage,
   matter-server and gotenberg are all `Pending`. This *raises* the urgency of
   Phases 6–7 rather than lowering it.
2. **`tank/timemachine-max` / `-michael` do not exist.** The Phase 0 open item is
   closed: nothing to preserve, nothing to delete.
3. **Time Machine is 689 G and has exactly one client — your Mac.** Anna and
   Michael have never backed up. The "Winkel Macs back up at LAN speed"
   assumption in Open Items is currently vacuous; every byte of Time Machine
   traffic is the cross-WAN case.
4. **The whole NFS tier is under 4 G** (Paperless media is 3.4 G, not the 300 G
   its PVC requests). Off-box backup of it is trivial — Phase 11 gets cheaper.
5. **48 of the 57 G under `local-path` is Prometheus**, already classed as
   disposable. The irreplaceable local-path set is under 3 G.
6. **Traefik holding `192.168.178.10` is luck, not configuration** — first-come
   assignment from the `.10–.20` pool, which is exactly why D5 pins everything.
7. **69 G of dead Proxmox zvols** under `tank/fast-backup/vms`, plus 13 690
   unpruned snapshots on `tank/fast-backup/k8s`. Both go in Phases 11/13.
8. **`kubectl exec` must be run from the node hosting the pod.** The
   apiserver→kubelet proxy on this cluster returns 502 across nodes and silently
   truncates exec streams — it corrupted the first backup attempt.

---

# Phase 1 — Backups

Scope is reduced from the original plan: **Home Assistant config, Matter fabric
credentials and Mosquitto state are explicitly discarded.** Both HA instances
(native on the pi, and the in-cluster one) are being destroyed and replaced with
a fresh install on brink-server. Smart-home devices will be re-commissioned at Brink.

Executed 2026-08-05. Manifest with sizes and contents:
[`inventory-pre-multi-site.md`](./inventory-pre-multi-site.md) §4.
Artefacts in `~/backup/pre-multi-site/` and `/tank/backups/pre-multi-site/`.

## 1.1 The real backup is the ZFS snapshot

```sh
zfs snapshot -r tank@pre-multi-site      # all 22 datasets
zfs snapshot -r fast/k8s@pre-multi-site  # every local-path PV
```

Together these capture every PV, both tiers, atomically — and Phase 6 never
touches the pools, so this alone is sufficient protection for the migration
itself. Everything below is the *off-box* copy of the small irreplaceable subset,
which protects against pool loss instead.

The recursive `tank` snapshot matters more than it looks: `tank/daten-familie`
(1.46 T, the only SMB share with data in it) has **neither sanoid nor syncoid
coverage** (`hosts/nixos/maxdata/zfs.nix:28-39`). It is the least-protected data
on the machine. Phase 11 fixes that permanently.

All tarballs were cut from the snapshot (`/fast/k8s/.zfs/snapshot/...`), not from
live directories, so they are point-in-time consistent.

## 1.2 Postgres — dump per database, from the pod's own node

⚠️ **`pg_dumpall` does not work on this cluster.** A whole-cluster dump truncated
silently at 338 MB, mid-record inside `homeassistant` and before `paperless` was
reached, while `kubectl` still exited 0. Cause: the apiserver→kubelet exec stream
drops (see 0.7 item 8).

What works:

```sh
# from the node hosting postgres-1 — NOT from another node
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl -n database exec postgres-1 -c postgres -- \
  pg_dumpall -U postgres --globals-only | gzip > /tmp/pg-globals.sql.gz
for db in authentik paperless grafana app; do
  kubectl -n database exec postgres-1 -c postgres -- \
    pg_dump -U postgres -d "$db" --create | gzip > "/tmp/pg-$db.sql.gz"
done
```

Verify with `gzip -dc … | grep -c 'PostgreSQL database.*dump complete'`. Note
PG 18 emits a trailing `\unrestrict <token>` line *after* the completion marker,
so a "last line" check gives a false negative.

`homeassistant` (2834 MB — 20× everything else combined) was **deliberately not
dumped**: it is recorder history, HA is being rebuilt from scratch, and it is what
broke the combined dump. It remains inside `fast/k8s@pre-multi-site`.

## 1.3 The "six manual bootstrap secrets" are not lost

⚠️ **Correction to the original plan.** They do not "exist only because someone
typed them into a UI". All sixteen Pulumi config secrets — including
`authentikOutpostToken`, both OAuth client ID/secret pairs and
`unpoller-password` — live in `homelab-k8s/Pulumi.default.yaml`, which is
**tracked in git** and encrypted with `PULUMI_CONFIG_PASSPHRASE`, itself stored
in sops at `personal/pulumi-passphrase`. All sixteen were decrypted successfully
on 2026-08-05.

So the real requirement is narrower: **keep the Pulumi passphrase safe.** It is
in sops with four recipients. Items 1–3 remain chicken-and-egg only in the sense
that Authentik must be running before they can be *re-created* if ever lost —
Phase 10 covers that ordering.

Genuinely outside both git and sops, and now backed up:

- Mosquitto `password.txt` — `nfs-mosquitto.tar.gz`
- ntfy `auth.db` — `localpath-ntfy-storage.tar.gz`
- `AdGuardHome.yaml` (admin hash, custom rules, clients) — `localpath-adguard-data.tar.gz`

Also captured, and not in the original plan: the **ACME account keys**
(`acme-account-keys.yaml`). Reusing them on the rebuild preserves the Let's
Encrypt account and its rate-limit standing.

## 1.4 Exit criteria

- [x] Postgres dumps taken per database and verified complete
      (authentik 19 M, paperless 3.2 M, grafana 357 K, globals, app)
- [x] cert-manager TLS secrets exported (10) plus both ACME account keys
- [x] Off-box tarballs of the irreplaceable local-path and NFS data
- [x] Bootstrap secrets verified recoverable (all 16 decrypt)
- [x] Recursive snapshots taken on both pools
- [ ] **UniFi `.unf` export** via the controller UI (`apps/unifi.ts:290-294`).
      The raw `unifi-data` + `unifi-mongo` tarballs exist, but `.unf` is the
      supported restore path for re-adoption
- [x] **Restore rehearsal passed** (2026-08-05). All four dumps loaded into a
      scratch `postgres:18` container with **zero errors**, and the content is
      real, not just schema:

      | Database | Restored content |
      |---|---|
      | `authentik` | 7 users · 3 groups · 6 applications · 6 providers · 215 tables |
      | `paperless` | 730 documents · 9 tags · 40 correspondents |
      | `grafana` | 26 dashboards · 3 datasources |
      | `app` | empty, as expected |

      Rehearsal command:
      ```sh
      docker run -d --name pg-rehearsal -e POSTGRES_PASSWORD=x postgres:18
      gzip -dc pg-globals.sql.gz | docker exec -i pg-rehearsal psql -U postgres
      gzip -dc pg-authentik.sql.gz | docker exec -i pg-rehearsal psql -U postgres
      ```
      Role-already-exists notices from the globals load are expected and benign.

---

# Phase 2 — Overlay spike: Headscale vs NetBird

Time-boxed evaluation on throwaway state. Both deployed to ionos; one client per
site. Nothing existing is touched.

## 2.1 Known input, not a verdict

The pinned nixpkgs (`753cc8a`) has a full `services.netbird.server` stack —
`management.nix`, `signal.nix`, `dashboard.nix`, `coturn.nix`, optional nginx.
It is more mature than first assumed. However `netbird/server.md` states:

> To fully setup Netbird as a self-hosted server, we need both a Coturn server
> **and an identity provider**

and `oidcConfigEndpoint` is a required option (`netbird/management.nix:213`).
The only OIDC provider in this estate is **Authentik, which runs inside the k3s
cluster** — whose networking depends on the overlay. Choosing NetBird therefore
requires a second, native IdP on ionos purely to bootstrap the VPN: another
always-on service outside git, to secure and monitor.

That is a real cost, not a disqualification. Carry it into the scoring.

## 2.2 Scoring criteria

| Criterion | Why it decides this | Measurement |
|---|---|---|
| Direct site-to-site path over native IPv6 | If traffic relays via ionos, every cross-site etcd heartbeat detours through the VPS | `tailscale status` / NetBird peer state: direct vs relay |
| Cross-site RTT and jitter | Feeds D4 etcd tuning | Sampled `ping` across the overlay, both directions, with the direct/relay path recorded per sample. Ran 5 h 55 min — see 2.4 for why that was enough |
| Subnet routing to unmodified clients | Hard requirement, both directions | Ping a Winkel printer from a Brink laptop with nothing installed |
| Behaviour when the control server is down | Do established peer links survive? | Stop the control server; observe for 1 h |
| Declarative in Nix + git | Headscale ACLs are a HuJSON file; NetBird's live in a DB behind the dashboard | Inspection |
| Bootstrap dependencies | Per 2.1 | Count of extra always-on services |
| k3s integration | Tailscale has `--vpn-auth`; NetBird needs manual `--node-ip`/`--flannel-iface`/MTU | Inspection |
| GUI | "I want a GUI where I see the connection setup" | Headplane (third-party) vs NetBird dashboard (first-party) |
| Re-enrolment / key rotation | Rebuild ergonomics | Destroy and rejoin a node |
| **Runs on UniFi OS?** | Would let the UDM SE be its own subnet router, removing both the missing-static-route problem and brink-server as a cross-site SPOF (see 3.2) | Install the UniFi OS Tailscale app; check whether it accepts a self-hosted control server URL. NetBird has no UniFi OS integration |

## 2.3 Fallback

If both fail the direct-path or subnet-routing criteria, the fallback is plain
WireGuard site-to-site with a hub on ionos — not the other product, since both
use the same underlying NAT-traversal approach.

## 2.4 Exit criteria

- [x] `docs/overlay-evaluation.md` written with measurements for both — both
      products fully deployed on ionos and measured end-to-end, 2026-08-05
- [x] Decision recorded with rationale — **Headscale + Tailscale**. Data plane
      was a tie; decided on relay fallback, bootstrap cost, git-managed policy
      and firewall surface
- [x] **Measured cross-site RTT recorded for D4** — p50 5.8 ms / p95 6.1 ms /
      p99 6.8 ms, jitter 0.45 ms, both directions. 347 samples per direction
      over 5 h 55 min, **zero packet loss and zero relay fallback**. D4's
      `heartbeat=500` / `election=5000` adopted as measured

      **The window was cut from 24 h to 6 h deliberately.** What the remaining
      eighteen hours could have added is diurnal variation and a longer
      baseline for flap frequency, and both belong on the production overlay
      rather than on throwaway state: Phase 3's exit criteria already require
      the path to be characterised and RTT recorded, and Phase 12 adds
      permanent cross-site blackbox probes for latency, loss and
      direct-vs-relay. Phase 7's "etcd stable 24 h, no leader elections" gate
      remains the empirical test of D4. Revisit only if Phase 3 or 12 shows
      relay flapping this window did not — with 347/347 direct and no loss,
      that is not the expected outcome. See `overlay-evaluation.md` §3.2.

---

# Phase 2b — Secret hygiene ✅

Numbered `2b` rather than renumbering everything downstream. It sat here because
Phase 3 is where the first *new* secrets get created (overlay auth keys), and the
policy had to be settled before that.

⚠️ **Rescoped 2026-08-05, closed 2026-08-06.** This phase was "Secret management
with 1Password" and assumed 1Password would become the source of truth for
infrastructure secrets, delivered to hosts by `opnix`. Working through it, that
plan did not survive its own rationale — see 2b.1.

**The phase closes because its actual purpose is served:** the policy question is
settled (D11, revised), and the one deliverable that had to exist before Phase 3
— knowing where overlay auth keys go — is answered: **sops-nix**. What remained
on the work list was not gated on Phase 3 at all, so it moved to the phases that
actually touch those hosts rather than blocking here. See 2b.3 for the
disposition of every item, including the one that was dropped outright.

## 2b.1 Why 1Password is not the vault for infrastructure secrets

The original argument was that 1Password is "the right vault" and only the
*delivery* was in question. Both halves turned out to be weaker than assumed.

**opnix buys nothing here.** It authenticates with a service-account token at
`/etc/opnix-token` and fetches over the network from 1password.com. sops-nix
decrypts a file already in the repo with a key already on disk — offline, no
network, no external service. D11 already excludes every boot-critical secret
from opnix, because a host that cannot reach the internet cannot fetch the key
that brings up its own network, which is exactly what Phases 6 and 7 create.
Once boot-critical secrets are excluded, the only remaining candidate in this
estate was `kopf3/github-token` on a laptop. A flake input, a service account
and a token file to manage one non-critical token is not a good trade.

**The service account only existed to feed opnix.** Dropping opnix drops it.
Nothing else needed it: 1Password for human use requires only a normal login.

**Importing every host age identity is close to busywork.** A host identity is
disposable — reinstall, generate a fresh one, add it to `.sops.yaml`,
`sops updatekeys` from a surviving recipient. Only *one* recipient has to
survive. Backing up all eight adds eight copies of highly sensitive material to
defend, to buy convenience that is rarely used. What actually cannot be
recovered by re-keying is plaintext that exists nowhere else — see the Pulumi
passphrase in 2b.3.

**`programs._1password` does not exist on darwin.** Both `_1password.nix` and
`_1password-gui.nix` live in `nixos/modules/programs/` and are implemented with
`security.wrappers` (setgid), `users.groups.onepassword-cli.gid` and polkit.
The original work item 1 was not implementable as written.

**The SSH-agent collision was overstated.** Both Macs already use a standalone
`age.keyFile` (`Maxs-MacBook-Pro/default.nix:48`, `work.nix:15`); they do not
derive at runtime. `ssh-to-age` is run once by hand when onboarding a machine.
So the agent breaks nothing operationally — the only casualty was the onboarding
instruction in `README.md`.

**What survives unchanged is the offline rule**, which is D11's real content:

> **If a host needs a secret before the network is up, it must decrypt offline.**

## 2b.2 Where each secret lives

| Secret | Home | Why |
|---|---|---|
| k3s token | **sops-nix** | Needed at every `k3s.service` start. |
| Overlay pre-auth / node keys | **sops-nix** | Needed to bring up the network itself. |
| WireGuard keys (until Phase 13) | **sops-nix** | Currently unmanaged files under `/home/max/.wireguard/`. |
| Every other host secret | **sops-nix** | It already works, offline, in git, with per-host scoping. Moving it into a networked vault is lateral. |
| SSH client keys (human) | **1Password** | Done — see 2b.4. The agent never exposes private material, which is why the sops key is excluded from it. |
| WiFi, router admin, recovery keys, LE account, IONOS panel | **1Password** | Managed nowhere today. This is where the vault earns its place. |
| `maxPassword` / `michaelPassword` / `annaPassword` (SMB) | **1Password** | Genuinely shared with Michael and Anna. |
| The Macs' `~/.config/sops/age/keys.txt` | **1Password** (copy) | These are the surviving recipients everything else can be re-keyed from. Host identities are *not* backed up — see 2b.1. |

## 2b.3 Disposition of the work items

None of the remaining items were gated on Phase 3, so each moved to the phase
that already touches that host — doing them here would have meant rebuilding
ionos and maxdata twice. One was dropped outright.

| # | Item | Disposition |
|---|---|---|
| 1 | Wire maxdata's sops config | **→ Phase 6.1**, which already opens with it |
| 2 | ionos age key: user → host key | **→ Phase 3**, which rebuilds ionos anyway |
| 3 | ionos WireGuard keys → sops | **dropped** — see below |
| 4 | Resolve Pulumi | **→ Open items** — not boot-critical, not a migration blocker |
| 5 | Dead recipiency (`k3s-pi`) | ✅ **done in Phase 5.2** (2026-08-06) — and it was never dead, only unwired; see 5.2 item 8 |
| 6 | 1Password as personal tooling | **→ Open items** — an ongoing human task, not a gate |
| — | SSH client keys → 1Password agent | **done**, see 2b.4 |

**Item 3 is dropped, not deferred.** Phase 13 deletes the FritzBox WireGuard
server outright — ionos's `wg0` peer block *and* the key files at
`/home/max/.wireguard/`. Building declarative sops plumbing for key material
that is scheduled for deletion is churn, and it means editing the config of the
tunnel that is currently the only route into Winkel, for no lasting gain.

The genuine risk it addressed was narrow: if ionos's disk died before Phase 13,
those two unmanaged files would be unrecoverable and the tunnel unrebuildable.
Phase 3 closes that by giving Winkel a second, independent path. Until then the
cheap mitigation is to **copy `private_key` and `preshared_key` into 1Password**
— a human action, no plumbing — recorded in Phase 13 item 1.

**Item 1 keeps its warning, it just lives in Phase 6.1 now.** maxdata is a
declared recipient of both `common.yaml` and `k3s.yaml` (`.sops.yaml:16,22`) but
has no `sops` block in any module and consumes nothing. Verified 2026-08-05:
maxdata's existing `/home/max/.ssh/id_ed25519` derives `age1s44mfk…`, which *is*
the `&maxdata` recipient — the key material is already correct and only the
wiring is missing. That makes Phase 6.1 a config change rather than a key
ceremony, but it must still be proven by an actual decrypt on the box.

## 2b.4 Done — SSH client keys (2026-08-05)

Client-side SSH moved to the 1Password agent. The private keys are no longer on
disk on the Macs.

| 1Password item | Grants |
|---|---|
| `id_max_admin` | user `max` on every NixOS host in the flake |
| `id_github` / `id_kopf3_github` | GitHub personal / Kopf3 |
| `id_hetzner` | Hetzner Storage Box |

Points worth carrying forward:

- **Keys are split by trust domain, not by destination host.** All keys share one
  vault on one laptop behind one unlock, so per-host keys would fall together
  anyway; the split that pays is personal-GitHub vs work-GitHub vs backup
  provider vs own machines.
- **A vault key belongs to a person, not a device.** The vault syncs everywhere,
  so `maxs-macbook-pro.pub` was renamed to `modules/data/keys/max-admin.pub`.
  Machine-to-machine keys (`maxdata.pub`) stay device-bound and keep their
  hostname, because a headless host cannot talk to a vault agent. This is also
  why host age identities can never come from 1Password.
- **`~/.ssh/id_sops_age`** (was `id_ed25519`) is the sops age source, not an SSH
  key. It authenticates to nothing and must stay a plain file.
- **`IdentityAgent` must be quoted.** The socket path contains a space; unquoted,
  ssh aborts the *entire* config file with `extra arguments at end of line`.
- maxdata's import of `personal-ssh.nix` was dropped —
  `programs.ssh.enable` was false there, so it rendered nothing. Verified as a
  no-op: identical `nixos-system-maxdata` derivation before and after.

## 2b.5 Exit criteria

- [x] **Secret policy settled** — D11 revised. sops-nix is the single mechanism
      for infrastructure secrets; 1Password is human/family credentials and the
      SSH agent, deliberately outside the secret path
- [x] **Where overlay auth keys go is answered: sops-nix.** This was the only
      thing Phase 3 actually needed from this phase
- [x] **Documented which secrets are offline-decryptable and which are not** —
      2b.2. Everything a host needs at boot decrypts offline; nothing in the boot
      path depends on reaching a network service. The Phase 6 and 7 runbooks
      depend on this and it now holds by construction
- [x] 1Password SSH agent live on the Macs; `ssh-to-age` unaffected because the
      sops key was never in the agent
- [x] Every remaining work item explicitly disposed of — moved or dropped, none
      silently abandoned (2b.3)

Deliberately **not** exit criteria for this phase, with their new homes:

| Was | Now |
|---|---|
| maxdata decrypts `k3s.yaml` with its own key | Phase 6.1 exit criteria |
| ionos derives its age key from a host key | Phase 3 exit criteria |
| ionos rebuildable from the flake alone | Phase 13 (item 3 dropped; see 2b.3) |
| Pulumi secrets provider resolved | Open items |

---

# Phase 3 — Overlay rollout and site-to-site

Runs **alongside** the existing FritzBox↔ionos WireGuard tunnel. Nothing is torn
down until Phase 13.

**Nothing from Phase 2 survives in Nix.** The spike was deliberately throwaway
(`systemd-run` units, `/var/lib/*-spike`) and is fully torn down. Phase 3 writes
the real modules from scratch. The only tailscale in the repo is
`modules/apps/tailscale.nix`, imported solely by the work laptop for a
*different*, commercial tailnet — unrelated, and no help here.

1. Control server on ionos, behind its own TLS (its own hostname under
   `mvissing.de`). See 3.0 — it should take **443** directly.
2. Clients on maxdata, pi, brink-server, laptop, phone. Auth keys in sops-nix
   (Phase 2b).
3. Subnet routers — **final assignment directly**, see 3.1:
   - **brink-server** `192.168.1.2` advertises `192.168.1.0/24`
   - **pi** `192.168.178.3` advertises `192.168.178.0/24`
   Approve both routes on the control server.
4. **`net.ipv4.ip_forward` declared on both subnet routers.** Phase 2 found it
   `0` on maxdata and the pi, and neither overlay sets it. Subnet routing fails
   silently without it; the spike only worked because it was set by hand.
5. Static routes on both routers — this is what makes unmodified clients
   reachable. Both tables confirmed present and configurable (Phase 0).

   | Router | Its own LAN | Destination (the *remote* subnet) | Next hop (must be on its own LAN) |
   |---|---|---|---|
   | **UDM SE** (brink) | `192.168.1.0/24` | `192.168.178.0/24` → winkel | brink-server `192.168.1.2` |
   | **FritzBox** (winkel) | `192.168.178.0/24` | `192.168.1.0/24` → brink | pi `192.168.178.3` |

   ⚠️ **The next hop is always the local subnet router, never the remote one.**
   A router can only hand a packet to an address it can already reach directly,
   so the UDM SE cannot point at anything in `192.168.178.0/24` — reaching that
   network is the entire purpose of the route. This paragraph previously had the
   two next hops swapped (UDM SE → `192.168.178.2`, FritzBox → `192.168.1.90`),
   which could not have worked; corrected 2026-08-06.
6. ACL policy committed to git.
7. Overlay addresses recorded into `networkConfig.hosts.*.overlayIPv4` — the
   option exists and is unset for every host.
8. GUI — **deferred, see 3.4.**

## 3.0 Prerequisites the original plan did not list

Four things must be true before any of the above, and none were visible when
this phase was written. **3.0.4 is the one that gates the others**, because
every remaining item in this phase ends in a `nixos-rebuild` on ionos.

**Reachability.** Phase 2 opened TCP 8443 and UDP 3478 on the IONOS Cloud
firewall and they were closed again at teardown. That firewall is default-deny
and **invisible from inside the VPS** — blocked packets never reach `ens6`, so
the host firewall and `tcpdump` both show nothing. Reopening is a panel action.

Which ports is now an easier question than it looks. Verified 2026-08-06:

```
-A PREROUTING -i ens6 -p tcp --dport 443 -j DNAT --to-destination 192.168.178.10:443
  → 192.168.178.10 does not respond
```

ionos's 80/443 DNAT still points at the MetalLB VIP Traefik used to hold, and
**that target is dead — public ingress is already broken.** So 443 and 80 are
effectively free, and Headscale should take **443 directly** rather than another
high port. That also avoids the Phase 2 failure mode where a control server on a
non-standard port let Tailscale's "forcing port 443 dial" heuristic wedge a
client permanently (2.1). It pulls part of D7 forward into this phase at no
cost, because nothing working is being displaced.

**TLS renewal.** Phase 2 issued its certificate by *manual* DNS-01 — a TXT
record pasted by hand. That is not viable for 90-day renewal on the service the
whole network depends on. With port 80 free, **HTTP-01 becomes possible and
needs no API credential**, which is the cheap path. The alternative is an IONOS
DNS API token, which Phase 9 (D8) needs anyway for the wildcard.

**ionos's age key.** Inherited from Phase 2b item 2: `age.sshKeyPaths` points at
`/home/max/.ssh/id_ed25519` (`hosts/nixos/ionos/default.nix:131`) instead of a
host key. ionos is rebuilt in this phase regardless, so it is done here.
Additive order, never a flag day: derive the host-key recipient → add it to
`.sops.yaml` *alongside* the existing one → `sops updatekeys` both files → flip
`age.sshKeyPaths` → `nixos-rebuild test` with a dead-man reboot armed → verify
`k3s_token` still decrypts and k3s stays up → `switch` → only then drop the old
recipient and `updatekeys` again.

🔄 **The additive half is done (2026-08-06, `49fa463`).** `age19ylfvg7p…`,
derived from ionos's `/etc/ssh/ssh_host_ed25519_key`, is enrolled in
`.sops.yaml` alongside `&ionos` and both files were re-keyed with their
plaintexts unchanged. Proven on the box: ionos decrypts **both** `common.yaml`
(`a342c743…`) and `k3s.yaml` (`cc44af01…`) with the host key it will switch to.

✅ **Unblocked 2026-08-06.** 3.0.4 is resolved — ionos now tracks `multi-site`,
so the re-keyed files and the `&ionos-host` recipient are present on the box.
The 26.11 upgrade confirmed the current path still works end to end:
`sops-install-secrets` imported `/home/max/.ssh/id_ed25519` as
`age100thyt…` and wrote `k3s_token` **at boot**.

What remains is a one-line change plus its verification: point
`age.sshKeyPaths` at `/etc/ssh/ssh_host_ed25519_key`, rebuild, and confirm
`k3s_token` is still written **after a reboot** — activation alone does not
test the boot path, which is the whole risk. Both keys are enrolled, so a
failure is recoverable by reverting one line rather than by re-keying.

### 3.0.4 ionos is on a different branch, three months behind ✅

✅ **Resolved the same day.** ionos was reconciled onto `multi-site` and upgraded
to `26.11.20260802.6438090` (generation 50), **verified across a reboot**:
`/run/booted-system` equals `/run/current-system`, `k3s_token` was written at
boot rather than only at activation, `wg0` re-established with a live handshake,
Winkel reachable through it, zero failed units. Generation 49 remains as
rollback. The fleet is now uniform on `26.11.20260802.6438090` except the pi,
which tracks nixos-raspberrypi's nixpkgs by design (D12).

The risk was smaller than this section first assumed, and the reasons are worth
keeping — they generalise:

- **ionos is a k3s _agent_**, `role = lib.mkForce "agent"`, `serverAddr =
  https://192.168.178.5:6443`. It holds **no etcd**, so no quorum exposure.
- **It was the straggler, not the outlier.** The microVMs already ran
  `26.11.20260802` / k3s **v1.35.6**; ionos ran k3s **v1.35.2**. The upgrade
  *converged* an existing skew rather than creating one.
- **Its config diff across the branches is cosmetic** — hardcoded IPs replaced
  by `networkConfig.legacy.ingressVIP`, which Phase 0.6 already verified renders
  byte-identical.

⚠️ **What actually went wrong was resource exhaustion, not configuration.**
See 3.0.5 — that is the finding with consequences for the rest of this phase.

⚠️ **Discovered 2026-08-06, and it reshapes this phase.** Every other host in
the fleet tracks `multi-site`. ionos does not, and never has.

| | ionos | pi / brink-server |
|---|---|---|
| Deploy source | `/home/max/setup`, a clone on **`main`** at `e97d2b6` | `/etc/nixos` on `multi-site` |
| `/etc/nixos` | a plain directory, not a repo | a real clone |
| Running system | `nixos-system-ionos-**26.05.20260427**.1c3fe55` | 26.05 (pi) / 26.11 (brink-server), both current |
| Last generation | **49, dated 2026-05-10** — the only one on the box | days old |
| Remote builders | none; it builds locally | same |

Two consequences:

1. **There is no such thing as a small rebuild of ionos right now.** The
   `multi-site` flake pins nixpkgs `26.11.20260802`; ionos runs `26.05.20260427`
   with a matching `flake.lock`. Any `nixos-rebuild switch` from this branch is a
   **release upgrade plus three months of churn**, applied to the k3s server,
   the public edge, and the WireGuard tunnel that is currently the only route
   into Winkel. Headscale cannot be deployed without paying that cost.
2. **Secrets have diverged by branch.** The `&ionos-host` enrolment and both
   re-keyed files live on `multi-site`. On `main` they are the pre-re-key
   versions with no host-key recipient — so flipping `age.sshKeyPaths` while
   deploying from `main` breaks `k3s_token` at boot, which is the exact failure
   the additive order exists to avoid.

**This is Phase 3's first task, not a side quest**, since step 1 of the phase is
a control server on ionos. Decide deliberately:

- **Reconcile ionos onto `multi-site` first**, as its own scoped change with a
  dead-man reboot armed and the IONOS console open. Pays the upgrade once,
  before anything depends on it, and while a known-good generation 49 exists to
  roll back to. Preferred — but it is a real upgrade and should be treated as
  one, not smuggled in under "deploy Headscale".
- Or **stage on `main`**: apply the additive sops enrolment there too, flip the
  key, and only then converge the branches. Smaller blast radius per step, at
  the cost of the same edit existing on two branches.

Either way, **verify after a reboot**, not after `test` — the boot path is what
`k3s_token` decryption actually depends on.

### 3.0.5 ionos cannot build its own closures — this phase must plan around it

⚠️ **Learned the hard way, 2026-08-06.** ionos has **no remote builders**
(`builders =` is empty in `/etc/nix/nix.conf`) and builds everything locally on
a small VPS. Starting a full `nixos-rebuild build` on it drove the box into
resource starvation: ping kept answering and TCP 22 kept completing its
handshake, but **sshd could not finish a banner exchange for over twenty
minutes**. It had to be power-cycled from the IONOS panel.

Two things made that recoverable, and both are worth relying on deliberately:

- `nixos-rebuild build` **activates nothing**. Through the whole incident ionos
  stayed on generation 49 with its original k3s and tunnel. A hard reboot was
  therefore safe — there was nothing half-applied to roll back.
- The partial download survives in the store, so the retry was fast.

**The trap is that "build" reads as the safe step.** It is safe with respect to
*configuration* and unsafe with respect to *resources*, and those are different
axes. On this host, check `free -m` and `df -h /` first, and constrain the run:

```sh
sudo nixos-rebuild switch --flake /home/max/setup#ionos --max-jobs 1 --cores 1
```

`--cores 1` matters alongside `--max-jobs 1`: it caps parallelism *inside* a
single derivation, which is what bounds a Go or C++ compiler's memory. Run it
under `tmux`, never a bare ssh session.

**`sops-install-secrets` is the specific offender**, and it recurs on every
host. It comes from the sops-nix flake, not nixpkgs, so `cache.nixos.org` has
never built it — it compiles from source and runs its test suite every time the
input moves. It spent 20 minutes in `buildPhase` here. Fix it once, fleet-wide:

```nix
nix.settings = {
  substituters = ["https://nix-community.cachix.org"];
  trusted-public-keys = ["nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="];
};
```

Until then it can be passed per-invocation with `--option extra-substituters` /
`--option extra-trusted-public-keys`, which is how this upgrade was finally
completed.

**Consequence for this phase:** step 1 is "control server on ionos", i.e.
another build on the box that just fell over.

⚠️ **"Give ionos a remote builder" — as first written here — cannot work, and
the reason is structural.** `nix.buildMachines` requires ionos to *dial out* to
the builder, and brink-server sits behind the UDM SE on DS-Lite CGNAT. ionos
cannot reach it. That path is exactly what Phase 3 is being built to create, so
depending on it to build Phase 3 is circular.

**Reverse the direction instead.** brink-server → ionos works today, because
ionos has a fixed public address. So build ionos's closure *on* brink-server —
native x86_64-linux, 32 GB, idle — and push it:

```sh
# on brink-server, from its own clone
nixos-rebuild switch --flake /etc/nixos#ionos \
  --target-host max@212.132.82.102 --use-remote-sudo
```

This needs no `nix.buildMachines`, no new config on either host, and no overlay.
Verified on the wire 2026-08-06: brink-server is `x86_64`, `tcp/22` to ionos is
**reachable**, and the *only* gap is authentication — `Permission denied
(publickey)`, since its sole key `id_brink_server` is the GitHub deploy key.

⚠️ **Prefer agent forwarding (`ssh -A`) over adding a key, and the reason is not
convenience.** `base.nix:25` authorises `max` from
`pubKeys = listFilesRecursive modules/data/keys`, so *every* `.pub` dropped in
that directory grants access to **every host in the fleet**, not just the one
you meant. Adding `brink-server.pub` would let brink-server log into ionos,
maxdata, winkel-pi and both Macs — a far broader grant than "let it push a
closure to ionos". (`maxdata.pub` already sits there and already does exactly
that, which is worth revisiting on its own merits.)

Forwarding the agent uses the `max-admin` key already in 1Password, leaves no
private material on brink-server, and scopes the access to the moment a human
initiates the deploy — which is the right shape for something this deliberate.
The deploy is not meant to be unattended.

It also generalises: the same inversion is how any x86_64 host in this estate
gets built without trusting a VPS to compile, and it stops being necessary once
the overlay makes the CGNAT direction routable.

📌 **A build counter is a diagnostic.** Mid-run this looked like a cache-coverage
problem, and a Renovate-bumped `flake.lock` pointing at a non-channel nixpkgs
revision was the theory. `[1/14/171 built]` disproved it: if coverage were
genuinely missing at the perl layer, everything downstream would rebuild and the
queue would be in the thousands, not 171. A small queue with a flake-provided Go
package at its head means "a few uncached derivations", not "wrong nixpkgs".

## 3.1 Subnet routers — the staging is gone

⚠️ **Rewritten 2026-08-06.** This section described a two-step interim/final
handover: the pi advertising Brink from `192.168.1.90` while maxdata advertised
Winkel, with both static routes rewritten later in Phase 5. **Both premises are
now false.** The pi was moved to Winkel on 2026-08-05, and the brink-server
hardware is in hand. The staging, and the coverage-gap choreography that went
with it, are simply unnecessary — the final assignment can be configured once.

| | Brink `192.168.1.0/24` | Winkel `192.168.178.0/24` |
|---|---|---|
| **Final, configured directly** | brink-server `192.168.1.2` | pi `192.168.178.3` |

This removes real work and real risk: maxdata never advertises a subnet, and
neither static route is ever rewritten.

⚠️ **The cost: Brink has no overlay-capable host until brink-server exists.**
The pi used to be the stand-in and has left. The UDM SE cannot fill the gap —
see 3.2. So this phase depends on brink-server, which means one of:

- **Build brink-server first** (Phase 5.1 pulled forward — the hardware is
  available), then run Phase 3 once with both sites covered. Preferred.
- Or accept that Phase 3 delivers the **Winkel half plus per-device clients**,
  and Brink subnet routing lands with brink-server in Phase 5. The exit criteria
  below then split accordingly.

The old "pi move deadline: before Phase 6" is **satisfied** — it moved during
Phase 2. D10's argument that Winkel needs a second, independent way in still
holds, and is now a property of the pi being physically there.

## 3.2 Static routes — both sides confirmed

Phase 0 verified both routers expose a configurable static-route table, so the
"unmodified client reaches the other site" requirement has a mechanism at both
ends. No contingency needed.

⚠️ **Corrected by Phase 2.** This section previously stated that UniFi OS ships
a *first-party* Tailscale app for the UDM/UDR line. No such first-party app was
found. What exists is a third-party community package
(`SierraSoftworks/tailscale-unifi`), installed by `curl … | sh` over SSH and
persisting under `/data`. It runs a real `tailscaled`, so it would accept a
self-hosted Headscale URL and could advertise routes — but it is unsupported by
Ubiquiti, needs SSH on the UDM SE, and is a candidate to break on UniFi OS
upgrades. That is a poor foundation for the thing keeping cross-site routing
alive.

**Still unverified** — this needs someone to open the UniFi OS app store and
confirm. Until then assume the UDM SE is **not** its own subnet router,
brink-server remains the single point of failure for cross-site routing at
Brink, and the static-route design in this phase stands as written. NetBird has
no UniFi OS integration either way, so this never favoured NetBird.

## 3.3 Replacing the FritzBox VPN

The FritzBox is currently the **WireGuard server** for the whole estate. It
allocates each peer a `/32` from the LAN subnet starting at `192.168.178.201` —
`.201` is ionos (`hosts/nixos/ionos/default.nix:95`), with further peers at
`.202`, `.203`, … for remote-access clients. Configured under
**Internet → Freigaben → VPN (WireGuard)**.

Every one of those peers is a remote-access use case the overlay must replace, so
before rolling out:

- [ ] Enumerate the existing FritzBox VPN connections. Each is a person or device
      that needs an overlay client in step 2 above.

This inversion is the main structural win of the phase. Today the tunnel depends
on MyFRITZ! DDNS resolving and on the FritzBox holding a prefix that Phase 0
confirmed is *not* guaranteed stable (`2a00:6020:b481:e300::/56`, D2) — hence the
boot-ordering hack at `hosts/nixos/ionos/default.nix:143-147`. Afterwards both
sites dial **out** to ionos's fixed address, and no site needs a stable inbound
address at all.

Retiring it in Phase 13 also frees `192.168.178.201+`, removing any chance of the
peer allocation growing into the `.240–.250` MetalLB pool.

## 3.4 The GUI is deferred to Phase 10

The layering rule puts the overlay GUI (Headplane) in the cluster, as a pod that
talks to the control server over its API. That is still the right end state, but
building it now means building it twice: the cluster is degraded today and is
destroyed in Phases 6–7.

Deferred to Phase 10, with the rest of the workloads. If a peer list is needed
before then, `headscale nodes list` on ionos is sufficient — it is what Phase 2
used throughout. "GUI reachable and shows all peers" moves to Phase 10's exit
criteria.

## 3.5 Exit criteria

- [x] **Unmodified Brink client reaches unmodified Winkel client, and vice
      versa** (2026-08-06). Mac → maxdata 11.8 ms and → winkel-pi 15.8 ms;
      maxdata → Mac 9.9 ms, → UDM SE 6.9 ms, → brink-server 5.9 ms. All 0%
      loss, and none of the endpoints tested run an overlay client
- [x] **Phone off-net reaches both sites** — iPhone enrolled as `100.64.0.4`
      via the Tailscale app pointed at the self-hosted control server
- [x] **Path characterised: direct over native IPv6, not relayed.**
      `pong from winkel-pi via [2a00:6020:b481:e300:…]:41641 in 5ms`, matching
      Phase 2's p50 of 5.8 ms on throwaway state
- [x] **Overlay MTU measured exactly: 1280.** The cliff sits precisely between
      1280 and 1281 bytes total (`-M do -s 1252` passes, `1253` fails), against
      a 1500-byte same-LAN baseline. Confirms D3 on the production overlay, so
      Phase 7's flannel MTU is **1230**
- [x] **ionos derives its age key from a host key** (inherited from Phase 2b) —
      and verified after a **cold boot**, not merely after `switch`:
      `/run/secrets/k3s_token` was written at boot and `k3s.service` came up.
      Activation and boot are different code paths, and only the second one is
      the failure this staging existed to prevent. With maxdata corrected the
      same day, **no host now derives a sops identity from a user key**
- [x] **Control server survives a reboot of itself and of a client** — both
      halves exercised on 2026-08-06. ionos rebooted for the age-key flip and
      all four hosts reconnected with both routes still *Serving*, no
      intervention. brink-server was then cold-booted: it rejoined on the same
      address, decrypted its auth key at boot, and **cross-site routing came
      back by itself** (7.4 ms to maxdata) with its own LAN unaffected
- [~] **Longer-window RTT/flap sampling — deliberately waived, 2026-08-06.**
      Not done, and recorded as waived rather than ticked, because the two are
      not the same and Phase 7's D4 gate rests on this. What exists is Phase
      2's **5 h 55 min** on throwaway state: 347/347 direct, zero loss, zero
      relay fallback. What is missing is diurnal variation and a longer
      baseline for flap frequency on the *production* overlay.

      The waiver is reasonable on the evidence — nothing observed has ever
      relayed, and D4's timers sit 73× and 735× above the measured p99 — but it
      is a judgement call, not a measurement. **Phase 7's "etcd stable 24 h, no
      leader elections" gate is now the first real long-window test**, and
      Phase 12's permanent blackbox probes are the durable one. If either shows
      direct→relay flapping, revisit D4 before trusting the cluster to it
- [ ] GUI reachable and shows all peers — **deferred to Phase 10 by design**
      (3.4), not outstanding work. `headscale nodes list` suffices until then
- [x] **Control server config and ACLs committed** — server, client module and
      the HuJSON policy all in git, deployed from the store
- [x] **Every existing FritzBox VPN peer has an equivalent overlay client** —
      the peer list turned out to be exactly two: ionos and the iPhone. ionos
      is a mesh node and the iPhone is enrolled, so the set is covered. The
      FritzBox tunnel is *not* retired until Phase 13 and remains the
      independent second path — see 3.6, where an overlay change silently took
      it out of use

---

## 3.6 Two failures worth keeping

Both were introduced by this phase's own configuration, and both generalise
beyond it.

### 3.6.1 Only subnet routers may accept routes

⚠️ **This broke maxdata outright and degraded ionos invisibly.**

Accepting routes puts them in **table 52**, which tailscale consults via an
`ip rule` at priority **5270 — ahead of the main table at 32766**. An accepted
route for a prefix the host is *directly connected to* therefore outranks its
own LAN route.

| Host | What happened |
|---|---|
| **maxdata** | Accepted winkel-pi's `192.168.178.0/24` — its own subnet. Replies to LAN neighbours went into the tunnel instead of out `vmbr0`. Incoming worked, outgoing did not: **ARP stayed `REACHABLE` while ping and ssh were dead** |
| **ionos** | Its `wg0` carries `192.168.178.201/24`, so the accepted route displaced the **FritzBox tunnel** as the path to Winkel. Everything kept working while the independent second path Phase 13 depends on quietly stopped being used |
| **brink-server** | Unaffected — tailscale never installs an accepted route for a prefix the node itself *advertises* |

ionos is the more instructive case: nothing looked wrong. The failure was a
silent loss of redundancy, which is exactly the class of fault that is only ever
discovered when the redundancy is needed.

**Rule, now enforced in `modules/system/overlay-client.nix`: a host accepts
routes if and only if it advertises one.** Non-routers lose nothing — overlay
peers stay reachable at their `100.64.0.0/10` addresses, and the far site's LAN
is reached the way any unmodified client reaches it, through the router's static
route. Verified: maxdata reaches `192.168.1.2` at 5.9 ms with `--accept-routes`
off, via the FritzBox route.

📌 **maxdata was recovered over the overlay** (`ssh -J ionos max@100.64.0.5`)
while its LAN address was dead. That is D10's argument for putting the pi at
Winkel, arriving unplanned: the site had a second way in that did not depend on
the broken host.

### 3.6.2 Removing iptables rules needs one deploy of overlap

⚠️ **Headscale bound 443 and still received nothing.**

Freeing 443 meant deleting the six 80/443 DNAT rules pointing at the dead
ingress VIP. Both the `extraCommands` that *add* them and the
`extraStopCommands` that *delete* them were removed in the same change — so
when `firewall.service` reloaded, it ran the **new** stop commands, which no
longer knew those rules existed. The rules stayed live, kept swallowing 80/443
into the dead tunnel, and Headscale never saw a packet.

The symptom was diagnostic once read properly: connections to 80/443 failed in
~170 ms while a genuinely firewalled port (`tcp/3478` before it was opened) took
the full 8 s to time out. **Fast failure is a reject or an ICMP unreachable;
slow failure is a drop.**

**Pattern: keep the delete half for one deploy, then remove it.** Or flush the
rules by hand, as was done here. Anything managed imperatively through
`extraCommands` is only ever removed by a matching `extraStopCommands` that is
still present at reload time.

---

# Phase 4 — DNS

AdGuard runs **natively on NixOS**, one instance per site: brink-server (Brink) and pi
(Winkel). Both on pinned static LAN addresses.

- Routers keep DHCP (never depends on k8s).
- Each router hands out its site's AdGuard as **primary** and itself as
  **secondary**. A dead AdGuard means ad-blocking goes leaky, not that the site
  loses name resolution.
- Split-horizon for `*.mvissing.de`: internal names resolve to the site-local
  MetalLB VIP; everything else goes out to ionos.
- Overlay DNS (MagicDNS or equivalent) layered on top for node names.
- Upstream: Cloudflare DoH, matching the current in-cluster config
  (`apps/adguard.ts:49-55`).

**Brink caveat:** brink-server is the only node at Brink. If it is down, Brink falls
back to the UDM SE resolver. Clients pick between primary and secondary
nondeterministically, so ad-blocking is leaky during a brink-server outage rather than
cleanly absent. Accepted.

The in-cluster AdGuard (`apps/adguard.ts`) is deleted in Phase 8.

Implemented 2026-08-06 as `modules/system/site-dns.nix`, one module for both
hosts — the `services.adguardhome` module is byte-identical in the fleet's
nixpkgs and the pi's, so D12's version split does not bite here.

Everything is derived from `networkConfig`; no address is written twice. The
module **asserts** `sites.<site>.adguard == hosts.<host>.lanIPv4`, because the
routers' DHCP is configured from the first and AdGuard binds the second, and
those two facts live in different systems where nothing else would notice them
diverging. Forcing a mismatch produces:

```
siteDns: networkConfig.sites.brink.adguard is 192.168.1.99 but brink-server
binds 192.168.1.2. The routers' DHCP is configured from the former and
AdGuard listens on the latter — they must not drift.
```

## 4.1 What was deliberately staged

The deploy was split from the cutover: **AdGuard was stood up with nothing
pointed at it**, verified by querying each instance directly, and only then did
`sites.*.dnsServers` change. That ordering is not ceremony — it is what caught
the split-horizon rewrites being completely inert (4.3) at a moment when the
cost was zero. The in-cluster AdGuard on `192.168.178.14` kept serving Winkel
throughout and is still running; Phase 8 deletes it.

## 4.2 The Phase 1 backup was not restored, and there was nothing to restore

`localpath-adguard-data.tar.gz` was extracted and read before deciding. It is a
stock configuration:

| Key | Value in the backup |
|---|---|
| `users` | `[]` — **no admin hash exists at all** |
| `user_rules` | `[]` |
| `filtering.rewrites` | `[]` |
| `clients.persistent` | `[]` |
| `filters` | the two stock lists |
| `upstream_dns` | Cloudflare DoH |

So the "don't silently regenerate an admin hash nobody has" concern was void:
the in-cluster instance ran unauthenticated behind Authentik forward-auth. The
only content worth carrying — the two filter lists and the Cloudflare
upstreams — is now declared in Nix.

**Consequence:** natively there is no Authentik in front, and `users` is left
undeclared on purpose. `mutableSettings` merges declared keys *over* the state
file, so a password set once in the web UI persists across every later rebuild
without a bcrypt hash entering the world-readable nix store. Until that is
done the UI is open to anyone on the LAN or the overlay.

## 4.3 Three traps, all of which looked like success

1. **The rewrites were inert.** Every entry landed with `enabled: false` —
   a schema migration default for an omitted field, not something written by
   hand. `AdGuardHome.yaml` read as entirely correct while every
   `*.mvissing.de` name still resolved to ionos.

2. **The module cannot be tested imperatively.** `preStart` re-merges the
   store config on *every* start, so two hand-edited "tests" silently re-ran
   the original configuration. The fix was only proven by running a second
   AdGuard on separate ports and a separate work directory.

3. **The UDM SE answers DNS for addresses that do not exist.** Testing
   winkel-pi's resolver from Brink reported it broken; it was correct all
   along, and the replies were the UDM SE's. See the decision log.

## 4.4 IPv6, and why the resolvers have a ULA

The router step as originally written — set the DHCP DNS server — **would not
have worked**. Clients prefer an RA-advertised IPv6 resolver over the DHCPv4
one, so `nameserver[0]` on the Brink Mac was the UDM SE's own address and
would have stayed that way.

Giving AdGuard an IPv6 address inside the site's delegated prefix is ruled out
by D2: the Deutsche Glasfaser /56 changes unannounced, and the router would go
on advertising an address that no longer exists. So each resolver gets a
**stable ULA** — see the decision log for the prefix and why it avoids
Tailscale's range and the legacy one.

## 4.5 Router configuration — done, and what each UI actually offers

Both routers were cut over on 2026-08-06 and verified on the wire.

| Router | DHCPv4 DNS | IPv6 |
|---|---|---|
| **UDM SE** (brink) | `192.168.1.2`, then `192.168.1.1` | ULA `fd06:f10a:ebec:1::1/64` added as an **additional IP on the VLAN** — that is what makes the UDM advertise the prefix; RDNSS → `fd06:f10a:ebec:1::2` |
| **FritzBox** (winkel) | `192.168.178.3` | *ULA-Präfix manuell festlegen* → `fd06:f10a:ebec:178::/64`; **„DNSv6-Server auch über Router Advertisement bekanntgeben (RFC 5006)"** ticked; *Lokaler DNSv6-Server* → `fd06:f10a:ebec:178::3` |

Two notes that cost time:

- **The UDM SE has no separate "advertise this prefix" control.** Adding the
  ULA under *additional IPs* on the VLAN is what does it. Before that address
  existed the RA carried the RDNSS option but **no prefix-info for the ULA**,
  so clients were told to use a resolver they had no route to. Confirmed by
  capturing the RA (`tcpdump 'icmp6 && ip6[40] == 134'`), which is the only
  way to see this — the UI shows nothing wrong.
- **On the FritzBox, „DNSv6-Server auch über Router Advertisement bekanntgeben"
  is not the same as „Auch IPv6-Präfixe zulassen, die andere IPv6-Router im
  Heimnetz bekanntgeben".** The first advertises a resolver outbound; the
  second accepts prefixes inbound. Only the first matters here.

The FritzBox retires the old `fda8:a1db:5685::/64` gracefully — it still
advertises it with **valid and preferred lifetime 0** rather than dropping it,
which is why hosts lost those addresses without disruption. **ionos's `wg0` was
unaffected**, verified by handshake and ping: its `fda8:` addresses are
statically configured on both ends and never depended on the LAN
advertisement.

⚠️ **maxdata still resolves via the FritzBox**, not via winkel-pi. It reads the
deprecated `networkConfig.dns.servers`, which Phase 6 replaces — the only host
at either site not yet on its site resolver.

## 4.6 Exit criteria

- [x] **Split-horizon `*.mvissing.de` resolves to the site-local VIP** —
      `192.168.1.240` at Brink, `192.168.178.240` at Winkel, each from its own
      resolver, with the apex left alone
- [x] **`headscale.mvissing.de` still resolves to ionos from both sites**, A
      and AAAA — the exclusion the overlay depends on
- [x] **MagicDNS names resolve** through both resolvers
      (`winkel-pi.mesh.mvissing.de → 100.64.0.3`)
- [x] **Blocking verified at both sites** (`doubleclick.net → 0.0.0.0`)
- [x] **Failover verified by stopping AdGuard** — 37 ms, via the router,
      blocking leaky rather than the site offline
- [x] **Both resolvers answer over IPv6** on their ULA, verified for
      split-horizon, exclusion, blocking and AAAA
- [x] **winkel-pi verified across a reboot** — address, default route and an
      outbound connection checked separately, no failed units
- [x] **Both sites resolve via their local AdGuard** — real clients in both
      query logs, on both address families. Winkel shows a client at
      `fd06:f10a:ebec:178:1806:…`, i.e. reaching AdGuard over the
      RDNSS-advertised ULA, so **per-client visibility survived** — which was
      the whole reason for choosing the ULA over having the routers forward
- [ ] Split-horizon behaviour off-net re-checked once Phase 9 gives the VIPs
      something to serve. Today they are aspirational: nothing listens on
      either `.240`, and every app hostname already fails at ionos, so this
      is not a regression — but it is not yet a working internal name either

---

# Phase 5 — brink-server bring-up and pi relocation

⚠️ **Partly done, and reordered — 2026-08-06.** The pi was physically moved to
Winkel on 2026-08-05, during Phase 2. That removes this phase's original reason
to exist: there is no longer a handover to sequence, so "build brink-server
first so it can take over before the pi leaves" no longer applies, and neither
static route is ever repointed. Both are configured once, in Phase 3 (see 3.1).

What is left here is the *configuration* of two hosts, and the dependency now
runs the other way: **Phase 3 needs brink-server**, because moving the pi left
Brink with no overlay-capable host. Consider building it before Phase 3 rather
than after — see 3.1 for that choice.

## 5.1 brink-server

Bare-metal NixOS install, done by hand, at Brink.

🔄 **Configuration written 2026-08-06; the install itself is still pending.**
Full step-by-step procedure: [`brink-server-install.md`](./brink-server-install.md).

- Single 1 TB NVMe. ZFS single-vdev — no redundancy, but gains snapshots,
  compression and tooling parity with maxdata. Backed up to maxdata's `tank` in
  Phase 11, which is what makes the lack of redundancy acceptable.
- ✅ `hosts/nixos/brink-server/` written and **evaluating** —
  `nix eval …#nixosConfigurations.brink-server.…drvPath` succeeds, rendering
  `192.168.1.2/24`, gateway `192.168.1.1`, `hostId = b21961a5` (distinct from
  maxdata's `ec7b6b2d` and the pi's `03030303`).
- ⚠️ `hardware-configuration.nix` is **partly provisional**. Its `fileSystems`
  block is correct by construction — the runbook creates exactly that layout, so
  the file is the *source* of the layout rather than a record of it. The
  kernel-module lists are a guess and must be reconciled on the hardware with
  `nixos-generate-config --root /mnt --no-filesystems`. Without
  `--no-filesystems` the generated output overwrites the layout with `by-uuid`
  paths.
- Static `192.168.1.2` (verified free in Phase 0), and *below* the UDM SE's DHCP
  floor of `.6`, so claiming it needs no router change at all.
- ✅ Installer media ready: NixOS 26.05 minimal x86_64 at
  `~/Downloads/nixos-minimal-26.05-x86_64.iso` on the Mac, SHA-256 verified
  against the published checksum.
- Overlay client + subnet router for `192.168.1.0/24` — **Phase 3, not here.**
- AdGuard — **Phase 4, not here.**
- Secret enrolment per Phase 2b: sops **host** key at
  `/etc/ssh/ssh_host_ed25519_key`, `.sops.yaml`, `sops updatekeys`. No 1Password
  component — D11 keeps the vault out of the host secret path entirely. The
  config declares the plumbing with **zero secrets**, which is what makes it
  safe to commit before the host exists: sops-nix with an empty secret set is a
  no-op at activation, so a first boot cannot fail on a key that could not have
  been enrolled yet.
- k3s server module (not enabled until Phase 7).

Three choices worth reviewing: the pool is named **`main`**, uses **native
mountpoints** rather than `mountpoint=legacy`, and compresses with **zstd**
where maxdata uses lz4 (D13); and the host runs
**systemd-networkd** rather than the scripted networking that bit the pi twice
(D14).

The install procedure in `docs/Migrate_Maxdata.md:136-207` was the starting
point for the ZFS and `nixos-install` steps.

## 5.2 Pi — `winkel-pi` ✅

✅ **Done 2026-08-06.** Everything Phase 5 owned for this host is complete: the
rename, the `hostId`, the static address, the move, and the sops host key. The
three items still listed under *Remaining* belong to Phases 3, 4 and 7.

**Physically at Winkel since 2026-08-05**, on the static `192.168.178.3` since
2026-08-06 (it first took `.118`, a DHCP lease the FritzBox reissued from its
previous stay). Identity confirmed by MAC `dc:a6:32:22:a2:a1`, not by name.

### Done

1. ✅ `/var/lib/hass` (313 M) backed up to
   `~/backup/pre-multi-site/pi-hass-2026-08-05.tar.gz` — verified, 3341 entries.
   The state directory is still on disk; removing the service does not delete it.
2. ⏭️ **Re-image deliberately skipped.** The rename and `hostId` are declarative,
   and re-imaging a known-flaky USB-SATA disk risks a working boot setup for no
   gain. Rebuilt in place instead. The quirk is carried and verified active on
   the new kernel (`/proc/cmdline`: `usb-storage.quirks=174c:55aa:u`).
3. ✅ **Renamed `k3s-pi` → `winkel-pi`** (2026-08-06), `hostId` `03030303` →
   `7a943cc4`. Site-first, matching `brink-server`; the old name was a role it
   never took up and is not getting back, since Phase 7 rejoins it as an
   *agent*. The rename was done in one commit because it is one surface:
   `hosts/nixos/`, `rpiHosts` and the flake attribute, `networkConfig.hosts`,
   the `.sops.yaml` anchor, the ssh alias, and the deploy key filename
   (`id_k3s_pi` → `id_winkel_pi`, copied on the box *before* the rebuild so
   both names existed during the transition). `k3s-pi-installer` became
   `rpi-installer` — it contains no host config and was never this host's to be
   named after.

   Verified **after a reboot**, per 6.5: `hostname` and `hostnamectl` both
   `winkel-pi`, `/etc/hostid` `c43c947a` (little-endian `7a943cc4`),
   `192.168.178.3/24`, default route via `.1`, outbound HTTPS 200 with working
   DNS, 5 IPv6 addresses, `accept_ra=2`, USB quirk still on the cmdline, zero
   failed units, deploy key authenticating as `Hi MaxMac99/setup!`.

   **The rebuild was de-risked by diffing before activating.** `nixos-rebuild
   build` produced a store path identical to the one evaluated on the Mac, and
   the `etc` diff against the running system was exactly `hostid`, `hostname`,
   `hosts`, `ssh/ssh_config`, `avahi-daemon.service` and `zshrc` — **no
   networking units at all**. That is what made the 6.5 failure mode
   inapplicable to this particular change, and it is a cheaper check than
   recovering from it.
4. ✅ `services.home-assistant` and `services.matter-server` removed
   (`c5343de`). Pulled forward because paho-mqtt's flaky test suite blocked the
   build — but the real justification is that since the pi moved to Winkel it
   cannot reach a single smart-home device, as they are all at Brink and there
   is no cross-site mDNS.
5. ✅ **Static `192.168.178.3`** (2026-08-06), from `networkConfig` rather than
   inline. `.3` was verified free from the Winkel LAN itself. Applying it live
   broke networking twice — see 6.5, which now carries the warning.
6. ✅ Physically moved to Winkel.
7. ✅ Verified by SSH and MAC, not mDNS. ⚠️ **This warning briefly inverted and
   is now live again.** maxdata's stale Avahi record `k3s-pi.local →
   192.168.178.118` was *accidentally correct* while the FritzBox had reissued
   that exact lease — so it lulled rather than alerted. Since the pi took the
   static `.3` on 2026-08-06 it is wrong once more. Keep confirming by MAC, and
   flush maxdata's cache when convenient.

   ✅ **The rename defuses this permanently.** The pi now publishes
   `winkel-pi.local`, so `k3s-pi.local` is not merely stale but *orphaned* — no
   host answers to it, and it can never again be accidentally right the way it
   was in August. The trap this item warns about was only possible while a live
   host and a stale record shared a name.
8. ⏭️ Repointing is **not needed** — Phase 3 configures both static routes once,
   at their final next hops, and maxdata never advertises a subnet.

Also done, not in the original plan: the pi now **maintains itself from GitHub**
(`4b1757c`). `/etc/nixos` is a git clone on `multi-site`, pulled over SSH with a
device key at `/home/max/.ssh/id_winkel_pi` whose public half is a **read-only**
deploy key scoped to this repo. Its update cycle is `git pull &&
nixos-rebuild switch`, run on the pi, with no Mac involved.

⚠️ **A rewritten branch strands a self-updating host, silently — found
2026-08-06.** The pi's clone sat on `8aa8e67`, a commit no ref on origin
contained: `multi-site` had been rebased and force-pushed at some point after
the pi cloned it, and the pi kept a stale remote-tracking ref, so nothing looked
wrong locally. `git pull` would not have failed cleanly — it would have *merged*
two divergent histories carrying the same changes under different hashes,
leaving the pi permanently ahead of origin and every later pull worse than the
last. The fetch is what exposes it (`+ 8aa8e67...d92d9b9 (forced update)`).

The repair, for any host whose `/etc/nixos` is a pull-only clone that never
authors commits:

```sh
cd /etc/nixos
git status --porcelain   # must be empty
git stash list           # must be empty
git fetch origin && git reset --hard origin/multi-site
```

`reset --hard` rather than `pull`, precisely *because* the host authors nothing:
there is no local work to preserve, and a merge would manufacture history that
only exists on that host. Distinguish the two cases by the fetch line —
`b187c6d..5376880` is a fast-forward, `+ 8aa8e67...d92d9b9 (forced update)` is
the orphan — or, non-destructively, with
`git merge-base --is-ancestor HEAD origin/multi-site`.

✅ **brink-server checked and clean** (2026-08-06): `HEAD` is an ancestor of
origin, 3 behind and 0 ahead, fast-forwarded normally. It was cloned *after* the
rewrite, so only the pi was ever affected.

⚠️ **The pi tracks a different nixpkgs from the rest of the fleet.** It is built
with `nixos-raspberrypi.lib.nixosSystem` and therefore that flake's nixpkgs
(NixOS 26.05), not the root one (26.11) — see D12. `nix flake update nixpkgs`
does not move the pi; only updating the `nixos-raspberrypi` input does.

8. ✅ **Secret enrolment** (2026-08-06). sops wired to the **host** key at
   `/etc/ssh/ssh_host_ed25519_key`, and `winkel-pi` enrolled as the 6th
   recipient of `common.yaml` — where Phase 3's overlay pre-auth key lands.
   **Decrypt proven on the box**, not on paper: `sops -d secrets/common.yaml`
   run on the pi under an age key derived from its own host key hashed to
   `a342c743…`, identical to the Mac's. `updatekeys` left the plaintext
   unchanged.

   ⚠️ **The "dead recipiency" was a misdiagnosis, and the correction is
   load-bearing.** 0.5 and 2b.3 item 5 both recorded `k3s-pi` as a stale
   recipient of `k3s.yaml` left over from before `adfcc70`. Re-deriving from
   the *live* host key on 2026-08-06 reproduced `age1acjwuna…` **exactly**, so
   the key material was correct the whole time and only the host-side `sops`
   block was missing. Consequences: no key ceremony was needed, `k3s.yaml`
   needed no `updatekeys` at all (renaming a YAML anchor does not change a
   recipient list), and the pi turns out to have been on a **host** key since
   the beginning — so the D11/2b.2 offenders are only ionos and maxdata.

   Zero secrets are declared, matching brink-server. That is provable rather
   than merely claimed: with an empty secret set sops-nix emits no
   `system.activationScripts.setupSecrets`, and the system derivation is
   **bit-identical** to the one without the block. The pi cannot fail a boot on
   this.

### Remaining

All three are owned by later phases; nothing is left that belongs to Phase 5.

6. **Overlay client + subnet router** for `192.168.178.0/24`, with
   `net.ipv4.ip_forward` declared — Phase 3.
7. **AdGuard** — Phase 4.
9. **k3s agent module** — not enabled until Phase 7.

## 5.3 Exit criteria

- [x] brink-server at Brink on `192.168.1.2` — **installed 2026-08-06**, see
      [`brink-server-install.md`](./brink-server-install.md). Verified after a
      reboot: `eno1 192.168.1.2/24`, default route via `.1`, outbound HTTPS,
      UEFI, `zpool` healthy, no failed units, ZFS mountpoints resolving without
      the install-time `/mnt` altroot prefix. Advertising `192.168.1.0/24` is
      Phase 3
- [x] Pi physically at Winkel, identified by MAC
- [x] Pi on the static `192.168.178.3` (2026-08-06) — advertising the subnet still pending, Phase 3
- [x] **Pi renamed to `winkel-pi`; `hostId` no longer collides** with node3's
      derived form — `03030303` → `7a943cc4`, verified after a reboot
      (2026-08-06)
- [x] **Secrets decrypt on both hosts, from host keys** — ✅ brink-server and
      ✅ winkel-pi, both proven on the box rather than on paper: each decrypted
      `common.yaml` to a plaintext hash matching the Mac's. The pi needed no key
      ceremony; its recipient was already derived from its host key and only the
      `sops` block was missing
- [x] **AdGuard serving at both sites** — done in Phase 4 on 2026-08-06:
      brink-server on `192.168.1.2` and winkel-pi on `192.168.178.3`, both
      routers cut over, real clients on each. This was the last item Phase 5
      was waiting on, and it belonged to Phase 4 throughout
- [x] **Winkel is reachable without maxdata** — the precondition for Phase 6,
      and proven the hard way rather than by the planned drill. On 2026-08-06
      maxdata lost its LAN address entirely (3.6.1) while winkel-pi kept
      serving `192.168.178.0/24` and stayed reachable throughout; Brink could
      still reach the Winkel LAN, and maxdata itself was recovered *through*
      the overlay. This is precisely D10's scenario, unrehearsed

---

# Phase 6 — maxdata: microVMs out, bare metal in

⚠️ **First irreversible step.** Everything before this is a safe stopping point.

## 6.1 Re-key sops FIRST

The microVMs' sops age identities are derived from
`/var/ssh/ssh_host_ed25519_key` — a file **inside** the 50 GB `var-state.img`
volume (`modules/system/k3s-node.nix:136`, volume at `:76-82`). maxdata is
already a declared recipient of `secrets/k3s.yaml` (`.sops.yaml:22`) but has no
`sops` block in any of its modules and consumes nothing.

Add a sops config to maxdata, verify it can decrypt `k3s.yaml`, and only then
proceed. **Destroy the images first and the k3s token becomes undecryptable** —
the single easiest way to brick this migration.

✅ **Done early, in Phase 3 (2026-08-06) — this phase no longer owns it.**
maxdata now has a `sops` block deriving from `/etc/ssh/ssh_host_ed25519_key`,
and decryption of **both** `common.yaml` and `k3s.yaml` was proven on the box
*before* the config was written. `/run/secrets/` exists on maxdata for the first
time.

Pulling it forward was deliberate. It was the single highest-risk item in the
migration precisely because it was bundled with the irreversible step: if
maxdata could not decrypt `k3s.yaml`, the token — encrypted to identities living
inside the very disk images 6.2 deletes — would be gone. Doing it while the
FritzBox tunnel was still up, no images were being destroyed, and Phase 3 was
already touching every host separated the risk from the irreversibility. What
remains here is only to re-confirm the decrypt immediately before 6.2 runs.

**Historical note.** It was Phase 2b work item 1; when 2b closed it moved here
rather than blocking there, on the reasoning that nothing in Phase 3 depended on
it. That reasoning turned out to be wrong in a useful way — Phase 3 wanted
maxdata on the overlay, which needed a decryptable auth key, which needed
exactly this.

✅ **Re-confirmed 2026-08-06, immediately before 6.2 deleted the images**, which
is what this section asked for and the one check whose failure is unrecoverable.
Done on the box under an age key derived from `/etc/ssh/ssh_host_ed25519_key`
(`age1ewxty…`), against **`origin/multi-site`** rather than maxdata's own clone —
which was five commits stale at that moment, and would have proven the wrong
file. `k3s.yaml → cc44af01…`, `common.yaml → ffbea925…`, exit 0.

Afterwards, and only once the images were actually gone, `&k3s-node1/2/3` were
removed from `.sops.yaml` and `sops updatekeys secrets/k3s.yaml` run (9 age
recipients → 6). Their identities came from `/var/ssh/ssh_host_ed25519_key`,
*inside* the deleted volumes, so they ceased to exist with the images. maxdata
was then proven a **third** time against the re-keyed file — same plaintext
hash. Ordering was deliberate: the fallback outlived the risk it existed for.
The user-key recipients `&maxdata` and `&ionos` are **still there**; they are
D11/2b.2 cleanup for Phase 13, not Phase 6.

**Partly de-risked by Phase 2b (2026-08-05).** maxdata's existing
`/home/max/.ssh/id_ed25519` derives `age1s44mfk…`, which is exactly the
`&maxdata` recipient at `.sops.yaml:4`. So the key material is already present
and correct; what is missing is only the `sops` block wiring it up. That makes
this a config change rather than a key ceremony. Two caveats: it is a *user* key,
inheriting the same smell as ionos (both should end on
`/etc/ssh/ssh_host_ed25519_key`), and matching on paper is not proof — require a
successful decrypt executed on the box before anything is deleted.

## 6.2 Remove the microVM layer

Delete:

- `hosts/nixos/maxdata/microvms.nix`
- `hosts/nixos/maxdata/microvm-bridge.nix`
- `hosts/nixos/maxdata/microvms/` (4 files)
- `hosts/nixos/k3s-node1/`, `k3s-node2/`, `k3s-node3/`

Remove the two imports from `hosts/nixos/maxdata/default.nix:24-25`. **No flake
edit needed** — `flake.nix:155-164` auto-discovers `hosts/nixos/*`.

✅ **Done 2026-08-06.** All of the above deleted, plus two things this list
missed: the now-unused **`microvm` flake input** (and its three `flake.lock`
entries), and the three `k3s-node*` **ssh aliases** in
`modules/profiles/personal-ssh.nix`.

⚠️ **The k3s-node.nix refactor was deliberately NOT done. `k3s-node.nix` was
deleted outright instead.**

The original instruction was to split it into `modules/system/k3s-server.nix`
and `modules/system/k3s-agent.nix`. That was reconsidered and dropped, because
nothing would import either module until Phase 7, and Phase 7 knows things this
phase does not: the flannel MTU (**1230**, D3), that `--node-ip` comes from
`hosts.<x>.overlayIPv4`, the `topology.kubernetes.io/zone` labels, and whether
`--vpn-auth` replaces the hand-rolled flags. Writing them here would leave two
speculative, unimported, untested modules in the tree carrying guesses at all
four. Phase 7 writes them fresh against real requirements.

`modules/system/k3s-base.nix` **stays** — ionos imports it
(`hosts/nixos/ionos/default.nix:11`) and it is not microVM-specific.

The four bullets above are therefore **inherited by Phase 7**, not lost. In
particular the `nodePathMap` rewrite from `/mnt/k8s-fast/local-path-provisioner`
to `/fast/k8s/local-path-provisioner` still has to happen: the virtiofs mount it
named no longer exists, while the data it pointed at is intact on ZFS
(`/fast/k8s/local-path-provisioner`, **58 G**, untouched by this phase).

⚠️ **Dangling reference left on purpose.** `hosts/nixos/ionos/default.nix:130`
still reads `serverAddr = "https://192.168.178.5:6443"` — k3s-node1, which no
longer exists. ionos's k3s agent has been unable to reach a control plane since
this phase. It was left alone because there is no correct value until Phase 7
and changing it means a build on ionos, which cannot be started casually
(see the ionos build-capacity note).

## 6.3 Reclaim resources

✅ **Done 2026-08-06 — but the ARC half was deliberately NOT done.**

18 GB RAM and 6 vCPU are freed, and the RAM genuinely came back: `available`
went **3.4 GB → 28 GB**.

⚠️ **`zfs_arc_max` was left at 8 GB on purpose.** Raising it looked obvious and
is wrong here. The freed 18 GB was a *fixed* reservation — held whether the
guests used it or not — backing workloads that ran *inside* them, and those same
workloads come back as native pods on this host from Phase 7. Handing the memory
to ARC now would only mean clawing it back under pressure later, which ARC
resists. It stays as k3s headroom. Only the stale comment was corrected.

**Consequently the 6.6 exit criterion "ARC max raised" is withdrawn, not
skipped.** Revisit it in Phase 8 or 12, once the real native workload footprint
is measurable rather than guessed.

The value is still duplicated in **three** places and they must continue to
agree — verified identical after this phase:

- `hosts/nixos/maxdata/default.nix:49-56` (`kernelParams` + `extraModprobeConfig`)
- `hosts/nixos/maxdata/zfs.nix:113-121` (a second `boot.extraModprobeConfig`)
- `hosts/nixos/maxdata/zfs.nix:124-130` (`environment.etc."modprobe.d/zfs.conf"`)

Also fix the now-wrong comment at `default.nix:48`
(`# ZFS ARC tuning for 32GB RAM (18GB reserved for 3x 6GB microVMs)`).

## 6.4 Firewall cleanup

✅ **Ports dropped 2026-08-06:** 8006 (Proxmox UI), 9090 (Cockpit), 5900 (VNC),
3128 (subscription proxy). Nothing served them.

✅ **The 3.6.2 trap does not apply here — checked, not assumed.**
`extraCommands`/`extraStopCommands` exist **only** on ionos
(`hosts/nixos/ionos/default.nix:90,100`); maxdata has neither, so there were no
live rules to orphan. `dry-activate` confirmed `firewall.service` is *reloaded*.

⚠️ **`trustedInterfaces = ["vmbr0"]` was deliberately KEPT.** The comment claimed
it existed "so the microVMs could talk freely", but `vmbr0` is maxdata's only
LAN interface, so in practice it emits `-A nixos-fw -i vmbr0 -j nixos-fw-accept`
as the **first** rule — the entire LAN is trusted and the port list above is
largely decorative.

Removing it makes the firewall real for the first time, and two things depend on
it that the port list does **not** cover:

- **`node_exporter` (9100) and `smartctl_exporter` (9116) are opened by nothing
  else.** Only `zfs-prometheus-exporter` (9134) is explicit
  (`monitoring.nix:11`). Verified against the live `nixos-fw` chain.
- **`rpc.mountd`/`statd` hold dynamic ports** unless pinned via
  `services.nfs.server.{mountdPort,lockdPort,statdPort}`.

Neither is testable in this phase — the cluster that scrapes those exporters and
mounts those exports is destroyed *here* and not rebuilt until Phase 7. Doing it
blind on the same day as the irreversible step, on a host nobody is sitting at,
buys nothing. **Moved to Phase 8**, which wires NFS up against a real consumer
and can pin the ports and open 9100/9116 explicitly, with something live to
prove it against.

⚠️ **Renaming `vmbr0` was also deliberately declined.** It is referenced at
`networking.nix:20,27,35` and is the netdev every address on the host rides on;
re-creating a netdev is exactly what drops those addresses during a networkd
reload (6.5). Cosmetic gain, and the one failure mode this phase had to avoid.
Left for a phase that is not also doing something irreversible.

## 6.5 Deploying without console access

You have local access but prefer not to use a console. The safe sequence:

1. Arm a dead-man's reboot before activating:
   ```sh
   sudo shutdown -r +10
   ```
2. `nixos-rebuild test --flake .#maxdata` — activates the generation **without
   touching the bootloader**. If the network config is wrong and you lose the
   box, the scheduled reboot (or a power cycle) returns to the previous
   generation.
3. Verify reachability from both sites and over the overlay.
4. `sudo shutdown -c` to cancel the reboot.
5. `nixos-rebuild switch --flake .#maxdata` to make it permanent.

⚠️ **Step 2 does not prove the network config works — learned the hard way on
the pi, 2026-08-06.** On a **scripted-networking** host `nixos-rebuild
test`/`switch` stops `dhcpcd` — which deletes every address and route — but does
**not** start `network-setup.service`, which owns the static addresses. The
interface is left with nothing. On the pi this presented twice, differently:

- first as total silence, at both the old and new address;
- then, more insidiously, with the address applied but **the default route
  missing** — LAN-reachable, so it looked fine, while every outbound connection
  failed with `Network is unreachable`. A `git pull` failed and a rebuild
  silently used a stale commit.

⚠️ **Correction, 2026-08-06 — this passage previously asserted "maxdata uses
scripted networking (no systemd-networkd)". That was wrong.**
`hosts/nixos/maxdata/networking.nix:8-13` sets `useNetworkd = true` and
`systemd.network.enable = true`, and builds `vmbr0` as a
`systemd.network.netdevs` entry; maxdata's address was observed live on exactly
that bridge, which scripted networking would not have created. So the specific
`dhcpcd`-versus-`network-setup.service` failure above **does not apply to
maxdata at all**.

⚠️ **But it is not "a property of the pi" either — that was too narrow.** The
fleet splits two ways, and ionos is on the scripted side:

| Scripted (`dhcpcd` + `network-setup.service`) | systemd-networkd |
|---|---|
| `winkel-pi`, **`ionos`** | `maxdata`, `brink-server` (D14) |

⚠️ **Unit names corrected 2026-08-06 (Phase 4).** `network-setup.service` does
**not exist on winkel-pi** — `systemctl is-enabled` returns `not-found`. NixOS
26.05 splits scripted networking into per-interface units, so the pi has
**`network-addresses-end0.service`** (the unit that actually owns the static
address) plus `network-local-commands.service` and `networking-scripted.target`.
The failure mode is unchanged; only the name to watch is. Note the trap in
checking this: `systemctl is-active` reports a non-existent unit as `inactive`,
which reads like "present but stopped" — use `is-enabled`, which says
`not-found`.

There is also a way to avoid the hazard rather than survive it: **`nixos-rebuild
boot` followed by a reboot never performs the live transition at all.** Phase 4
used exactly that on winkel-pi for the one change that did alter
`network-addresses-end0.service`, and the address came up clean on boot. Prefer
it on the pi whenever a change touches networking.

ionos's upgrade on 2026-08-06 reproduced the exact signature — `network-setup.
service` appeared under *stopping* and never under *starting*, while
`dhcpcd.service` and `network-addresses-ens6.service` restarted:

```
stopping:   … network-setup.service …
starting:   … (network-setup.service absent) …
restarting: dhcpcd.service, network-addresses-ens6.service, sshd.service …
```

**It was harmless there, for a reason that does not generalise.** ionos's `ens6`
is DHCP-configured, so dhcpcd owns both address and default route and restoring
them is its job; `network-setup.service` had no static configuration to reapply.
The pi is the dangerous case precisely because its address *is* static, so that
unit is the only thing that would have reinstated it.

The check is the same either way and takes one command —
`ip -4 route show default` — but the interpretation differs: on a DHCP interface
a missing route means dhcpcd failed, on a static one it means
`network-setup.service` never ran. Phase 3 rebuilds ionos again for Headscale,
so this recurs until ionos moves to networkd for D14's reasons.

✅ **Confirmed live on the box, 2026-08-06.** The check that was outstanding has
now run, and it settles the question harder than the source reading did:

```
systemd-networkd            active, enabled
network-setup.service       NOT PRESENT — unit does not exist
dhcpcd.service              NOT PRESENT — unit does not exist
/etc/systemd/network/       20-vmbr0-bind.network, 20-vmbr0.netdev,
                            25-microvm-tap.network, 30-vmbr0.network
networkctl                  routable / online, 192.168.178.2 on vmbr0
```

The two units the failure mode is *made of* are not merely inactive on maxdata,
they are absent — so `dhcpcd`-stopped-without-`network-setup` **cannot happen
there**. It is a property of the pi alone.

**This changes what Phase 6 must guard against.** The risk on maxdata is not a
bare interface after activation; it is a `systemd-networkd` restart that
reconfigures `vmbr0` — a bridge carrying the microVM taps — from edited unit
files. Watch the `.network`/`.netdev` set above, and treat a change to
`20-vmbr0.netdev` as the dangerous one, since renaming or re-creating a netdev
is what drops the addresses riding on it. Note also that 6.2 deletes
`25-microvm-tap.network`'s reason to exist, so that file goes with the microVMs.

Consequences for this phase, none of which change:

- A dead-man reboot is **not optional** here; it is what recovered the pi, and
  it is cheap insurance regardless of which stack maxdata runs.
- Judge success **after a reboot**, not after `test`. A clean boot runs
  `network-setup.service` properly and is the only honest verification.
- Check the **default route** explicitly, not just pingability from the same
  subnet: `ip -4 route show default` plus an outbound connection.

Also: disabling DHCP silently disables IPv6. `dhcpcd` leaves `accept_ra=0`,
`addr_gen_mode=1` (none) and `autoconf=0` behind, so the kernel generates no
address at all — not even a link-local — until the host reboots. Declare
`net.ipv6.conf.<iface>.accept_ra = 2` on any host that both forwards and needs
SLAAC, because a forwarding host ignores RAs at the default `1`.

The pi at Winkel is an independent second path in: it is on the overlay and does
not depend on maxdata, so it can reach maxdata by LAN IP even if maxdata's
overlay client fails. A smart plug on maxdata's power removes the need for
anyone to be physically present for a power cycle.

ZFS pools are never touched by any step in this phase.

## 6.6 Exit criteria

- [x] maxdata decrypts `secrets/k3s.yaml` with its own **host** key — ✅
      **re-confirmed on the box immediately before the deletion**, as required.
      Identity `age1ewxty…` derived from `/etc/ssh/ssh_host_ed25519_key`;
      `k3s.yaml → cc44af01…` and `common.yaml → ffbea925…`, exit 0, checked
      against **`origin/multi-site`** rather than the box's local clone, which
      was five commits stale at the time. Re-proven a **third** time after
      `sops updatekeys` dropped the three microVM recipients — same plaintext
      hash, so the re-key is safe
- [x] microVMs stopped and their images removed — all three `microvm@` units
      gone, zero `cloud-hypervisor` processes, the `microvm` user removed, and
      `/var/lib/microvms` (**67 G**) deleted
- [x] maxdata reachable from both sites after the reboot — verified from Brink
      over the LAN route, and present on the overlay at `100.64.0.5` with all
      five nodes visible. `booted-system == current-system`
- [x] `zpool status` clean — both pools `ONLINE`, `zpool status -x` reports
      "all pools are healthy", 12 ZFS mounts, **all 24 `pre-multi-site`
      snapshots intact**, zero failed units
- [ ] ~~ARC max raised and confirmed via `arc_summary`~~ — **withdrawn, not
      skipped.** See 6.3: the freed RAM is deliberately kept as k3s headroom
      rather than given to ARC. RAM reclaim *was* verified (`available`
      3.4 GB → 28 GB)
- [x] **Added:** maxdata resolves through its own site resolver — ✅ **verified
      across a cold boot with no manual intervention.** It was the last host at
      either site still on the deprecated `dns.servers`. ⚠️ This exposed a
      genuine defect — see `systemd-resolved never re-elects` in the decision
      log — which had to be fixed before the criterion could honestly be met.
      Post-boot: resolver `192.168.178.3`, `paperless.mvissing.de →
      192.168.178.240`, `doubleclick.net → 0.0.0.0`,
      `winkel-pi.mesh.mvissing.de → 100.64.0.3`

⚠️ **"all datasets mounted" was dropped from the criteria as unmeetable, and
that is a finding rather than a pass.** Three datasets are `mountpoint=legacy`
with no `fileSystems` entry and so are never mounted: `tank/fast-backup/k8s`,
`tank/fast-backup/vms` and `tank/k8s/timemachine`. All three predate this phase.
The last one matters — see the decision log; the 689 G of Time Machine data is
in the *parent* dataset behind a shadowing directory.

## 6.7 How the deploy actually went

Recorded because the sequence worked and the next risky host should reuse it.

```
nixos-rebuild build        # safe, no activation. ~2 min.
nixos-rebuild dry-activate # THE decisive check — read before doing anything
shutdown -r +12            # dead-man: lands on the OLD generation
nixos-rebuild test         # bootloader untouched, so a power cycle still reverts
<verify>                   # address, default route, OUTBOUND, DNS, overlay
shutdown -c
nixos-rebuild boot ; reboot
<verify again>             # only a clean boot is honest (6.5)
```

**`dry-activate` is the step that made this safe** and it belongs in 6.5's
sequence permanently. It reported, before anything ran:

```
would stop: microvm@k3s-node{1,2,3} + 9 more units, microvms.target
would remove user 'microvm'
would reload: dbus-broker.service, firewall.service, systemd-networkd.service
```

**`systemd-networkd` is *reloaded*, not restarted** — which is precisely the
hazard 6.5 warns about *not* firing. Knowing that in advance turned the riskiest
change in the phase into a routine one. It also confirmed `sops` still resolved
mid-activation, under the host key, before any image was touched.

Two verification lessons, both learned by getting them wrong:

- **Four probe commands were broken, and each one produced a convincing false
  reading.** `pgrep -f "nixos-rebuild build"` matched its own invocation and
  reported a finished build as still running; `dig` is **not installed** on
  maxdata, and with stderr redirected its absence read as "DNS returned
  nothing"; `uptime -p` is unsupported by this build, so a reachability loop
  reported a healthy rebooted host as unreachable; and piping a file into `ssh`
  while also using a heredoc silently transferred **nothing** (the tell was the
  empty-input hash `e3b0c442…`). In every case the box was correct and the
  instrument was wrong. **Verify the instrument before believing a bad result**
  — never redirect stderr on a probe.
- **`df` immediately after `rm` still showed the old figure**, because ZFS frees
  asynchronously. The reclaim was real; the measurement was premature.

---

# Phase 7 — Fresh cluster

✅ **Cluster is up — all four nodes `Ready` 2026-08-07.** Only the 24 h etcd
soak remains. `modules/system/k3s-cluster.nix` derives every node's role, node
IP and zone from `networkConfig.hosts`.

| Host | role | `--node-ip` | zone | joins | `flannel.1` |
|---|---|---|---|---|---|
| ionos | server | `100.64.0.1` | `public` | `--cluster-init` | **1230** ✅ |
| brink-server | server | `100.64.0.2` | `brink` | `https://100.64.0.1:6443` | **1230** ✅ |
| maxdata | server | `100.64.0.5` | `winkel` | `https://100.64.0.1:6443` | **1230** ✅ |
| winkel-pi | **agent** | `100.64.0.3` | `winkel` | `https://100.64.0.1:6443` | **1230** ✅ |

`INTERNAL-IP` is the overlay address on every node, not a LAN one — D3 holds in
practice, not just on paper. Three etcd members across three L3 domains.

⚠️ **One parameterised module, not `k3s-server.nix` + `k3s-agent.nix`.** 6.2
asked for a split by role *and*, in the same sentence, to "parameterise node
role" — contradictory instructions. An agent is a strict subset of a server
(six fewer flags, none added), so a split would duplicate the shared half or
need a third module to hold it, and that module already exists as
`k3s-base.nix`. See the header of `k3s-cluster.nix`.

⚠️ **The local-path provisioner is deliberately absent.** `k3s-node.nix` shipped
one pinned to the dead virtiofs path. A correct `nodePathMap` needs per-node
storage decisions across four genuinely different disks, which is Phase 8's
subject with D6. Phase 7's gate does not mention storage; guessing would ship a
manifest wrong on three nodes of four.

## 7.0 Prerequisites — done 2026-08-07

- ✅ **brink-server added as a recipient of `secrets/k3s.yaml`** (6 → 7). It was
  excluded in Phase 5 because the token then belonged to the cluster Phase 6
  destroyed. ⚠️ **Order was load-bearing**: a host declaring
  `sops.secrets.k3s_token` without being a recipient fails *activation*, and
  brink-server is Brink's DNS and subnet router at the site with nobody in it.
  Recipient first, decrypt proven on the box, `k3sCluster.enable` last.
- ✅ **Token rotated.** The old one belonged to the destroyed cluster *and* had
  been echoed into a session transcript. New value is a fresh
  `secrets.token_urlsafe(48)`.
- ✅ **The `K3S_TOKEN=` prefix removed from the secret.** The value used to be
  literally `K3S_TOKEN=<token>`, so ionos's `tokenFile` took the whole string —
  prefix included — as the token, while the microVMs' sops *template* wrapped it
  a second time into `K3S_TOKEN=K3S_TOKEN=…`. Both landed on the same effective
  token by accident, which is why it worked. Now a raw scalar, consumed only via
  `tokenFile`.
- ✅ **All four hosts decrypt the rotated file with their own host keys** —
  verified on each box, identical hash `81a7572f…`.

⚠️ **ionos carries stale cluster state and it must be cleared before bring-up.**
It holds **2.7 GB** under `/var/lib/rancher/k3s/agent` and **no `server/db`**,
because it was an *agent* of the old cluster. Starting it as a `--cluster-init`
server on top of another cluster's CA and node identity does not re-initialise —
it fails or resumes. Stop k3s and remove `/var/lib/rancher/k3s` on ionos first.
The other three have no k3s state at all: brink-server and winkel-pi never ran
it, and on maxdata it lived inside the microVMs.

## 7.0.1 Bring-up order

1. `ionos` — clear stale state, then `--cluster-init`, first server.
2. `brink-server` and `maxdata` join as servers.
3. `winkel-pi` joins as agent.

Per-node flags:

- `--node-ip=<overlay IP>` and `--flannel-iface=<overlay iface>` (D3)
- **Pinned flannel MTU** — ⚠️ **corrected 2026-08-07: there is no
  `--flannel-mtu` flag.** Checked against the installed **k3s v1.35.6+k3s1**;
  `k3s server --help` matches zero MTU options (only `--flannel-backend`,
  `-iface`, `-conf`, `-cni-conf`). Flannel *derives* its MTU from
  `--flannel-iface` minus backend overhead, so naming the interface is the only
  lever — and naming the wrong one is D3's blackhole.
  `tailscale0` measures **1280 on all four nodes**, so `flannel.1` must come up
  at **1230** (VXLAN −50). **This is a prediction to verify, not an
  assumption**, and the old cluster is the control that proves the mechanism: it
  rode `wg0` at MTU 1420 and its `flannel.1` was **1370** — exactly 1420 − 50.
  Check `ip link show flannel.1` on every node after bring-up, then the
  large-payload ping (`ping -M do -s 1400`) across sites.
- `--node-label=topology.kubernetes.io/zone=<brink|winkel|public>`
- etcd WAN tuning (D4), values from Phase 2 measurements
- `--disable=servicelb,traefik,local-storage` (unchanged intent)
- Cluster/service CIDRs IPv4-only (D1)
- ionos keeps `--node-taint=edge=true:NoSchedule`; note the zone label changes
  from the current `external` to `public`, so any Pulumi nodeSelector must agree

## 7.1 Close the internet-facing k3s ports ✅ done 2026-08-07

✅ **Fixed and deployed to ionos.** The ports now live on the overlay interface
only, via `networking.firewall.interfaces.${config.services.tailscale.interfaceName}`
in `k3s-base.nix` — referencing the option rather than hardcoding `tailscale0`,
so it cannot drift.

**Measured before:**

```
-A nixos-fw -p tcp -m tcp --dport 6443  -j nixos-fw-accept     <- no -i, so ens6 too
-A nixos-fw -p tcp -m tcp --dport 2379  -j nixos-fw-accept
-A nixos-fw -p tcp -m tcp --dport 2380  -j nixos-fw-accept
-A nixos-fw -p tcp -m tcp --dport 10250 -j nixos-fw-accept
```

**After:** all four carry `-i tailscale0`, and the global surface is exactly
`22/80/443` TCP plus `443/3478/41641/56527` UDP.

⚠️ **The important nuance, which the original text understated.** Nothing was
ever actually reachable — an external probe confirmed all four ports filtered
*before* the fix as well. They were held shut **solely by the IONOS Cloud
firewall**, a web-panel control that lives outside this repo and is invisible
from inside the VPS. So this was one undocumented, out-of-band control standing
between the public internet and etcd, with no second layer behind it: a latent
exposure rather than an active breach, and exactly the kind that survives a
panel misclick.

✅ **The "ionos cannot build" warning does not apply to changes like this — and
the decision-log entry deserves this qualification.** `nixos-rebuild dry-build`
reported **4 trivial derivations** (`manifest.json`, `activate`, `dry-activate`,
the system derivation) and the switch added only firewall units. The 20-minute
sshd starvation happened during the **26.05 → 26.11 upgrade**, where
`sops-install-secrets` compiled from source and ran its test suite. With nixpkgs
unmoved, a config-only change on ionos is seconds. Measure with `dry-build`
before assuming the expensive path.

Consequence: the elaborate remedy — wire `brink-server` up as a push-deploy host
with `--target-host` — was **not needed** and was not done. Worth knowing it is
also not currently *possible*: brink-server cannot SSH to ionos
(`Permission denied (publickey)`), because its only key is the GitHub deploy key
`id_brink_server`. Granting it access means adding a `.pub` to
`modules/data/keys/`, which every host reads, and then deploying ionos — so the
bootstrap needs an ionos deploy either way.

**Verified after the switch:** `headscale`, `tailscaled` and `sshd` all active;
`headscale.mvissing.de/health` → **HTTP 200**; 4 nodes online; maxdata still
reaches ionos over the overlay (10–30 ms); and an external probe still shows
only `22/80/443` open. `dry-activate` had predicted precisely this — *"would
reload the following units: firewall.service"* and nothing else.

### Original analysis

`modules/system/k3s-base.nix:19-29` puts 6443, 10250, 2379 and 2380 in the
**global** `allowedTCPPorts` list, and 8472 in the global UDP list. NixOS global
firewall lists apply to *all* interfaces, including ionos's public `ens6`. The
per-interface block at `hosts/nixos/ionos/default.nix:51-55` does **not** fix
this — `networking.firewall.interfaces.<if>.allowedUDPPorts` is *additive*, so an
empty list subtracts nothing.

Fix: remove these from the global list in `k3s-base.nix` and declare them
per-interface on the overlay interface only.

## 7.2 Exit criteria

- [x] **4 nodes `Ready` with correct zone labels** — `brink`, `public`,
      `winkel`, `winkel` respectively; three servers with etcd, winkel-pi as the
      sole agent
- [ ] ~~etcd stable for 24 h with no leader elections~~ — ⚠️ **WAIVED
      2026-08-07**, as Phase 3.5's 24 h sampling was. Snapshot taken at close
      instead: `/healthz` → `ok`, all three members `Ready`, and **exactly 1
      election event** in the journal — the initial one, which is what a fresh
      cluster should show.

      **What waiving costs, stated plainly.** D4 called this gate "the empirical
      test" for `heartbeat-interval=500` / `election-timeout=5000`. Those values
      are not guesses — they sit **73×** above Phase 2's measured direct p99 of
      6.8 ms and **14×** above the worst single echo in six hours — but a
      sustained soak is the only thing that would catch a *rare* uplink stall
      that the sampling window missed. Not running it means the tuning is
      justified by measurement but unproven under time.

      **How it would show up later, and what to do.** Spurious elections appear
      as the count below rising:
      ```sh
      journalctl -u k3s -b | grep -icE 'lost leader|leader changed|elected leader'
      ```
      Baseline is **1**. A number climbing over days means the WAN tuning is
      still too tight; raise `election-timeout` first. Worth a glance whenever
      the cluster misbehaves, since a partition here presents as apiserver
      flapping rather than as an obvious network fault.
- [x] **Cross-site pod-to-pod at full MTU** — pod on brink-server ↔ pod on
      maxdata. Pod `eth0` MTU is **1230** end-to-end, ping 3/3 at **5.0–5.4 ms**
      (matching Phase 2's p50 of 5.8 ms), and a **20 MB TCP transfer arrived
      byte-exact at 20 971 520**.
      ⚠️ **The bulk transfer is the test that matters, not the ping.** D3's
      failure mode is TCP with DF stalling while ICMP sails through, so a
      1400-byte ping "succeeding" proves only that fragmentation works — it
      cannot detect the blackhole. Note also **busybox `ping` has no `-M do`**,
      so the intended cliff test silently printed usage and exited 1; the pod
      MTU plus a byte-exact bulk transfer replace it
- [x] Only 22/80/443 open on ionos from outside — ✅ **7.1 done 2026-08-07**,
      verified by an external probe before *and* after, plus the host firewall
      now scoping the k3s ports to `tailscale0`. Re-check after the cluster is
      up, since a running k3s can add rules of its own

---

# Phase 8 — Storage and site affinity

The largest Pulumi change. Everything here is in `homelab-k8s`.

## 8.1 MetalLB

Two `IPAddressPool`s with `L2Advertisement` node selectors:

- Brink: `192.168.1.240-250`, advertised by brink-server (and pi if it were there)
- Winkel: `192.168.178.240-250`, advertised by maxdata and pi

**Pre-check:** confirm `192.168.1.240-250` is actually free before defining the
Brink pool. Phase 0 found seven DHCP clients above `.199` (`.200`, `.212`, `.225`,
`.231`, `.233`, `.244`, `.253`) — `.244` is inside the pool. The UDM SE range was
shrunk to `.6–.199`, so they migrate out on lease renewal, but old leases stay
valid until they expire. Either wait out the lease time or forget the leases in
the UniFi UI.

**Pin every LoadBalancer IP.** Current live assignments, captured in Phase 0:

| Now | Service | Pinned? |
|---|---|---|
| `.10` (+ `::10`) | `traefik/traefik` | ❌ auto — and the six ionos DNAT rules depend on it |
| `.11` | `monitoring/loki-external` | ✅ `monitoring/loki.ts:157` |
| `.12` | `default/timemachine` | ✅ `apps/timemachine.ts:221` |
| `.13` | `unifi/unifi` | ❌ auto |
| `.14` | `adguard/adguard-dns` | ❌ auto — this is what clients resolve against today |
| `.15` | `homeassistant/mosquitto` | ✅ `apps/mosquitto.ts:173` |

Traefik landing on `.10` is first-come luck from the `.10–.20` pool, not
configuration (`infrastructure/traefik.ts:32` has the pin commented out). All six
move to the new per-site pools.

Time Machine hardcodes its own LB IP into the container environment
(`apps/timemachine.ts:116-118`, `ADVERTISED_HOSTNAME`) — the pin and the env var
must change together.

The Alloy log-shipping target on maxdata is also hardcoded to `192.168.178.11`
(`hosts/nixos/maxdata/monitoring.nix:67`) and must move with the Loki pin.

## 8.2 Site pinning

Every `local-path` PVC becomes genuinely node-local. Remove the shared-virtiofs
assumption at `databases/postgresql.ts:291`.

| Workload | Site | Storage |
|---|---|---|
| Postgres (CNPG) | **both** — one instance per site | local-path on `/fast/k8s` (maxdata) and `/var/lib/k8s` (brink-server). ⚠️ Scaled to `instances: 2` with zone anti-affinity so Authentik survives maxdata |
| Paperless (media + data + consume) | winkel — maxdata | NFS 300 Gi + local-path |
| UniFi (`unifi-data`, `unifi-mongo`) | winkel — maxdata | local-path; amd64 + privileged already |
| Time Machine | winkel — maxdata | NFS 3 Ti; hostNetwork, amd64 |
| Home Assistant | brink — brink-server | brink-server local NVMe |
| Mosquitto | brink — brink-server | brink-server local NVMe |
| Authentik (server, worker, media, own Redis) | **brink — brink-server** | brink-server local NVMe |
| Redis | winkel — maxdata | local-path (regenerable) |
| Monitoring (Prometheus/Loki/Tempo) | winkel — maxdata | local-path, large PVCs |
| ~~Authentik~~ | ~~winkel — maxdata~~ | **Moved to Brink** — see the row above. It gates forward auth for every ingress at both sites, so pinning it to maxdata made one site's outage a total auth outage |

Home Assistant keeps `hostNetwork: true` for mDNS discovery — on brink-server it sees
Brink's segment, which is where every smart-home device now lives. No reflector,
no cross-site mDNS, and the Matter commissioning caveat flagged twice in
`docs/k3s-Migration.md:77-79` does not arise.

## 8.3 Deletions

- **MongoDB** (`databases/mongodb.ts`) — 50 Gi PVC, **zero consumers**. UniFi was
  its only user and explicitly moved to a bundled Mongo (`apps/unifi.ts:7`).
- **AdGuard** (`apps/adguard.ts`) — replaced by native AdGuard in Phase 4.
- **Time Machine namespace** — `apps/timemachine.ts` sets no `metadata.namespace`
  on its ConfigMap (`:17`), PVC (`:67`), Deployment (`:87`) or Service (`:217`),
  so everything lands in `default`. Give it its own namespace like every other
  app.

## 8.4 Exit criteria

- [x] Both MetalLB pools defined with node selectors — **deployed**, plus
      `autoAssign: false` so an unpinned service fails visibly
- [x] Every LoadBalancer service has an explicit pinned IP
- [x] Every `local-path` PVC has a site pin — tightened to a **node** pin, since
      Winkel has two nodes
- [x] MongoDB and in-cluster AdGuard removed
- [x] Time Machine out of `default`

Added during the phase, and not in the original list:

- [x] `local-path-provisioner` deployed with a per-node `nodePathMap` — k3s runs
      `--disable=local-storage`, so without it every `local-path` PVC in the
      repo sits Pending forever. Bind proven end-to-end on maxdata
- [x] Authentik no longer depends on maxdata (see the decision log)

Still open:

- [ ] A PVC proven to bind on **brink-server** — the path was corrected to
      `/var/lib/k8s/local-path` but never exercised
- [ ] Home Assistant and Mosquitto data copied from maxdata's NFS to
      brink-server **before either starts**; an empty config makes Home
      Assistant run its new-install wizard rather than fail
- [ ] `tank/k8s/timemachine` — 689 G moved into the real dataset
- [ ] UDM SE DHCP range confirmed at `.6–.199` before Mosquitto takes
      `192.168.1.241`

⚠️ **Do not run an untargeted `pulumi up` to close this phase.** The full plan
is 281 resources, i.e. the whole estate, and cert-manager is still HTTP-01
while ionos's DNAT points at the dead `192.168.178.10` — so every hostname
would fail validation against **production** Let's Encrypt at once and burn the
budget Phase 9's wildcard needs. Phase 8's own resources were applied with
`--target '**metallb**' --target '**local-path**' --target-dependents`. The
remaining code deploys with its workloads in Phase 10, after the restores.

---

# Phase 9 — Ingress and certificates

## 9.1 Traefik on ionos

Replace ionos's DNAT block (`hosts/nixos/ionos/default.nix:57-90`) with a
`hostNetwork` Traefik pinned to ionos, terminating TLS there. This preserves real
client IPs, which the current `MASQUERADE -o wg0` (`:77`) destroys for all public
traffic.

Internal Traefik stays as a per-site LoadBalancer for LAN access.

## 9.2 cert-manager DNS-01

Switch both `ClusterIssuer`s from HTTP-01 (`infrastructure/cert-manager.ts:72-80`)
to DNS-01 via the community `cert-manager-webhook-ionos`. Issue a wildcard
`*.mvissing.de` to cut issuance volume. Restore the Phase 1 cert secrets
**before** creating any Ingress:

```sh
kubectl apply -f ~/backup/cert-secrets.yaml
cmctl status certificate <name>
```

Validate against staging first (`letsencrypt-staging` already exists,
`cert-manager.ts:95-133`).

## 9.3 Fix the exposed Traefik API

`infrastructure/traefik.ts:57` sets `api.insecure: true` and `:78` sets
`expose.default: true` on entrypoint `traefik` (port 9000). The unauthenticated
Traefik API is therefore reachable on the LoadBalancer IP at `:9000`, bypassing
the Authentik-protected `traefik.mvissing.de` route entirely. Either drop
`api.insecure` or stop exposing 9000 in the Service.

## 9.4 Exit criteria

- [ ] Wildcard `*.mvissing.de` issued from production Let's Encrypt
- [ ] Real client IPs visible in Traefik access logs
- [ ] `:9000` no longer reachable from the LAN
- [ ] All hostnames resolve and serve valid TLS from both sites and off-net

---

# Phase 10 — Workloads and bootstrap

Layered redeploy in dependency order, adapted from
`docs/k3s-Migration.md:299-322`:

1. Foundation — cert-manager, MetalLB, reflector
2. Cert restore
3. Traefik (both instances)
4. CNPG operator
5. Shared Postgres cluster
6. Per-app databases and roles
7. Authentik → **then create the outpost token and the two OAuth applications**
8. Applications — Paperless, Homepage, UniFi, Home Assistant, Mosquitto, ntfy
9. Monitoring — Prometheus, Loki, Tempo, Grafana, Alloy, unpoller
10. Infrastructure extras — GitHub ARC

Stage with `pulumi up --target`.

Restores:

- Postgres: `bootstrap.initdb`, then `kubectl exec ... psql < postgres-all.sql`.
  Do **not** use `bootstrap.recovery` — there is no object store to recover from.
- UniFi: upload the `.unf` via the web UI, then re-adopt switches and APs at
  Winkel.
- Home Assistant: **fresh install on brink-server.** Re-commission Matter and HomeKit
  devices at Brink. Add IP-addressable integrations (Shelly, WLED, Hue,
  ESPHome, UniFi) by discovery on the Brink segment.

The six manual secrets from Phase 1.1 are re-created here in order — items 1–3
require Authentik to be up first, which is why step 7 is a hard gate.

## 10.1 Exit criteria

- [ ] All applications reachable and authenticating via Authentik
- [ ] Paperless documents present and searchable after `document_index reindex`
- [ ] UniFi devices adopted at Winkel
- [ ] Home Assistant discovering Brink devices; Matter devices commissioned
- [ ] All six bootstrap secrets stored in sops

---

# Phase 11 — Backups that actually exist

Today `homelab-k8s` has **zero** backup automation. Every hit for
`barmanObjectStore`, `ScheduledBackup`, `CronJob`, Velero, restic, VolSync or
`pg_dump` is a comment. The stated strategy is out-of-band sanoid/syncoid on
maxdata (`databases/postgresql.ts:286-289`), which is crash-consistent only and
single-site.

Add:

1. **CNPG WAL archiving** to object storage. A Hetzner Storage Box already
   exists (`u499100.your-storagebox.de`,
   `modules/profiles/personal-ssh.nix:42`). Gives PITR instead of
   crash-consistent snapshots.
2. **brink-server → maxdata replication.** brink-server's local-path PVs — including Home
   Assistant — sit on a single unmirrored NVMe. Scheduled ZFS send/receive over
   the overlay into `tank`.
3. **sanoid coverage for `tank/daten-familie`** (1.46 T) and `tank/k8s`. Neither
   has any today (`hosts/nixos/maxdata/zfs.nix:28-39`); a template exists in
   `hosts/nixos/maxdata/SMB_SETUP.md:314-358` but was never applied. The other
   `daten-*` datasets are empty. `tank/timemachine-*` does not exist.
4. **NFS-tier backups.** Cheaper than assumed — the whole tier is under 4 G
   (Paperless media is 3.4 G against a 300 Gi request). Currently protected only
   by RAIDZ1.
5. **Syncoid target retention.** `tank/fast-backup/k8s` holds **13 690**
   snapshots: sanoid prunes the source, nothing prunes the target. Add a
   retention policy, or the target grows without bound.
6. **`fast` has no redundancy** — a single NVMe vdev carrying `/`, `/nix` and
   every local-path PV. `fast/root` is in sanoid but replicates nowhere; only
   `fast/k8s` is syncoid'd to `tank`. Worth extending to `fast/root`.

## 11.1 Exit criteria

- [ ] CNPG WAL archiving verified; a PITR restore rehearsed into a scratch cluster
- [ ] brink-server → maxdata replication running and verified by restoring a PV
- [ ] `sanoid --monitor-snapshots` clean for all `tank/daten-*`
- [ ] A restore has been performed from a real backup, not a snapshot

---

# Phase 12 — Monitoring

- Node, ZFS and smartctl exporters on all four hosts (maxdata already has all
  three: 9100, 9134, 9116 — `hosts/nixos/maxdata/monitoring.nix:107-126`).
- Overlay control-server metrics.
- Cross-site blackbox probes: latency, packet loss, overlay path direct-vs-relay.
- Per-site alert routing via ntfy.
- **External dead-man's switch.** In-cluster alerting cannot tell you the cluster
  is down. Today ZED, smartd and the hourly `zfs-health-check` all only write to
  the journal — `hosts/nixos/maxdata/zfs.nix:93` is a literal
  `# Add notification here` TODO. Add a healthchecks.io ping or ntfy heartbeat
  from ionos, running **outside** k3s.

## 12.1 Exit criteria

- [ ] All four hosts scraped
- [ ] Cross-site probes graphed
- [ ] Simulated cluster outage triggers the external dead-man's switch
- [ ] A simulated ZFS degradation produces an actual notification, not a journal line

---

# Phase 13 — Cleanup

1. Retire the FritzBox WireGuard server entirely — not just the ionos tunnel.
   That means:
   - ionos's `wg0` peer block (`hosts/nixos/ionos/default.nix:93-109`) and the
     unmanaged key files at `/home/max/.wireguard/private_key` and
     `preshared_key`, which currently make ionos non-reproducible from the flake.
   - The boot-ordering workaround at `:143-147`, which exists only because the
     peer endpoint is a MyFRITZ! DDNS name.
   - **All** FritzBox VPN connections under Internet → Freigaben → VPN
     (WireGuard), once Phase 3.3 has confirmed an overlay equivalent for each.
     This frees `192.168.178.201+`.

   Do this only after the overlay has run alongside it long enough to trust —
   it is the last remaining way into Winkel if the overlay fails.

   ⚠️ **Interim mitigation, do this now rather than at Phase 13.** Phase 2b
   considered moving those two key files into sops and **dropped it** (2b.3
   item 3): it is declarative plumbing for material this phase deletes, and it
   means editing the config of the only route into Winkel for no lasting gain.
   The narrow risk it addressed is real though — if ionos's disk died before
   this phase, `private_key` and `preshared_key` would be unrecoverable and the
   tunnel unrebuildable. **Copy both files into 1Password.** A human action, no
   plumbing, and Phase 3 retires the risk entirely by giving Winkel a second
   independent path.
2. (Moved to **Phase 3**, which rebuilds ionos anyway) Standardise ionos's sops age key onto a **host** key
   (`/etc/ssh/ssh_host_ed25519_key`) instead of `/home/max/.ssh/id_ed25519`
   (`:131`).
3. Delete `docs/proxmox/` (describes a Proxmox-on-NixOS design that no longer
   exists) and `docs/k3s-Migration.md` (superseded by this document).
4. Update `docs/k3s-ipv6-ingress.md` or delete it — it describes a dual Traefik
   design with a `traefik-external` DaemonSet that does not exist, and a
   dual-stack ingress that D1 removes.
5. Rewrite `README.md` and `CLAUDE.md` in `homelab-k8s`. Current known errors:
   - Claims cert-manager uses DNS-01; the code was HTTP-01 (`CLAUDE.md:51`)
   - Claims AdGuard uses hostPort 5353 pinned to the Pi (`README.md:14,25,91`);
     no such config exists
   - Claims Proxmox at `192.168.178.97` (`README.md:35`); code uses `.2`
   - Grafana PVC listed as 2 Gi (`monitoring/index.ts:55`); actual is 10 Gi
   - Paperless media listed as 500 Gi (`apps/paperless.ts:740`); actual is 300 Gi
   - Claims Diun and Nova are deployed (`monitoring/index.ts:37-38`); neither exists
   - Claims MongoDB is in active use (`CLAUDE.md:54`); it has no consumers
6. Remove stale references to `k3s-node1/2/3` and `pi-k3s` throughout both repos.
7. **Reclaim dead storage on maxdata**, all identified in Phase 0:
   - `tank/fast-backup/vms/*` — 68.6 G of Proxmox-era zvols (`vm-100-*`,
     `vm-201/202/203-*`, `base-9000-disk-0`) with 375 snapshots on one of them.
     Nothing references them.
   - `/fast/k8s/migration` — 156 M of residue from an earlier migration
     (stale copies of `adguard-*`, `paperless-data`, `redis-data`).
   - `tank/k8s/timemachine` — the dataset exists but is **not mounted**; the
     689 G of real Time Machine data sits in the parent `tank/k8s`. Either mount
     it properly and migrate the data in, or delete the empty dataset. Leaving
     it as-is means no separate quota and no separate snapshot boundary.
   - The stale `Max's MacBook Pro 2025-10-24-181306.incomplete` sparsebundle.
8. Delete the dead `proxmox-api-user` / `proxmox-api-token` entries from
   `Pulumi.default.yaml`.

## 13.1 Exit criteria

- [ ] Old WireGuard tunnel removed; ionos rebuildable from the flake alone
- [ ] Stale docs deleted or rewritten
- [ ] `grep -r k3s-node` returns nothing meaningful in either repo

---

## Open items

- **Resolve Pulumi's secrets provider.** *(From Phase 2b work item 4, parked
  here 2026-08-06 — real, but not boot-critical and not a migration blocker.)*
  `Pulumi.default.yaml` has `encryptionsalt` and 16 `secure:` entries, so
  `PULUMI_CONFIG_PASSPHRASE` is a genuine encryption key and the stored web
  login does **not** substitute for it. Lose it and all 16 values — Authentik
  outpost token, both OAuth pairs, `unpoller-password`, the SMB passwords —
  become unrecoverable ciphertext. Preferred: `pulumi stack
  change-secrets-provider service`, which re-encrypts all 16 under a
  service-managed key, so the passphrase stops existing rather than being
  relocated; no new dependency, since the state backend is already
  `api.pulumi.com`. Then delete both `personal/pulumi-passphrase` and
  `personal/pulumi-token` from `secrets/common.yaml`. Wants a clean tree and a
  fresh `pulumi stack export` first. `personal/pulumi-token` is redundant either
  way — `~/.pulumi/credentials.json` already holds a web login. Not urgent: the
  passphrase currently sits in sops with four recipients.
- **1Password as personal tooling.** *(From Phase 2b work item 6.)* An ongoing
  human task, not a gate. WiFi and router-admin credentials, recovery keys, the
  Let's Encrypt account, IONOS panel logins, the SMB passwords shared with
  Michael and Anna, and copies of the two Macs' `~/.config/sops/age/keys.txt` —
  those are the surviving recipients everything else can be re-keyed from. Host
  age identities are deliberately *not* backed up (2b.1). See also Phase 13
  item 1 for ionos's WireGuard key files.
- **Brink single-node.** brink-server is the only node at Brink. If it is down, Brink
  loses its subnet router and primary DNS. Accepted because you are physically
  there. Revisit if you spend extended time away.
- **Time Machine across the WAN — now the *only* case.** Phase 0 found 689 G
  belonging to `max` and **zero bytes** for Anna and Michael; they have never
  backed up. So "Winkel Macs back up locally at LAN speed" describes nobody. The
  entire Time Machine workload is your Mac at Brink writing SMB sparsebundles
  across the WAN, which corrupts periodically and takes days for a full backup.
  Recommended: local Time Machine to a USB disk at Brink plus a restic/borg push
  of important directories to maxdata. Decide before Phase 8 — it determines
  whether the Time Machine pod is worth keeping at all.
- **`tank/timemachine-*` — resolved.** Those datasets do not exist despite
  `setup-smb-datasets.sh:13-24`. Nothing to preserve. The live data is under
  `/tank/k8s/timemachine`, in the *parent* dataset — see Phase 13 item 7.
- **maxdata has no ULA IPv6.** `networkConfig.staticIPv6s.maxdata`
  (`modules/data/network-config.nix:52`) is defined but never applied — only the
  microVMs reference `staticIPv6s`. D1 removes the need, but confirm nothing else
  depended on it.
