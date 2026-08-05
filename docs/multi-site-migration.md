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
| 2 | Overlay spike | 🔄 decided, 24 h RTT pending | 2026-08-05 | **Headscale + Tailscale** — see [`overlay-evaluation.md`](./overlay-evaluation.md). Read the sampler CSVs after 2026-08-06 17:26, finalise D4, then tear down (§9) |
| 2b | Secret management (1Password) | not started | | new — see D11 |
| 3 | Overlay rollout | not started | | |
| 4 | DNS | not started | | |
| 5 | brink-server + pi relocation | not started | | pi move deadline: before Phase 6 |
| 6 | maxdata microVMs out | not started | | ⚠️ first irreversible step |
| 7 | Fresh cluster | not started | | |
| 8 | Storage and site affinity | not started | | |
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
| Secret split (vault vs on-host) | 1Password = vault; sops-nix = boot-critical delivery (D11) | Phase 2b |
| Cross-site RTT / jitter | ~5.5 ms direct, ~24 ms relayed via ionos — **24 h figure still pending** | Phase 2 → feeds D4 etcd tuning |
| Overlay path (direct vs relayed) | **Direct**, over native IPv6. Asymmetric: brink→winkel over IPv6, winkel→brink over CGNAT IPv4 | Phase 2 |
| Overlay MTU → flannel MTU | overlay **1280** → flannel **1230** (VXLAN −50) | Phase 2 → D3 |
| IONOS Cloud firewall | **default-deny, only 22/80/443 inbound** — invisible from inside the VPS; the control plane needs an explicit opening | Phase 2, 2026-08-05 |
| Control-plane TLS | **mandatory** — plain HTTP on an alternate port wedges clients permanently after any control outage | Phase 2 |
| `ip_forward` on subnet routers | `0` on both pi and maxdata; neither overlay sets it — must be declared | Phase 2 |
| Cold start needs the control server | a host rebooting while ionos is unreachable loses the overlay entirely (both products) | Phase 2 → Phases 6, 7, 13 |
| UniFi OS Tailscale app | **no first-party app found** — §2.2/§3.2 premise looks wrong; third-party pkg only, **unverified** | Phase 2 |
| Brink DHCP range | `192.168.1.6-.199` — shrink from auto `.6-.254` | UDM SE, 2026-08-05 |
| Winkel DHCP range | `192.168.178.20-.200` — already clear, no change | FritzBox, 2026-08-05 |
| Overlay IPs per host | *pending* | Phase 3 → `networkConfig.hosts.*.overlayIPv4` |
| ionos → home RTT (existing wg0) | ~13 ms | Phase 0, `ping` from ionos |
| Winkel WAN IPv6 prefix | `2a00:6020:b481:e300::/56` — record only, never depend on it (D2) | FritzBox, 2026-08-05 |
| UDM SE static routes | present and configurable — Phase 3 unblocked | UDM SE, 2026-08-05 |
| FritzBox static routes | table present, empty, configurable | FritzBox, 2026-08-05 |
| Address availability | `192.168.178.3`, `.240-.250`, `192.168.1.2`, `192.168.1.240-.250` all free — verified on the wire | Phase 0, 2026-08-05 |
| k3s-pi current location | Brink, `192.168.1.90` (DHCP) — must still move to Winkel | Phase 0, 2026-08-05 |
| FritzBox VPN peers | `192.168.178.201/32`, `.202`, … — FritzBox is the WireGuard *server* today | FritzBox, 2026-08-05 |
| Effective ionos↔home throughput | ~3 MB/s | Phase 0, scp over wg0 |
| Winkel MetalLB pool | `192.168.178.240-250` | Phase 0 address plan |
| Brink MetalLB pool | `192.168.1.240-250` | Phase 0 address plan |
| brink-server LAN IP | `192.168.1.2` | Phase 0 address plan |
| k3s-pi LAN IP (at Winkel) | `192.168.178.3` | Phase 0 address plan |

---

## Target topology

