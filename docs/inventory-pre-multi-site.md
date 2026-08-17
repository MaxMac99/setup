# Pre-Migration Inventory

Live state captured **2026-08-05** for Phase 0 of
[`multi-site-migration.md`](./multi-site-migration.md). Snapshot of reality, not
a plan. Several entries **contradict assumptions in the migration plan** — those
are marked ⚠️ and the plan has been corrected.

Access path used: laptop at Brink → `ssh max@212.132.82.102` (ionos) →
`wg0` → `192.168.178.0/24`. maxdata is *not* directly reachable from Brink;
ionos is the only route.

---

## 1. Storage — maxdata

### Pools

Both `ONLINE`, no errors, last scrub 2026-08-01 clean.

| Pool | Size | Alloc | Free | Frag | Cap |
|------|------|-------|------|------|-----|
| `fast` | 928 G | 510 G | 418 G | 57 % | 54 % |
| `tank` | 14.9 T | 6.50 T | 8.44 T | 13 % | 43 % |

```
fast   nvme-CT1000P3SSD8_2237E665D487-part2            (single vdev, no redundancy)

tank   raidz1-0  4× ata-WDC_WD40EFRX-68N32N0
       special   mirror-1  CT1000BX500SSD1-part1 + Samsung_870_EVO-part1
       logs      mirror-2  CT1000BX500SSD1-part2 + Samsung_870_EVO-part2
       cache     CT1000BX500SSD1-part3, Samsung_870_EVO-part3   (not mirrored)
```

Both pools report `zpool upgrade` available (features not enabled). Do **not**
upgrade before Phase 6 — it would break rollback to an older kernel/ZFS.

### Dataset occupancy

| Dataset | Used | Refer | Mountpoint | Note |
|---|---|---|---|---|
| `fast/root` | 343 G | 130 G | `/` | includes `/var/lib/microvms` |
| `fast/nix` | 36.4 G | 36.4 G | `/nix` | |
| `fast/k8s` | 130 G | 56.5 G | `/fast/k8s` | all local-path PVs |
| `tank/data` | 1.69 T | 1.69 T | `/tank/data` | |
| `tank/daten-familie` | **1.46 T** | 1.46 T | `/tank/daten-familie` | the only SMB share in use |
| `tank/daten-max` | 96 K | — | `/tank/daten-max` | ⚠️ **empty** |
| `tank/daten-michael` | 96 K | — | `/tank/daten-michael` | ⚠️ **empty** |
| `tank/daten-anna` | 96 K | — | `/tank/daten-anna` | ⚠️ **empty** |
| `tank/k8s` | 692 G | 692 G | `/tank/k8s` | NFS exports **and** Time Machine data |
| `tank/k8s/timemachine` | 96 K | 96 K | `legacy` | ⚠️ **exists but is NOT mounted** |
| `tank/backups` | 96 K | — | `/tank/backups` | was empty; now holds Phase 1 tarballs |
| `tank/fast-backup/k8s` | 841 G | 56.7 G | legacy | syncoid target |
| `tank/fast-backup/vms` | **68.6 G** | — | — | ⚠️ Proxmox-era leftovers |

### ⚠️ Findings that contradict the plan

1. **`tank/timemachine-max` and `tank/timemachine-michael` do not exist.**
   `setup-smb-datasets.sh:13-24` creates them, but they are absent. The open item
   in the plan ("resolve the ambiguity before deleting anything") is resolved:
   there is nothing to delete and nothing to preserve.

2. **`tank/k8s/timemachine` the *dataset* is not mounted.** It is exported over
   NFS and holds 689 G of real data — but that data lives in the **parent**
   `tank/k8s` dataset, written into the directory the child should have occupied.
   Consequences: no separate quota, no separate snapshot boundary, and the
   `tank/k8s@pre-multi-site` snapshot is what actually protects it.

3. **Time Machine is 689 G and belongs to one Mac only.**
   ```
   689G  /tank/k8s/timemachine/max
   6.2M  /tank/k8s/timemachine/Max's MacBook Pro 2025-10-24-181306.incomplete
   512   /tank/k8s/timemachine/anna
   512   /tank/k8s/timemachine/michael
   ```
   Anna and Michael have never backed up. So the "Winkel Macs back up locally at
   LAN speed" assumption is currently vacuous — the *only* Time Machine client is
   your Mac, which is at Brink, i.e. the cross-WAN case in the plan's Open
   Items. There is also a stale `.incomplete` bundle from 2025-10-24.

