# k3s Cluster Migration: VMs → Pi Control Plane + Native maxdata

Migrate from the current "3 microVMs on maxdata + ionos + (planned) pi as agent"
topology to "k3s-pi as control plane + maxdata as native agent + ionos as agent".

**Strategy:** spring-clean. Fresh cluster, no PV adoption. Preserve only
irreplaceable state via app-level dumps. Regenerate monitoring history, caches,
indexes, and TLS certs (carefully, to avoid Let's Encrypt rate limits).

**mDNS / Bonjour:** host Avahi on maxdata runs in reflector mode, bridging mDNS
between LAN and CNI bridge. All cluster workloads drop `hostNetwork: true` and
expose services via ClusterIP/LoadBalancer. No microVMs needed.

**Downtime:** unconstrained.

---

## Topology

| Node      | Role   | Arch    | Zone label              | Notes                                  |
|-----------|--------|---------|-------------------------|----------------------------------------|
| k3s-pi    | server | arm64   | `zone=home`             | Control plane, etcd, Kea DHCP, AdGuard |
| maxdata   | agent  | amd64   | `zone=core`             | Workhorse, ZFS, NFS/SMB, all heavy pods|
| ionos     | agent  | amd64   | `zone=public`           | Public-facing edge over WAN            |

Old VM nodes `k3s-node1/2/3` are decommissioned.

---

## Preserve list (must back up before tear-down)

App-level dumps only. **Do not** attempt PV adoption.

- [ ] **CloudNativePG clusters** — `pg_dump` (or `pg_dumpall`) per CNPG cluster
- [ ] **MongoDB** — `mongodump`
- [ ] **Authentik** — covered by its postgres cluster dump above; also dump any media PVC content (logos, certificates)
- [ ] **Paperless** — postgres dump (covered above) + tarball of documents directory + tarball of media/originals
- [ ] **Home Assistant** — tarball of `/config` (includes SQLite DB, automations, dashboards, integrations, user DB)
- [ ] **UniFi controller** — controller MongoDB dump + `/data` tarball (covers site backup, adoption keys)
- [ ] **Mosquitto** — `mosquitto.db` (retained messages) + ACL/passwd files if customized
- [ ] **TimeMachine** — sparsebundles on the Samba share (verify they're on a preserved ZFS dataset; should not require backup if dataset survives)
- [ ] **AdGuard** — `AdGuardHome.yaml` (filter rules + customizations); query log discarded
- [ ] **cert-manager** — TLS Secrets across all namespaces
      ```sh
      kubectl get secret -A -l controller.cert-manager.io/fao=true -o yaml > /backup/cert-secrets.yaml
      ```
- [ ] **Pulumi state** — confirm Pulumi backend is healthy and committed; new cluster will `pulumi refresh` after import

## Discard list (regenerated on restart)

- Prometheus TSDB
- Loki chunks
- Tempo traces
- Grafana DB if dashboards are code-provisioned (verify `monitoring/grafana.ts`)
- Redis data (it's cache)
- GitHub Actions runner state
- Paperless OCR search index (rebuilds from documents, takes hours)
- All k3s state on old VMs

---

## Phase 0 — Pre-flight

- [ ] Confirm `k3s-pi` boots from USB SSD/NVMe (no SD card) — `lsblk` on pi should show root on `/dev/sda` or `/dev/nvme*`
- [ ] Confirm Pulumi stack is clean: `pulumi preview` shows zero drift
- [ ] Commit all in-flight repo changes; tag pre-migration state:
      ```sh
      cd ~/Git/setup && git tag pre-k3s-migration
      cd ~/Git/homelab-k8s && git tag pre-k3s-migration
      ```
- [ ] Identify dataset layout: confirm where current PVs live on maxdata
      (`/fast/k8s/local-path-provisioner/...`) and which ZFS dataset that is
- [ ] mDNS coexistence strategy (chosen approach: **Avahi reflector on maxdata host**):
      - One Avahi daemon on maxdata listens on both LAN interface and CNI bridge, forwards mDNS between them
      - HA, matter-server, and TimeMachine pods all drop `hostNetwork: true` and expose via Services
      - Resolves port 5353 conflict by keeping pods in their own netns; reflector bridges pod-LAN mDNS
      - Known limitation: Matter *commissioning* uses IPv6 link-local addresses that don't reflect by RFC
        — if commissioning is frequent, plan to either commission via phone app first or pin matter-server
        as the single hostNetwork pod on a node where 5353 is free (likely requires a small dedicated VM)

---

## Phase 1 — Backups

- [ ] CNPG dumps. For each CNPG cluster:
      ```sh
      kubectl -n <ns> exec -it <cluster>-1 -- pg_dumpall -U postgres > /backup/<ns>-<cluster>.sql
      ```
- [ ] MongoDB dump:
      ```sh
      kubectl -n <ns> exec -it <mongo-pod> -- mongodump --archive > /backup/mongodb.archive
      ```
- [ ] PVC tarballs (Paperless docs, HA /config, UniFi /data, Mosquitto db, AdGuard yaml):
      ```sh
      kubectl -n <ns> exec -it <pod> -- tar czf - <path> > /backup/<ns>-<app>.tar.gz
      ```
- [ ] cert-manager secrets export (see preserve list)
- [ ] ZFS snapshot of `/fast/k8s` (insurance — not relied upon):
      ```sh
      zfs snapshot fast/k8s@pre-migration
      ```
- [ ] Verify every dump is non-empty and readable. Spot-test restore of one dump locally if uncertain.

**Gate:** all backups on disk outside maxdata's k8s dataset, sizes look right.

---

## Phase 2 — Nix flake changes (build, do not deploy)

### 2a. Shared module refactor

- [ ] Create `modules/system/k3s-server.nix` from current `modules/system/k3s-node.nix`:
      - Keep: k3s flag construction logic, local-path manifest, sops k3s_token setup
      - Drop: all microvm options (hypervisor, vsock, virtiofs shares, var-state volume, interfaces)
      - **Rewrite local-path nodePathMap:** target node `maxdata` with path `/fast/k8s/local-path-provisioner` (not `/mnt/k8s-fast/...`)
      - Add cluster-init flag conditionally (server-only)
- [ ] Either delete `modules/system/k3s-node.nix` or repurpose as `modules/system/k3s-agent.nix` with just agent-side flag construction

### 2b. `hosts/nixos/k3s-pi/default.nix`

- [ ] Flip `services.k3s.role` to default (server) — remove explicit `role = "agent"`
- [ ] Remove `serverAddr`
- [ ] Add server flags via `extraFlags`:
      - `--cluster-init`
      - `--disable=servicelb,traefik,local-storage`
      - `--write-kubeconfig-mode=644`
      - `--tls-san=k3s-pi`
      - `--tls-san=<pi-ipv4>` and `--tls-san=<pi-ipv6>`
      - `--node-name=k3s-pi`
      - `--node-ip=<pi-ipv4>,<pi-ipv6>`
      - `--cluster-cidr=10.42.0.0/16,fd01::/48`
      - `--service-cidr=10.43.0.0/16,fd02::/112`
      - `--node-label=topology.kubernetes.io/zone=home`
- [ ] Import the new `k3s-server.nix`
- [ ] Keep Kea DHCP config as-is
- [ ] Leave Kea's `domain-name-servers` pointing at gateway (NOT AdGuard) until Phase 7 verification

### 2c. `hosts/nixos/maxdata/`

- [ ] In `default.nix`, remove imports: `./microvms.nix`, `./microvm-bridge.nix`
- [ ] In `default.nix`, add k3s agent config:
      - Import `modules/system/k3s-base.nix`
      - `services.k3s.role = "agent"`
      - `services.k3s.serverAddr = "https://<pi-ipv4>:6443"`
      - `services.k3s.tokenFile = config.sops.secrets.k3s_token.path`
      - `extraFlags`: `--node-name=maxdata --node-ip=<maxdata-ipv4>,<maxdata-ipv6> --node-label=topology.kubernetes.io/zone=core`
- [ ] sops config: same pattern as pi (k3s_token secret)
- [ ] Delete files:
      - `hosts/nixos/maxdata/microvms.nix`
      - `hosts/nixos/maxdata/microvms/` (directory)
      - `hosts/nixos/maxdata/microvm-bridge.nix`
- [ ] Verify maxdata still imports its non-k3s modules: `smb.nix`, `zfs.nix`, `monitoring.nix`, `networking.nix`
- [ ] Enable Avahi reflector in `smb.nix` (or `networking.nix`) — required for HA/TM mDNS without `hostNetwork`:
      ```nix
      services.avahi = {
        enable = true;
        openFirewall = true;
        reflector = true;       # forward mDNS between LAN and CNI bridge
        publish = {              # keep existing SMB Bonjour publish
          enable = true;
          addresses = true;
          domain = true;
          userServices = true;
          workstation = true;
        };
        ipv4 = true;
        ipv6 = true;             # required for Matter operational traffic
      };
      ```
      Keep the existing `extraServiceFiles.smb` entry untouched.
- [ ] Verify firewall rules in `smb.nix` already include UDP 5353 (they do); no change needed.

### 2d. `hosts/nixos/ionos/default.nix`

- [ ] Update `serverAddr` from `k3s-node1` to `k3s-pi`
- [ ] Confirm node label `topology.kubernetes.io/zone=public`

### 2e. `flake.nix`

- [ ] Remove `nixosConfigurations.k3s-node1`, `k3s-node2`, `k3s-node3`
- [ ] Keep `k3s-pi`, `maxdata`, `ionos`

### 2f. Network config

- [ ] `modules/data/network-config.nix`: keep `k3s-node1/2/3` IP entries for now (no harm; removed in Phase 7). `k3s-pi` entry already added.

### 2g. Verify builds

- [ ] `nix flake check`
- [ ] `nixos-rebuild build --flake .#k3s-pi`
- [ ] `nixos-rebuild build --flake .#maxdata`
- [ ] `nixos-rebuild build --flake .#ionos`
- [ ] Commit; do not deploy yet

**Gate:** all four configs evaluate cleanly, committed to setup repo.

---

## Phase 3 — Pulumi changes (commit, do not deploy)

### 3a. Drop hostNetwork, rely on host Avahi reflector

The Avahi reflector enabled in Phase 2c bridges mDNS between LAN and CNI bridge,
so pods can keep their own netns and still participate in Bonjour/mDNS discovery.

- [ ] **`apps/timemachine.ts`**:
      - Remove `hostNetwork: true` (line 105)
      - Add `LoadBalancer` Service exposing SMB (445/TCP) and NetBIOS (137-139) with annotation:
        ```yaml
        metallb.universe.tf/loadBalancerIPs: 192.168.178.12
        ```
      - Verify mbentley/timemachine's internal Avahi advertises on the pod interface — reflector picks it up and forwards `_smb._tcp` + `_adisk._tcp` to LAN. Macs see TM in Finder/System Settings as before.
- [ ] **`apps/homeassistant.ts`**:
      - Remove `hostNetwork: true` from HA pod (line 178) and matter-server pod (line 278)
      - HA already has a ClusterIP Service + Traefik Ingress for HTTP; no LB change needed
      - matter-server: expose to HA via ClusterIP Service if not already
      - Reflector forwards mDNS announcements (Sonos, Chromecast, HomeKit accessory publish, etc.) in both directions
      - **Matter commissioning caveat:** IPv6 link-local addresses don't reflect by RFC. If you commission Matter devices through HA frequently, expect commissioning to fail and fall back to phone-app commissioning, OR keep matter-server as a single hostNetwork pod on a dedicated small VM (out of scope for this plan; defer until confirmed problematic in practice)
- [ ] **Smoke test after Phase 5b deploy**: `avahi-browse -art` on maxdata should show both maxdata's `_smb._tcp` AND TM's `_smb._tcp` + `_adisk._tcp` once TM is deployed. From a Mac on LAN: Finder Network sidebar shows both maxdata and TimeMachine.

### 3b. Node selectors

- [ ] Confirm no Pulumi code references `k3s-node1/2/3` by name (`grep -rn "k3s-node" --include="*.ts"`). Existing nodeSelectors use `kubernetes.io/arch` only — no changes expected.
- [ ] **AdGuard**: confirm `apps/adguard.ts` selects pi via `kubernetes.io/arch: arm64` (or similar). Update if needed to target `topology.kubernetes.io/zone=home`.

### 3c. cert-manager bootstrap

- [ ] Plan to re-apply backed-up cert secrets *before* the first `pulumi up` of apps, so cert-manager treats certs as already-issued.

### 3d. Stack export

- [ ] `pulumi stack export > /backup/pulumi-stack-pre-migration.json` (so the stack can be reset to a clean state and re-imported if needed)

**Gate:** Pulumi changes committed (and pushed if remote). Cert secrets backed up to local disk.

---

## Phase 4 — Tear down old cluster

- [ ] On a VM: `kubectl delete all --all -A` (best-effort cleanup; the cluster is being destroyed anyway)
- [ ] Stop k3s on each VM: `ssh k3s-node1 'sudo systemctl stop k3s'` etc.
- [ ] Stop k3s on ionos: `ssh ionos 'sudo systemctl stop k3s-agent'`
- [ ] On maxdata: `sudo microvm -s stop k3s-node1 k3s-node2 k3s-node3` (and remove from autostart if needed)
- [ ] Confirm VMs are down; no k3s processes on maxdata
- [ ] Leave `/fast/k8s/local-path-provisioner` alone for now (still useful as a sanity check; clean in Phase 7)

**Gate:** no k3s processes running anywhere. `kubectl` against any old endpoint fails.

---

## Phase 5 — Deploy new infrastructure

### 5a. k3s-pi as control plane

- [ ] `nixos-rebuild switch --flake .#k3s-pi --target-host k3s-pi --use-remote-sudo`
- [ ] Verify on pi: `systemctl status k3s` is active
- [ ] Pull kubeconfig:
      ```sh
      scp k3s-pi:/etc/rancher/k3s/k3s.yaml ~/.kube/config-new
      sed -i 's/127.0.0.1/<pi-ipv4>/' ~/.kube/config-new
      export KUBECONFIG=~/.kube/config-new
      ```
- [ ] `kubectl get nodes` → pi is `Ready`
- [ ] `kubectl get deploy -n kube-system local-path-provisioner` → manifest applied
- [ ] `kubectl get sc local-path` → exists, default

### 5b. maxdata as native agent

- [ ] `nixos-rebuild switch --flake .#maxdata --target-host maxdata --use-remote-sudo`
      - This activates native k3s, removes microvm host stack, removes bridge
- [ ] Verify on maxdata: `systemctl status k3s` (agent unit) active; `journalctl -u k3s -f` shows join success
- [ ] From pi: `kubectl get nodes` → maxdata is `Ready` with `zone=core` label
- [ ] **Smoke test:** deploy a busybox pod with `nodeSelector: {topology.kubernetes.io/zone: core}` and hostPath mount of `/fast/k8s/test-mount`, write a file, read it back, delete
- [ ] Verify `/fast/k8s/local-path-provisioner` is writable by the k3s service account (chown to k3s user if needed)

### 5c. ionos as agent

- [ ] `nixos-rebuild switch --flake .#ionos --target-host ionos --use-remote-sudo`
- [ ] From pi: `kubectl get nodes` → ionos is `Ready` with `zone=public` label

**Gate:** three-node cluster healthy, scheduling works, hostPath verified on maxdata.

---

## Phase 6 — Deploy Pulumi stack

### 6a. Reset Pulumi state (clean start)

- [ ] Decide between two modes:
      1. **Refresh + adopt approach**: keep Pulumi state, `pulumi refresh` after deploying — Pulumi will detect missing resources and recreate. Risk: deletions ordered wrong cause downtime spikes.
      2. **Stack reset approach**: `pulumi stack rm` then re-init, state starts fresh. Risk: Pulumi state never knew about resources that might still exist in cluster.
      Spring-clean → cluster is empty, so approach 2 is cleanest. Recommended.
- [ ] If approach 2: `pulumi stack rm default` then `pulumi stack init default`, restore secret keys

### 6b. Layer deployment (in dependency order)

Deploy with `pulumi up --target …` to stage:

1. [ ] **Foundation:** `cert-manager`, `metallb`, `reflector`
2. [ ] **Cert secrets restore** (immediately after cert-manager is up, before any Ingress):
      ```sh
      kubectl apply -f /backup/cert-secrets.yaml
      ```
      Verify cert-manager doesn't re-issue (look at `cmctl status certificate <name>`)
3. [ ] **Traefik** — depends on cert-manager + metallb
4. [ ] **Database operators:** CloudNativePG operator
5. [ ] **Shared databases:** Redis, MongoDB (Redis empty; MongoDB restore from dump after cluster is healthy)
6. [ ] **Per-app postgres clusters** (CNPG bootstrap):
      - Option A: `bootstrap.initdb` then restore dump via `kubectl exec ... psql < dump.sql`
      - Option B: `bootstrap.recovery` from object storage (more complex, skip for spring-clean)
      - Choose A
7. [ ] **Auth:** Authentik DB restore → Authentik app → Authentik outpost. Verify login.
8. [ ] **Apps** (parallel-safe, run one or in small batches and verify each):
      - AdGuard (restore `AdGuardHome.yaml` via Secret/ConfigMap)
      - Paperless (postgres restored above; restore documents tarball into PVC after first deploy creates it)
      - Home Assistant (restore `/config` tarball into PVC after first deploy)
      - UniFi (restore MongoDB + `/data` tarball)
      - Mosquitto (restore mosquitto.db)
      - Homepage (config provisioned by Pulumi, no state)
      - TimeMachine (sparsebundles already on disk; verify share is accessible)
9. [ ] **Monitoring stack:** Prometheus, Loki, Tempo, Grafana, Alloy, ntfy, unpoller — fresh start, no data restore
10. [ ] **Infra extras:** github-runner (ephemeral, no restore)

### 6c. Verification per app

- [ ] Each app: hit its URL via Traefik, log in, verify expected data appears (documents in Paperless, automations in HA, devices in UniFi, etc.)
- [ ] cert-manager: `kubectl get certificate -A` all `Ready=True`, no spike in Let's Encrypt requests
- [ ] Monitoring: Prometheus targets healthy, Grafana dashboards render (re-provisioned)

**Gate:** all apps green via external URL, no certificate re-issuance, smoke tests pass.

---

## Phase 7 — Finalize and clean up

- [ ] Flip Kea DHCP to advertise AdGuard's MetalLB IP as DNS (`k3s-pi/default.nix` Kea config, `domain-name-servers`)
- [ ] `nixos-rebuild switch --flake .#k3s-pi --target-host k3s-pi`
- [ ] Verify DHCP clients resolve via AdGuard (`nslookup test.local` from a client)
- [ ] Remove from `modules/data/network-config.nix`: `k3s-node1`, `k3s-node2`, `k3s-node3` (IPv4 and IPv6 entries)
- [ ] Remove `modules/system/k3s-node.nix` if fully superseded by `k3s-server.nix` and inline agent config
- [ ] On maxdata: clean old PV directories
      ```sh
      sudo rm -rf /fast/k8s/local-path-provisioner/*
      ```
      (only after confirming all apps healthy and no remaining references)
- [ ] On maxdata: remove old microvm state files (`/var/lib/microvms/k3s-node*`)
- [ ] Update `homelab-k8s/CLAUDE.md`: replace "Proxmox VMs" + "tank pool" with accurate NixOS topology
- [ ] Update `setup/README.md` if it references the old topology
- [ ] Commit final state, tag `post-k3s-migration`

**Gate:** repo is internally consistent; no dead references to old VMs.

---

## Phase 8 — Decommission grace period

- [ ] Run for 1 week, observe stability
- [ ] Drop ZFS snapshot once confident:
      ```sh
      zfs destroy fast/k8s@pre-migration
      ```
- [ ] Drop local dump backups (or move to long-term offsite)

---

## Rollback per phase

| Phase | Rollback                                                         |
|-------|------------------------------------------------------------------|
| 0–3   | `git reset --hard pre-k3s-migration` in both repos               |
| 4     | Restart VMs: `microvm-run k3s-node1` etc., k3s comes back        |
| 5a    | `nixos-rebuild --rollback` on pi; old VMs still bootable         |
| 5b    | `nixos-rebuild --rollback` on maxdata — restores microvm stack   |
| 5c    | `nixos-rebuild --rollback` on ionos                              |
| 6     | Spring-clean = data is in dumps. Wipe stack, redeploy from dumps |

---

## Open items to resolve before starting

- [ ] Confirm pi root device is SSD/NVMe (`lsblk -d -o NAME,SIZE,ROTA,TRAN` should show `usb` or `nvme`, not `mmc`)
- [ ] Confirm how often Matter devices get commissioned via HA — if rare/never, reflector approach is fine; if frequent, plan matter-server isolation strategy
- [ ] List actual workloads + their PVCs (drives the Phase 1 backup checklist)
- [ ] Confirm GitOps state: is everything in Pulumi, or are there hand-applied resources to capture before tear-down?