| Host           | Site       | Network              | Router | Role |
|----------------|------------|----------------------|--------|------|
| `brink-server` | **brink**  | `192.168.1.0/24`     | UDM SE | k3s **server** (etcd) · site DNS · subnet router · Home Assistant · user-facing workloads |
| `maxdata`      | **winkel** | `192.168.178.0/24`   | FritzBox | k3s **server** (etcd) · ZFS · NFS/SMB · Paperless · UniFi · Time Machine |
| `k3s-pi`       | **winkel** | `192.168.178.0/24`   | FritzBox | k3s **agent** · site DNS · subnet router · out-of-band anchor |
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
- `k3s-pi` — Raspberry Pi 4, PoE+ HAT, USB-SATA boot disk
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
| **D4** | Tune etcd for WAN | Three members across two consumer uplinks plus a VPS. Defaults (100 ms heartbeat / 1000 ms election) cause spurious leader elections. Target `heartbeat-interval=500`, `election-timeout=5000`, tuned to Phase 2 RTT. |
| **D5** | One MetalLB L2 pool per site; every LB IP pinned | L2 mode requires a shared segment, which no longer holds. Today Traefik, `adguard-dns` and UniFi are unpinned and will drift on rebuild. UDM SE DHCP defaults to `.6–.254` and must be shrunk to free a pool. |
| **D6** | No cross-site replicated storage | Longhorn/Ceph over consumer uplinks is a reliability trap. Every `local-path` PVC gets an explicit site pin. `databases/postgresql.ts:291` (`// can run on any k3s node since /mnt/k8s-fast is shared via virtiofs`) becomes false the moment maxdata is a real node. |
| **D7** | hostNetwork Traefik on ionos | Today `iptables DNAT` + `MASQUERADE -o wg0` (`hosts/nixos/ionos/default.nix:63-77`) hides every public client IP from Traefik. |
| **D8** | cert-manager DNS-01 via IONOS webhook | Domain stays at IONOS (`ns*.ui-dns.*`). Needs the community `cert-manager-webhook-ionos` rather than a built-in solver. Removes the inbound-port-80-per-hostname dependency and enables a wildcard, cutting issuance volume. Note `CLAUDE.md:51` already falsely claims DNS-01; the code is HTTP-01 (`infrastructure/cert-manager.ts:72-80`). |
| **D9** | AdGuard native on brink-server + pi | Per above. Overlay DNS layered on top for node names. Split-horizon for `*.mvissing.de`. |
| **D10** | Pi lives at Winkel | Brink already has an always-on x86 node. Winkel's only machine is the unattended one — with the pi there, a `nixos-rebuild` on maxdata does not simultaneously kill Winkel's DNS, subnet router and your only route in. Cost: Brink becomes single-node for site infra. |
| **D11** | 1Password is the vault; sops-nix stays the on-host delivery for boot-critical secrets | 1Password becomes the source of truth for everything a human touches, and for disaster recovery. But secrets a host needs *at boot* — k3s token, overlay keys — must decrypt **offline**. opnix fetches over the network from 1password.com; a host with a broken network config cannot fetch them, which is exactly the situation Phase 6 creates. See Phase 2b. |

---

## Phase overview

**Phases 0–5 are additive and reversible. The first irreversible step is Phase 6.**

| # | Phase | Reversible | Gate |
|---|-------|-----------|------|
| 0 | Groundwork and inventory | read-only | address plan written, both repos tagged |
| 1 | Backups | additive | Postgres restore rehearsed |
| 2 | Overlay spike: Headscale vs NetBird | throwaway | comparison doc + decision |
| 2b | Secret management with 1Password | additive | vault + service account live, split documented |
| 3 | Overlay rollout and site-to-site | additive | unmodified client ↔ unmodified client, both directions |
| 4 | DNS | additive | both sites resolve via local AdGuard, failover verified |
| 5 | brink-server bring-up + pi relocation | additive | Winkel reachable without maxdata |
| 6 | **maxdata: microVMs out** | ⚠️ **irreversible** | maxdata reachable, ZFS intact, 18 GB reclaimed |
| 7 | Fresh cluster | destructive | 4 nodes Ready, etcd stable 24 h, full-MTU cross-site |
| 8 | Storage and site affinity | — | every PVC pinned, every LB IP pinned |
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
| k3s-pi | `192.168.178.3` |

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
| Cross-site RTT and jitter | Feeds D4 etcd tuning | `ping -c 200` + `mtr` across the overlay, both directions, over 24 h |
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
- [ ] **Measured cross-site RTT recorded for D4** — the 24 h window runs to
      **2026-08-06 17:26 CEST**. Read
      `/var/lib/tailscale-spike/rtt-brink-to-winkel.csv` on `k3s-pi` and
      `rtt-winkel-to-brink.csv` on `maxdata`, write the figure into the
      Decision log, finalise D4, **then** tear the spike down per
      `overlay-evaluation.md` §9 (which also closes the IONOS firewall ports
      and removes the spike DNS records)