4. **Paperless media is 3.4 G, not 300 G.** The 300 Gi is the PVC *request*.
   Real usage across all NFS PVs:
   ```
   3.4G  paperless-media      366M  homeassistant
   214K  matter-server         14K  mosquitto
   ```
   The whole NFS tier is under 4 G. Backing it up off-box is trivial, which makes
   Phase 11's NFS-tier backup much cheaper than assumed.

5. **`tank/fast-backup/vms` — 68.6 G of dead Proxmox zvols** (`vm-100-disk-*`,
   `vm-201/202/203-*`, `base-9000-disk-0`) with 375 snapshots on one of them.
   Nothing references these. Deletable in Phase 13 for a free 69 G.

6. **13 690 snapshots on `tank/fast-backup/k8s`.** Syncoid replicates but nothing
   prunes the target. Add target-side retention in Phase 11.

### local-path PV occupancy (`/fast/k8s/local-path-provisioner`, 57 G total)

| Size | PVC |
|---|---|
| 48 G | `monitoring/prometheus-server` |
| 5.9 G | `monitoring/storage-loki-0` |
| 1.4 G | `unifi/unifi-data` |
| 899 M | `database/postgres-1` |
| 558 M | `database/mongodb-data` ← orphaned |
| 227 M | `database/postgres-1-wal` |
| 194 M | `unifi/unifi-mongo` |
| 156 M | `paperless/paperless-data` |
| 30 M | `monitoring/grafana` |
| 2.2 M | `adguard/adguard-work` |
| 1.9 M | `database/redis-data` |
| ≤10 K | `monitoring/ntfy-storage`, `adguard/adguard-data`, `monitoring/storage-tempo-0`, `monitoring/storage-prometheus-alertmanager-0`, `paperless/paperless-consume`, `authentik/authentik-media` |

**48 of 57 G is Prometheus**, which the plan already classes as disposable. The
entire *irreplaceable* local-path set is under 3 G.

There is also a stray `/fast/k8s/migration` (156 M) holding old copies of
`adguard-data`, `adguard-work`, `paperless-data`, `redis-data` — residue from an
earlier migration. Deletable.

### NFS exports (live)

```
/tank/k8s/nfs         192.168.178.0/24(rw,no_root_squash,sync,...)
/tank/k8s/timemachine 192.168.178.0/24(rw,no_root_squash,async,...)
```

### Memory / ARC

```
Mem: 31 Gi total, 27 Gi used, 3.8 Gi available
ARC: c_min 2 G, c_max 8 G, size 7.88 G   (pinned at max)
Load average: 6.71 / 5.15 / 5.46
Uptime: 83 days
```

ARC is saturated at its 8 G ceiling with only 3.8 G available — the box is
memory-starved because 18 G is held by the microVMs. Phase 6 fixes this.

---

## 2. Cluster

### ⚠️ The cluster is degraded right now

```
NAME        STATUS     ROLES                       VERSION        INTERNAL-IP
ionos       Ready      <none>                      v1.35.2+k3s1   192.168.178.201
k3s-node1   Ready      control-plane,etcd,master   v1.35.6+k3s1   192.168.178.5
k3s-node2   Ready      control-plane,etcd,master   v1.35.6+k3s1   192.168.178.6
k3s-node3   NotReady   control-plane,etcd,master   v1.35.6+k3s1   192.168.178.7
```

`k3s-node3` stopped posting node status at **2026-08-05 04:16**
(`NodeStatusUnknown`, "Kubelet stopped posting node status"), still a voting etcd
member. etcd quorum is 2 of 3 — **one more failure loses the cluster.**

Fallout, all pending since 07:16:

```
authentik/authentik-server     Pending          ← auth is down
authentik/authentik-worker     Pending
monitoring/grafana             Pending
homeassistant/matter-server    Pending
homepage/homepage              Pending
paperless/gotenberg            Pending
default/timemachine            ContainerCreating
paperless/gotenberg (old)      Terminating on k3s-node3
```

Also unhealthy: `mongodb` 576 restarts, `ntfy` 106 restarts, `postgres-1` 7
restarts (last 27 h ago).

Two operational consequences:

- **Do not delay Phase 6/7.** The current cluster is not stable and node3's
  local-path PVs are inaccessible while it is down.