---

# Phase 2b — Secret management with 1Password

Numbered `2b` rather than renumbering everything downstream. It sits here because
Phase 3 is where the first *new* secrets get created (overlay auth keys), and the
policy should be settled before that.

## 2b.1 The constraint that shapes the design

1Password is the right vault. It is not automatically the right *delivery*
mechanism, and the difference matters here.

`opnix` (`github:brizzbuzz/opnix` — NixOS, nix-darwin and home-manager modules)
authenticates with a **1Password service account token** at `/etc/opnix-token`
and fetches secrets over the network from 1password.com. sops-nix instead
decrypts a file already in the repo, using a key already on disk — **offline, no
network, no external service.**

Two consequences:

1. **The bootstrap secret does not go away, it moves.** The service-account token
   sits unencrypted at `/etc/opnix-token`, exactly as the sops age key does
   today. Neither is worse; both must be placed out-of-band on a new host.
2. **Reachability becomes a dependency.** A host that cannot reach the internet
   cannot fetch its secrets. Phase 6 deliberately rebuilds maxdata's networking
   remotely, and Phase 7 brings up k3s across a fresh overlay — the two moments
   most likely to leave a host without a working network. If the k3s token can
   only arrive over that network, a mistake becomes unrecoverable-without-console
   rather than merely inconvenient.

That is the whole argument for D11's split. It is not a rejection of 1Password.

## 2b.2 The split

| Secret | Home | Why |
|---|---|---|
| Pulumi passphrase + access token | **1Password** | The passphrase is the master key for all 16 Pulumi config secrets. Human-operated, never needed at boot. |
| GitHub PAT, admin passwords, WiFi, recovery keys | **1Password** | Human-facing. |
| `maxPassword` / `michaelPassword` / `annaPassword` (SMB) | **1Password** | Shared with actual humans. |
| The sops **age private keys** and host SSH keys | **1Password** (copies) | Disaster recovery. Today, if a host's disk dies its age identity dies with it. |
| k3s token | **sops-nix** | Needed at every `k3s.service` start. |
| Overlay pre-auth / node keys | **sops-nix** | Needed to bring up the network itself. |
| WireGuard keys (until Phase 13) | **sops-nix** | Currently unmanaged files under `/home/max/.wireguard/` — fixing that is already on the list. |
| Non-boot-critical host secrets | **opnix**, optional | Convenience, once the pattern is proven. |

Rule of thumb: **if the host needs it before the network is up, it decrypts
offline.** Everything else can come from 1Password.

## 2b.3 Work items

1. Add `programs._1password` / `_1password-gui` (both in nixpkgs) to the Macs.
2. **1Password SSH agent** on the Macs, replacing the loose `~/.ssh/id_ed25519`
   handling that currently feeds `ssh-to-age` (`README.md:32-41`). Note the age
   identities themselves still derive from SSH keys — verify the agent's keys can
   still be exported for `ssh-to-age`, or keep a dedicated non-agent key for sops.
3. Create a 1Password vault for the homelab, and a **service account** scoped to
   it. Store the token out-of-band.
4. Move the Pulumi passphrase and token from `secrets/common.yaml` into
   1Password. This is the single highest-value item — the passphrase unlocks
   everything in `Pulumi.default.yaml`.
5. Import every host's age identity and SSH host key into 1Password.
6. Add `opnix` as a flake input and adopt it for one non-critical secret on one
   host as a trial, before relying on it.
7. **Fix ionos's age key source** while here: it uses `/home/max/.ssh/id_ed25519`
   (`hosts/nixos/ionos/default.nix:131`) instead of a host key. Currently
   scheduled for Phase 13; it belongs in this phase.
8. Consider a 1Password service account for the GitHub ARC runners in place of
   the long-lived `githubPat`.

## 2b.4 Exit criteria

- [ ] Homelab vault and service account created; token stored out-of-band
- [ ] Pulumi passphrase and token in 1Password; verified `pulumi config
      --show-secrets` still works from a shell sourcing them
- [ ] All host age identities backed up to 1Password
- [ ] 1Password SSH agent working on the Macs without breaking `ssh-to-age`
- [ ] opnix trialled on one non-critical secret
- [ ] Documented which secrets are offline-decryptable and which are not — the
      Phase 6 and 7 runbooks depend on knowing this

---

# Phase 3 — Overlay rollout and site-to-site

Runs **alongside** the existing FritzBox↔ionos WireGuard tunnel. Nothing is torn
down until Phase 13.

1. Control server on ionos, behind its own TLS (its own hostname under
   `mvissing.de`).
2. Clients on maxdata, pi, laptop, phone. brink-server joins in Phase 5, when it
   exists. Auth keys per Phase 2b.
3. **Interim** subnet routers — see 3.1 for why these are not the final ones:
   - **pi**, currently at Brink on `192.168.1.90`, advertises `192.168.1.0/24`
   - **maxdata** advertises `192.168.178.0/24`
   Approve both routes on the control server.
4. Static routes on both routers — this is what makes unmodified clients
   reachable:
   - UDM SE: `192.168.178.0/24` → maxdata's LAN IP `192.168.178.2`
   - FritzBox: `192.168.1.0/24` → pi's current LAN IP `192.168.1.90`
   Both tables confirmed present and configurable (Phase 0).
5. ACL policy committed to git.
6. GUI deployed (as a pod, per the layering rule — it talks to the control
   server over its API).

## 3.1 Subnet routers are staged, and the pi's move has a deadline

The final assignment is brink-server at Brink and the pi at Winkel (D10). Neither
holds yet: brink-server does not exist until Phase 5, and the pi is still
physically at Brink. So the roles are filled in two steps.

| | Brink `192.168.1.0/24` | Winkel `192.168.178.0/24` |
|---|---|---|
| **Phase 3 (interim)** | pi, at Brink on `.90` | maxdata |
| **Phase 5 (final)** | brink-server `192.168.1.2` | pi, at Winkel on `192.168.178.3` |

This works because the pi happens to be on the Brink segment right now, and
maxdata is permanently on the Winkel one. Each static route is rewritten once, in
Phase 5, and only after the replacement has been verified — so there is no window
without a route.

**The move is not urgent, but it is not optional either. Deadline: before
Phase 6.** That is the phase that rebuilds maxdata's networking remotely, and
D10's entire argument is that a second, independent way into Winkel must exist
first. If maxdata is *also* the Winkel subnet router at that moment, a bad
network generation takes out the box and your route to it simultaneously.

Sequence within Phase 5, to avoid a coverage gap:

1. Build brink-server at Brink, join the overlay, verify it as subnet router.
2. Repoint the UDM SE static route at `192.168.1.2`.
3. Only then move the pi. Brink is covered by brink-server; Winkel is still
   covered by maxdata throughout.
4. Bring the pi up at `192.168.178.3`, verify, repoint the FritzBox route.
5. Withdraw maxdata's route advertisement.

Everything on the pi except its *physical location* can be done at Brink
beforehand: re-image, NixOS config, overlay enrolment, sops/1Password host
enrolment, AdGuard, the k3s agent module. Only three things need it to be at
Winkel — the static `192.168.178.3`, advertising the Winkel subnet, and serving
DNS to Winkel clients. Configure those declaratively before the move and they
take effect when it lands.

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