- The apiserver→kubelet proxy is flaky. A `kubectl exec` issued from `k3s-node1`
  against a pod on `k3s-node2` returned `502 Bad Gateway`; the same command run
  *from* `k3s-node2` worked. **Run `kubectl exec` from the node hosting the pod.**
  This is what truncated the first `pg_dumpall` attempt (see §4).

### LoadBalancer assignments — the three "unpinned" ones, captured

| IP | Service | Pinned in Pulumi? |
|---|---|---|
| `192.168.178.10` (+ `fda8:a1db:5685::10`) | `traefik/traefik` | ❌ auto-assigned |
| `192.168.178.11` | `monitoring/loki-external` | ✅ |
| `192.168.178.12` | `default/timemachine` | ✅ |
| `192.168.178.13` | `unifi/unifi` | ❌ auto-assigned |
| `192.168.178.14` | `adguard/adguard-dns` | ❌ auto-assigned |
| `192.168.178.15` | `homeassistant/mosquitto` | ✅ |

Notes:

- Traefik happens to hold `.10`, which is what the six hardcoded DNAT rules on
  ionos (`hosts/nixos/ionos/default.nix:64-73`) assume. **That match is luck, not
  configuration** — it is first-come assignment from the `.10–.20` pool and would
  not survive a rebuild.
- AdGuard's DNS service is on `.14`. Any router/client currently pointed at
  AdGuard is pointed there. Phase 4 replaces it with native AdGuard on fixed
  addresses.
- `unpoller.ts:168`'s comment referencing `192.168.178.13` for UniFi is
  accidentally correct today.

### PVC inventory

22 PVCs: 17 `local-path`, 4 `nfs`, 1 `nfs-storage` (Time Machine — a second class
name for the same server, no provisioner behind either).

Requested vs. actual is wildly oversized throughout: 100 Gi Loki holding 5.9 G,
50 Gi Tempo holding 6.5 K, 300 Gi Paperless media holding 3.4 G.

---

## 3. Secrets

### `.sops.yaml` drift — **fixed**

`secrets/common.yaml` had 3 age recipients while `.sops.yaml:10-17` declared 4.
`sops updatekeys -y secrets/common.yaml` run on 2026-08-05; ionos
(`age100thyt62...`) added. Decryption verified, and the plaintext is byte-identical
to `HEAD` — the pre-existing dirty state was encryption metadata only.

### ⚠️ The "six manual bootstrap secrets" are not lost

The plan states these "exist only because someone typed them into a UI. None are
in git or sops." **That is wrong.** All of them are in
`homelab-k8s/Pulumi.default.yaml`, which is tracked in git and encrypted with
`PULUMI_CONFIG_PASSPHRASE` — itself stored in sops at `personal/pulumi-passphrase`.

All 16 config secrets were decrypted successfully on 2026-08-05:

```
annaPassword  authentikApiToken  authentikOutpostToken  githubPat
grafana-oauth-client-id  grafana-oauth-client-secret
homeassistant-prometheus-token  maxPassword  michaelPassword
paperless-authentik-client-id  paperless-authentik-client-secret
paperless-metrics-api-token  paperless-secret-key
proxmox-api-token  proxmox-api-user  unpoller-password
```

Phase 1.1 therefore reduces to: **keep the Pulumi passphrase safe** (it is in
sops, replicated to 4 recipients) and delete the dead `proxmox-api-*` entries in
Phase 13.

Genuinely outside both git and sops — and now backed up (§4):

- Mosquitto `password.txt` (on NFS)
- ntfy `auth.db`
- `AdGuardHome.yaml` (admin hash, custom rules, client config)

---

## 4. Phase 1 backup manifest

**Local:** `~/backup/pre-multi-site/` · **On maxdata:** `/tank/backups/pre-multi-site/`