## 3.4 Exit criteria

- [ ] Unmodified Brink client reaches unmodified Winkel client, and vice versa
- [ ] Phone off-net reaches both sites
- [ ] Path characterised as direct or relayed; RTT recorded
- [ ] GUI reachable and shows all peers
- [ ] Control server config and ACLs committed
- [ ] Every existing FritzBox VPN peer has an equivalent overlay client, verified
      working — the FritzBox tunnel is not retired until Phase 13, so this is
      reversible

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

## 4.1 Exit criteria

- [ ] Both sites resolve via their local AdGuard
- [ ] Blocking verified at both sites
- [ ] Failover to the router resolver verified by stopping AdGuard
- [ ] Split-horizon `*.mvissing.de` resolves correctly at both sites and off-net

---

# Phase 5 — brink-server bring-up and pi relocation

**Order matters.** brink-server is built first so it can take over the Brink
subnet-router role before the pi leaves; the pi is only then moved. See 3.1 for
why, and for the hard deadline (before Phase 6).

## 5.1 brink-server

Bare-metal NixOS install, done by hand, at Brink.

- Single 1 TB NVMe. ZFS single-vdev — no redundancy, but gains snapshots,
  compression and tooling parity with maxdata. Backed up to maxdata's `tank` in
  Phase 11, which is what makes the lack of redundancy acceptable.
- `hosts/nixos/brink-server/` with `hardware-configuration.nix` from
  `nixos-generate-config`.
- Static `192.168.1.2` (verified free in Phase 0).
- Overlay client + subnet router for `192.168.1.0/24`.
- AdGuard.
- Secret enrolment per Phase 2b: sops host key, `.sops.yaml`, `sops updatekeys`,
  and the 1Password service-account token if opnix is adopted.
- k3s server module (not enabled until Phase 7).

The install procedure in `docs/Migrate_Maxdata.md:136-207` is reusable for the
ZFS and `nixos-install` steps.

Then: repoint the UDM SE static route for `192.168.178.0/24` from the pi's
`192.168.1.90` to brink-server's `192.168.1.2`, and verify cross-site reachability
still holds **before** touching the pi.

## 5.2 Pi

Current state (Phase 0): at **Brink**, `192.168.1.90` via DHCP, up 27 days, with
`home-assistant` and `matter-server` both active, `/var/lib/hass` at 312 M.

Steps 1–5 can all be done **at Brink, before the physical move**. Only the static
`192.168.178.3`, the Winkel subnet advertisement and serving DNS to Winkel
clients require it to be in place — declare them anyway and they take effect on
arrival.

1. Back up `/var/lib/hass` (312 M) before re-imaging — even though the HA
   instance is being discarded, it is cheap insurance and the only copy exists on
   that disk.
2. Re-image. **Carry forward the USB-SATA quirk:**
   `boot.kernelParams = ["usb-storage.quirks=174c:55aa:u"]`
   (`hosts/nixos/k3s-pi/hardware-configuration.nix:10`, duplicated at
   `flake.nix:128`). Omit it and the ASM1153 bridge corrupts the root filesystem
   under sustained write load, e.g. a kernel rebuild.
3. Rename the host. `k3s-pi` is a leftover from an era when it was a k3s node,
   and its `hostId = "03030303"` collides in form with node3's derived ID.
   Suggested: `pi-winkel` or `anchor-winkel`, matching the site naming above.
4. Remove `services.home-assistant` and `services.matter-server`
   (`hosts/nixos/k3s-pi/default.nix:65-101`) — HA moves to brink-server.
5. Add: overlay client + subnet router, AdGuard, secret enrolment per Phase 2b
   with a **host** key at `/etc/ssh/ssh_host_ed25519_key`, k3s agent module.
   Enrol the new host key in `.sops.yaml`; `sops updatekeys` both secret files.