| File | Size | Contents |
|---|---|---|
| `pg-globals.sql.gz` | 1.1 K | roles: `app`, `authentik`, `cnpg_metrics_exporter`, `grafana`, `homeassistant`, `paperless`, `postgres`, `streaming_replica` |
| `pg-authentik.sql.gz` | 19 M | 209 MB database — users, groups, applications, providers |
| `pg-paperless.sql.gz` | 3.2 M | 31 MB database — document metadata, tags, correspondents |
| `pg-grafana.sql.gz` | 357 K | 15 MB database — dashboards, datasources, users |
| `pg-app.sql.gz` | 535 B | 7.8 MB default CNPG database (unused) |
| `cert-secrets.yaml` | 101 K | 10 cert-manager TLS secrets |
| `acme-account-keys.yaml` | 5.1 K | `letsencrypt-prod-account-key` + staging — reuse to keep the ACME account |
| `localpath-adguard-data.tar.gz` | 1.6 K | `AdGuardHome.yaml` |
| `localpath-ntfy-storage.tar.gz` | 2.6 K | `auth.db`, `cache.db` |
| `localpath-authentik-media.tar.gz` | 102 B | empty |
| `localpath-unifi-mongo.tar.gz` | 195 M | UniFi bundled Mongo datadir |
| `localpath-paperless-data.tar.gz` | 143 M | search index (regenerable) |
| `nfs-mosquitto.tar.gz` | 2.6 K | `password.txt`, `mosquitto.db` |
| `pulumi-stack-pre-multi-site.json` | 17 M | 302 resources |

**On maxdata only** (too large to be worth pulling over the 3 MB/s tunnel; both
are also inside the ZFS snapshot):

| File | Size |
|---|---|
| `localpath-unifi-data.tar.gz` | 1.4 G |
| `nfs-paperless-media.tar.gz` | 3.3 G |

All tarballs were created from the ZFS snapshot, not from live directories, so
they are point-in-time consistent.

### ZFS snapshots

```
tank@pre-multi-site         (recursive — all 22 datasets)
fast/k8s@pre-multi-site
```

Taken 2026-08-05 14:29. This is the real backup: it captures every local-path PV
and every NFS PV atomically. The tarballs are the off-box copy of the small
irreplaceable subset.

### ⚠️ Postgres: `pg_dumpall` does not work here

A whole-cluster `pg_dumpall` truncated silently at 338 MB — mid-record inside the
`homeassistant` database, before `paperless` was reached — while `kubectl` still
exited 0. Cause: the apiserver→kubelet exec stream drops on this cluster (see §2).

The dump was therefore split per database and run from the node hosting the pod.
Each output was verified to contain the `PostgreSQL database dump complete`
marker. Note that PG 18 emits a trailing `\unrestrict <token>` line *after* that
marker, so "last line" checks give a false negative.

**`homeassistant` (2834 MB) was deliberately not dumped** — it is recorder history
and Home Assistant is being rebuilt from scratch. It is the largest database by
20× and the thing that broke the combined dump. It is still inside
`fast/k8s@pre-multi-site` if it is ever wanted.

Database sizes:

```
homeassistant 2834 MB     grafana        15 MB
authentik      209 MB     app/postgres  7.8 MB each
paperless       31 MB
```

### Not done — needs you

- [ ] **UniFi `.unf` export** via the controller UI (`apps/unifi.ts:290-294`).
      The raw `unifi-data` + `unifi-mongo` tarballs exist, but `.unf` is the
      supported restore path for re-adoption.
- [ ] **Restore rehearsal** — Phase 1's exit criterion. Load `pg-authentik.sql.gz`
      into a scratch Postgres and confirm it applies. Nothing else validates the
      dumps.

---

## 5. Router state

Captured 2026-08-05 from the two web UIs. Both are reachable from Brink — the
FritzBox and the UniFi controller answer over `wg0` via ionos, so nothing here
required travelling to Winkel.

**UDM SE (Brink, `192.168.1.1`)**

| Item | Value |
|---|---|
| DHCP pool | was `192.168.1.6–.254` ("Auto") → **shrunk to `.6–.199`** ✅ |
| Static routes | present and configurable ✅ |
| Fixed IP reservations | none |
| Laptop | `192.168.1.93`, gateway `192.168.1.1` |

Start was deliberately left at `.6` so existing leases survive; only the top was
shrunk. That frees `.200–.254` for the `.240–.250` MetalLB pool and leaves
`.2–.5` static for brink-server.

⚠️ **Seven clients hold leases above `.199`** — `.200`, `.212`, `.225`, `.231`,
`.233`, `.244`, `.253`. None have fixed IPs, so they will move into `.6–.199` on
renewal, but existing leases stay valid until they expire (UniFi default 24 h).
`.244` sits inside the planned MetalLB pool.

**Pre-check before Phase 8:** confirm `.240–.250` is empty before defining the
Brink MetalLB pool. Either wait out the lease time or forget the leases in the
UniFi UI.

**FritzBox (Winkel, `192.168.178.1`)**