6. **Physically move to Winkel**, static `192.168.178.3` (verified free).
7. **Do not verify the move by mDNS.** maxdata's Avahi still serves a stale
   `k3s-pi.local → 192.168.178.118` from when the pi last lived at Winkel, long
   enough ago that even the ARP entry has expired. Confirm by SSH and MAC
   (`dc:a6:32:22:a2:a1`), and flush the cache afterwards.
8. Repoint the FritzBox static route for `192.168.1.0/24` at `192.168.178.3`,
   then withdraw maxdata's route advertisement.

## 5.3 Exit criteria

- [ ] brink-server at Brink on `192.168.1.2`, advertising `192.168.1.0/24`
- [ ] UDM SE static route repointed at brink-server; cross-site still verified
- [ ] Pi at Winkel on `192.168.178.3`, advertising `192.168.178.0/24`
- [ ] FritzBox static route repointed at the pi; maxdata's advertisement withdrawn
- [ ] Secrets decrypt on both hosts
- [ ] AdGuard serving at both sites (Phase 4 exit criteria still met)
- [ ] **Winkel is reachable without maxdata** — the precondition for Phase 6.
      Verify by stopping maxdata's overlay client and confirming you can still
      reach the Winkel LAN through the pi

---

# Phase 6 — maxdata: microVMs out, bare metal in

⚠️ **First irreversible step.** Everything before this is a safe stopping point.

## 6.1 Re-key sops FIRST

The microVMs' sops age identities are derived from
`/var/ssh/ssh_host_ed25519_key` — a file **inside** the 50 GB `var-state.img`
volume (`modules/system/k3s-node.nix:136`, volume at `:76-82`). maxdata is
already a declared recipient of `secrets/k3s.yaml` (`.sops.yaml:22`) but has no
`sops` block in any of its modules and consumes nothing.

Add a sops config to maxdata using its own host key, verify it can decrypt
`k3s.yaml`, and only then proceed. **Destroy the images first and the k3s token
becomes undecryptable** — the single easiest way to brick this migration.

## 6.2 Remove the microVM layer

Delete:

- `hosts/nixos/maxdata/microvms.nix`
- `hosts/nixos/maxdata/microvm-bridge.nix`
- `hosts/nixos/maxdata/microvms/` (4 files)
- `hosts/nixos/k3s-node1/`, `k3s-node2/`, `k3s-node3/`

Remove the two imports from `hosts/nixos/maxdata/default.nix:24-25`. **No flake
edit needed** — `flake.nix:155-164` auto-discovers `hosts/nixos/*`.

Refactor `modules/system/k3s-node.nix` into `modules/system/k3s-server.nix` and
`modules/system/k3s-agent.nix`:

- Strip the microVM block (lines 41-83) and the guest systemd-networkd config
  (85-110).
- Rewrite the local-path `nodePathMap` from `/mnt/k8s-fast/local-path-provisioner`
  to `/fast/k8s/local-path-provisioner` (`k3s-node.nix:253`).
- Parameterise node role, site zone label, and overlay node IP.
- Re-enable the firewall (guests had `firewall.enable = false`,
  `k3s-node.nix:90`).

## 6.3 Reclaim resources

18 GB RAM and 6 vCPU are freed. Raise `zfs_arc_max`, which is duplicated in
**three** places and must be changed in all of them:

- `hosts/nixos/maxdata/default.nix:49-56` (`kernelParams` + `extraModprobeConfig`)
- `hosts/nixos/maxdata/zfs.nix:113-121` (a second `boot.extraModprobeConfig`)
- `hosts/nixos/maxdata/zfs.nix:124-130` (`environment.etc."modprobe.d/zfs.conf"`)

Also fix the now-wrong comment at `default.nix:48`
(`# ZFS ARC tuning for 32GB RAM (18GB reserved for 3x 6GB microVMs)`).

## 6.4 Firewall cleanup

Drop dead Proxmox-era ports from `hosts/nixos/maxdata/networking.nix:47-52`:
8006 (Proxmox UI), 9090 (Cockpit), 5900 (VNC), 3128 (subscription proxy).
Nothing serves them.