| Item | Value |
|---|---|
| DHCP pool | `192.168.178.20–192.168.178.200` — no change needed |
| Static routes | table exists, currently **empty** — confirmed configurable |
| WAN IPv6 prefix | `2a00:6020:b481:e300::/56` (recorded 2026-08-05) |
| VPN peers | `192.168.178.201/32` (ionos), `.202`, … — see below |
| Fixed IP reservations | not located in FRITZ!OS 8.x UI; see below |

**No DHCP change needed.** The pool already stops at `.200`, so `.240–.250` is
free, and `.2`/`.3`/`.5`/`.6`/`.7` plus ionos's `.201` all sit outside it.

Confirms Deutsche Glasfaser delegates a **/56**. Per D2 nothing may depend on
this prefix — it is recorded as a datapoint for the Phase 2 spike, where the
question is whether the overlay can hold a direct site-to-site path across a
prefix change.

⚠️ **Latent conflict at Winkel today:** the live MetalLB pool is
`192.168.178.10–20` and DHCP starts at `.20`. They overlap on exactly one
address. Nothing has collided, but it is a further argument for D5.

### The FritzBox is the estate's WireGuard server

Not previously recorded anywhere. Under **Internet → Freigaben → VPN
(WireGuard)** the FritzBox terminates inbound WireGuard and hands each peer a
`/32` out of the LAN subnet, counting up from `192.168.178.201`:

- `.201` — ionos (matches `hosts/nixos/ionos/default.nix:95`)
- `.202`, `.203`, … — remote-access clients

So the repo's picture was incomplete: ionos is not a special case, it is one peer
of a general VPN service, and every other peer is a remote-access use case the
overlay has to replace. Enumerating them is a Phase 3 task.

Two consequences:

1. **The direction is wrong for a DS-Lite estate.** Inbound reachability depends
   on MyFRITZ! DDNS plus a prefix that is not guaranteed stable — the boot-order
   hack at `hosts/nixos/ionos/default.nix:143-147` is the symptom. The overlay
   inverts this: both sites dial out to ionos's fixed address.
2. **Peer allocation grows toward the MetalLB pool.** `.201` upward vs
   `.240–.250`. ~40 peers away, so not urgent, but retiring the FritzBox VPN in
   Phase 13 removes the question.

### Address availability — verified on the wire

The FRITZ!OS 8.x reservation list could not be opened in the UI, so this was
answered directly instead: ARP probes from maxdata at Winkel, ICMP from the
laptop at Brink. More reliable than the UI anyway, since it reports what is
actually live rather than what is configured.

| Address | Site | State | For |
|---|---|---|---|
| `192.168.178.3` | winkel | **free** — no ARP reply, no ICMP | k3s-pi after relocation |
| `192.168.178.240–250` | winkel | **free** — all ARP INCOMPLETE | MetalLB pool |
| `192.168.1.2` | brink | **free** | brink-server |
| `192.168.1.240–250` | brink | **free** — no ICMP reply | MetalLB pool |

Live hosts on the Winkel LAN: `.1` FritzBox, `.5/.6/.7` microVMs, `.201`
(WireGuard peer, answered by the FritzBox's own MAC), plus ~11 DHCP clients in
`.45–.170`. `.11` (loki-external) does not answer — the cluster is degraded.

### ⚠️ Stale mDNS and ARP residue at Winkel

`k3s-pi.local` still resolves to `192.168.178.118` from maxdata's Avahi cache,
and a stale ARP entry for the pi's MAC (`dc:a6:32:…`, Raspberry Pi Trading)
lingers. **Both are wrong.** The pi is at Brink:

```
k3s-pi   192.168.1.90/24 on end0 (DHCP)   up 27 days
         home-assistant: active   matter-server: active
         /var/lib/hass: 312 M
```

This nearly produced a false conclusion — that the pi had never left Winkel and
Phase 5's relocation was a no-op. It has left; the records are residue.

Two consequences:

1. **Phase 5.1's physical move is still required.** The pi is at Brink today and
   has to go to Winkel per D10.
2. **Do not trust mDNS for identity during Phase 5.** After the move, flush
   Avahi caches or verify by SSH and MAC, not by `.local` name. maxdata held a
   wrong record for a pi that had been gone long enough for the ARP entry to
   expire.

The Home Assistant state to back up before re-imaging is 312 M — cheap insurance
even though the instance is being discarded.