Reconsider `trustedInterfaces = ["vmbr0"]` (`networking.nix:59`) — it existed so
the microVMs could talk freely and currently trusts the whole LAN-facing bridge,
making the port list largely cosmetic. Renaming `vmbr0` is cosmetic and optional;
it is referenced at `networking.nix:20,27,35,59`.

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

The pi at Winkel is an independent second path in: it is on the overlay and does
not depend on maxdata, so it can reach maxdata by LAN IP even if maxdata's
overlay client fails. A smart plug on maxdata's power removes the need for
anyone to be physically present for a power cycle.

ZFS pools are never touched by any step in this phase.

## 6.6 Exit criteria

- [ ] maxdata decrypts `secrets/k3s.yaml` with its own host key — **verified before deletion**
- [ ] microVMs stopped and their images removed
- [ ] maxdata reachable from both sites after `switch`
- [ ] `zpool status` clean, all datasets mounted
- [ ] ARC max raised and confirmed via `arc_summary`

---

# Phase 7 — Fresh cluster

1. `ionos` — `--cluster-init`, first server.
2. `brink-server` and `maxdata` join as servers.
3. `pi` joins as agent.

Per-node flags:

- `--node-ip=<overlay IP>` and `--flannel-iface=<overlay iface>` (D3)
- **Pinned flannel MTU** — compute from the overlay MTU minus VXLAN overhead and
  set it explicitly. Verify with a large-payload ping (`ping -M do -s 1400`)
  across sites, not just a default ping.
- `--node-label=topology.kubernetes.io/zone=<brink|winkel|public>`
- etcd WAN tuning (D4), values from Phase 2 measurements
- `--disable=servicelb,traefik,local-storage` (unchanged intent)
- Cluster/service CIDRs IPv4-only (D1)
- ionos keeps `--node-taint=edge=true:NoSchedule`; note the zone label changes
  from the current `external` to `public`, so any Pulumi nodeSelector must agree

## 7.1 Close the internet-facing k3s ports

`modules/system/k3s-base.nix:19-29` puts 6443, 10250, 2379 and 2380 in the
**global** `allowedTCPPorts` list, and 8472 in the global UDP list. NixOS global
firewall lists apply to *all* interfaces, including ionos's public `ens6`. The
per-interface block at `hosts/nixos/ionos/default.nix:51-55` does **not** fix
this — `networking.firewall.interfaces.<if>.allowedUDPPorts` is *additive*, so an
empty list subtracts nothing.

Fix: remove these from the global list in `k3s-base.nix` and declare them
per-interface on the overlay interface only.

## 7.2 Exit criteria

- [ ] 4 nodes `Ready` with correct zone labels
- [ ] etcd stable for 24 h with no leader elections (`etcdctl endpoint status`,
      k3s logs)
- [ ] Cross-site pod-to-pod at full MTU — verified with a 1400-byte payload, not
      just ping
- [ ] `nmap` from outside confirms only 22/80/443 open on ionos

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
| Postgres (CNPG) | winkel — maxdata | local-path on `/fast/k8s` |
| Paperless (media + data + consume) | winkel — maxdata | NFS 300 Gi + local-path |
| UniFi (`unifi-data`, `unifi-mongo`) | winkel — maxdata | local-path; amd64 + privileged already |
| Time Machine | winkel — maxdata | NFS 3 Ti; hostNetwork, amd64 |
| Home Assistant | brink — brink-server | brink-server local NVMe |
| Mosquitto | brink — brink-server | brink-server local NVMe |
| Redis | winkel — maxdata | local-path (regenerable) |
| Monitoring (Prometheus/Loki/Tempo) | winkel — maxdata | local-path, large PVCs |
| Authentik | winkel — maxdata | local-path media 5 Gi |

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

- [ ] Both MetalLB pools defined with node selectors
- [ ] Every LoadBalancer service has an explicit pinned IP
- [ ] Every `local-path` PVC has a site pin
- [ ] MongoDB and in-cluster AdGuard removed
- [ ] Time Machine out of `default`

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
2. (Moved to Phase 2b) Standardise ionos's sops age key onto a **host** key
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
