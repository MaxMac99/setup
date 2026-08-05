# Overlay evaluation — Headscale/Tailscale vs NetBird

Phase 2 deliverable. Measured on throwaway state, 2026-08-05, against the
criteria in [`multi-site-migration.md`](./multi-site-migration.md) §2.2.

**Decision: Headscale + Tailscale.**

The data plane is a tie — both products get a direct site-to-site path over
native IPv6 with identical MTU and statistically indistinguishable RTT. The
decision is made entirely by the surrounding properties: bootstrap dependencies,
what can live in git, firewall surface, k3s integration, and — decisively —
that the nixpkgs NetBird server module ships **no working relay fallback at all**.

---

## 1. Environment and method

Nothing existing was modified. The FritzBox↔ionos WireGuard tunnel was not
touched. All spike state is throwaway (`/var/lib/headscale-spike`,
`/var/lib/netbird-spike`, `/var/lib/tailscale-spike`), all services run as
transient `systemd-run` units, and all firewall changes are runtime-only
`iptables` rules that vanish on reboot or rebuild. Teardown in §9.

| Role | Host | Site | Address |
|---|---|---|---|
| Control server (both products) | `ionos` | public | `212.132.82.102` / `2a02:2479:5c:a00::1` |
| Client A | `k3s-pi` | brink | `192.168.1.90`, GUA in `2a00:6020:b444:bb00::/56` |
| Client B | `maxdata` | winkel | `192.168.178.2`, GUA in `2a00:6020:b481:e300::/56` |

Versions, all from each host's own pinned nixpkgs:

| Component | Version |
|---|---|
| headscale | 0.29.3 |
| tailscale (pi / maxdata) | 1.98.3 / 1.98.10 |
| netbird-management / -signal | 0.69.0 |
| netbird client (pi / maxdata) | 0.71.4 / 0.76.0 |
| dex | 2.45.1 |
| coturn | 4.9.0 |

### 1.1 Pre-flight: is a direct site-to-site path even possible?

Both sites have a **native IPv6 GUA**, so a direct path is physically available
— this is the single most important precondition and it holds.

```
pi → ionos, native IPv6:   0% loss, rtt 12.752/12.873/13.282/0.204 ms
pi → maxdata, native IPv6: From 2a00:6020:1000:1b::f4
                           Destination unreachable: Administratively prohibited
```

That rejection comes from the **FritzBox's WAN address**, not from the network.
Packets route from Brink to Winkel's prefix across the public internet and are
dropped by the FritzBox's stateful firewall on arrival. That is a firewall
decision on unsolicited inbound traffic, not a routing failure — which is
exactly the condition UDP hole punching is designed to defeat. Both products
subsequently punched through it.

---

## 2. The constraint that shaped the whole spike

**ionos sits behind an IONOS Cloud firewall that is default-deny, and it is
invisible from inside the VPS.**

Inbound TCP 8080/8443/9999 and UDP 3478/41641/51820 produced **zero packets on
`ens6`**, verified with `tcpdump`, which sits ahead of `iptables`. The host
firewall was never involved. Only 22/80/443 were permitted; 80 and 443 are
`DNAT`'d to the production Traefik (v4 and v6 alike) and could not be
repurposed without breaking HTTPS for the household at both sites.

This is a **Phase 3 prerequisite that the plan does not currently record**, and
it is also a scoring input, because the two products need very different
openings:

| | Headscale | NetBird |
|---|---|---|
| Control plane | 1 TCP port (reverse-proxyable behind 443 via SNI) | 1 TCP port (nginx fronting management + signal gRPC + dashboard) |
| NAT traversal | UDP 3478 (STUN, embedded DERP) | UDP 3478/3479 + TCP 5349/5350 (coturn) |
| Relay | same TCP port as control (embedded DERP) | **UDP 49152–65535** — 16 384 ports, the nixpkgs default |

Under a default-deny provider firewall, NetBird's coturn relay range is a
materially larger and uglier ask. It can be narrowed (I pinned it to
49152–49200 for the spike), but it is per-relay-session state on a VPS whose
firewall you administer through a web panel.

Ports opened for the spike, to be closed at teardown: TCP 8443, TCP 8444,
UDP 3478, UDP 49152–49200.

### 2.1 TLS is mandatory, not cosmetic

The first run used a plain-HTTP control server on a non-standard port. It
worked until the control server was stopped, at which point maxdata's client
logged:

```
control: controlhttp: forcing port 443 dial due to recent noise dial
Received error: PollNetMap: Post "https://212.132.82.102:8443/machine/map":
  all connection attempts failed
  (HTTP: TLS forced: no port 80 dialed, HTTPS: dial tcp 212.132.82.102:443: connection refused)
```

The client's fallback heuristic escalated to HTTPS and then to **port 443**,
which is DNAT'd to the cluster, so it could never reconnect. A plain-HTTP
control server on an alternate port is a trap: any control interruption can
wedge a client permanently. The spike was redone over HTTPS.

The certificate was obtained by **manual DNS-01** (certbot `--manual` with an
auth hook that pauses for the operator to publish the TXT record). No DNS API
credentials were needed or handled, and the private key never left ionos. This
is a usable pattern for Phase 3 if the IONOS DNS API token for Phase 9's
`cert-manager-webhook-ionos` is not yet in place.

---

## 3. Measurements

### 3.1 Direct vs relayed path — criterion 1

**Both products get a direct path over native IPv6. Neither relays via ionos in
steady state.**

Headscale/Tailscale, `tailscale ping` from Brink to Winkel:

```
pong from maxdata-winkel-spike (100.64.0.2) via DERP(ionos) in 25ms
pong from maxdata-winkel-spike (100.64.0.2) via DERP(ionos) in 23ms
pong from maxdata-winkel-spike (100.64.0.2) via DERP(ionos) in 24ms
pong from maxdata-winkel-spike (100.64.0.2) via 94.31.109.83:4199 in 5ms
```

It starts relayed and upgrades to direct within ~3 probes, settling on
`[2a00:6020:b481:e300:6011:c5ff:fe27:82f1]:41641`.

NetBird, `netbird status -d`:

```
Connection type: P2P
ICE candidate (Local/Remote): host/host
ICE candidate endpoints (Local/Remote):
  [2a00:6020:b444:bb00:...]:51820 / [2a00:6020:b481:e300:...]:51820
Latency: 5.92611ms
```

NetBird reached direct via **`host/host` ICE candidates** — it used the native
IPv6 addresses directly without even needing STUN.

**The relay penalty is now quantified.** With only the ionos DERP in the map
(public DERP disabled, modelling the production design), a relayed cross-site
path costs **23–25 ms against 5 ms direct** — roughly 5×. That is the concrete
cost of "cross-site etcd heartbeats detour through the VPS", and it justifies
the D4 tuning independently of the direct-path result.

**Path selection is asymmetric.** Brink→Winkel settled on native IPv6;
Winkel→Brink settled on CGNAT IPv4 (`94.31.94.151:61435`). Both direct, but
different address families per direction. Hole punching therefore works through
DS-Lite CGNAT as well as over IPv6 — useful, because it means the direct path
does not depend solely on the unstable DG prefix.

The pi's ICE candidate also changed between observations
(`...81a5:9e:c18:cd99` → `...4b28:5572:d3ed:60fa`) because of IPv6 privacy
extensions. Both products re-negotiated transparently. Worth knowing given D2:
the site prefix is unstable *and* the host suffix rotates, and neither product
cares.

### 3.2 Cross-site RTT and jitter — criterion 2 → feeds D4

Sampling ran every ~60 s in both directions — 20 ICMP echoes per sample, with the
direct/relay path recorded alongside — from **2026-08-05 17:26 CEST**. Harvested
at 23:21 CEST: **347 usable samples per direction over 5 h 55 min**, after
discarding the contaminated window described below.

| | Brink → Winkel | Winkel → Brink |
|---|---|---|
| min of min | 4.780 ms | 4.942 ms |
| **p50 of avg** | **5.757 ms** | **5.851 ms** |
| p95 of avg | 6.133 ms | 6.145 ms |
| p99 of avg | 6.634 ms | 6.813 ms |
| worst single echo | 35.596 ms | 30.430 ms |
| **mean jitter** (ping mdev) | **0.443 ms** | **0.461 ms** |
| packet loss | **0** across 347 samples | **0** |
| relay fallback | **0 / 347 — direct throughout** | **0 / 347** |

**The stability result is the important one.** Not one sample in either direction
fell back to DERP over six hours, and there was no packet loss at all. Brink→
Winkel held the same native-IPv6 endpoint for the entire run; Winkel→Brink
started on CGNAT IPv4 (`94.31.94.151:61435`) and moved to IPv6, so it changed
endpoint family once — but never left a direct path.

**D4 is settled by this.** The planned `heartbeat-interval=500` /
`election-timeout=5000` sit 73× and 735× above the measured p99. Even the worst
single echo in six hours (35.6 ms) is 14× inside the heartbeat, and the
*relayed* path measured in §3.1 (23–25 ms) is 20× inside it. There is no
plausible reading of this data in which the planned values are too tight, so
they are adopted as measured rather than assumed.

Representative single 20-packet samples, Brink→Winkel, for the head-to-head:

| Overlay | min | avg | max | mdev |
|---|---|---|---|---|
| Headscale/Tailscale | 5.101 | 5.535 | 6.054 | 0.231 |
| NetBird | 4.691 | 5.407 | 7.075 | 0.688 |

Indistinguishable in the mean. The apparent jitter difference is within
sample-to-sample noise at this sample size and should not be read as a
difference between the products.

> **Why six hours and not twenty-four.** The window was cut deliberately, not
> abandoned. What the remaining eighteen hours could have added is diurnal
> variation and a longer baseline for flap frequency — and both have a better
> home than a throwaway spike:
>
> - **Phase 3** rolls out the production overlay and its exit criteria already
>   require the path to be characterised and RTT recorded. Measuring the real
>   thing for longer is strictly more relevant than measuring throwaway state.
> - **Phase 12** adds permanent cross-site blackbox probes — latency, loss and
>   direct-vs-relay — so this becomes continuously monitored rather than
>   sampled once.
> - **Phase 7's own gate** is "etcd stable for 24 h with no leader elections",
>   which is the empirical test of D4 that actually matters.
>
> Revisit D4 only if Phase 3 or 12 shows relay flapping that this window did not.
> Given 347/347 direct with zero loss, that is not the expected outcome.

**Discard samples between roughly 17:35 and 17:49 on 2026-08-05.** While both
overlays ran simultaneously, NetBird's subnet route (table 7120, priority 110)
made each peer's *LAN* address reachable from the other site, and Tailscale
duly picked it up as a "direct" endpoint — one sample reads
`direct 192.168.1.90:41641`, i.e. Tailscale tunnelling inside NetBird. NetBird
was torn down at 17:49 for exactly this reason; the path immediately returned to
`[2a00:6020:b481:e300:…]:41641` and the rest of the window is clean. The `path`
column in the CSV makes the affected rows easy to spot.

This is also a warning for Phase 3: if any second overlay or subnet route ever
makes a node's LAN address reachable cross-site, Tailscale will prefer it, and
the "direct" label in `tailscale status` will no longer mean what you think.

Provisional read: at ~5.5 ms steady-state the etcd defaults (100 ms heartbeat /
1000 ms election) would nominally suffice, but the ~24 ms relayed fallback and
consumer-uplink jitter are exactly the tail events that cause spurious leader
elections. The planned `heartbeat-interval=500` / `election-timeout=5000`
remains the right target and is not contradicted by the measurement.

### 3.3 Overlay MTU — criterion 3 → D3

**Both overlays present MTU 1280.** Largest ICMP payload passing with DF set is
**1252** on both (1252 + 20 IP + 8 ICMP = 1280); 1260 fails.

```
ts-spike0: mtu 1280   (Tailscale)
wt0:       mtu 1280   (NetBird)
```

For D3, flannel VXLAN over the overlay costs 50 bytes (20 outer IP + 8 UDP +
8 VXLAN + 14 inner Ethernet):

> **flannel MTU = 1280 − 50 = 1230**

This must be pinned explicitly. Phase 7's verification should use
`ping -M do -s 1202` (1202 + 28 = 1230) across sites, not a default ping.

Existing interface MTUs on ionos, for reference: `wg0` 1420, `flannel.1` 1370,
`cni0` 1370. The overlay is a step down from the current tunnel.

### 3.4 Subnet routes to unmodified clients — criterion 4

**Both products, both directions, verified against genuinely unmodified
devices.**

| From | To (unmodified) | Headscale | NetBird |
|---|---|---|---|
| pi (brink) | FritzBox `192.168.178.1` | 6.485 ms | 5.492 ms |
| pi (brink) | maxdata `192.168.178.2` | 5.753 ms | 5.128 ms |
| maxdata (winkel) | UDM SE `192.168.1.1` | 6.320 ms | 5.329 ms |
| maxdata (winkel) | MacBook `192.168.1.93` | 10.916 ms | 28.129 ms¹ |

¹ high variance from a laptop's wifi power management, not the overlay.

Two things this does **not** yet prove: unmodified-client ↔ unmodified-client
still needs the router static routes, which is Phase 3's exit criterion, not
Phase 2's. What is proven is that the subnet router forwards correctly in both
directions.

Attribution note: once both overlays were running they advertised the same
subnets. NetBird installs into table 7120 at rule priority **110**; Tailscale
uses table 52 at priority **5270**. NetBird therefore wins when both are up.
The Headscale figures above were taken before NetBird existed, so they are
clean. Later, when NetBird's `wt0` disappeared during a restart test, a subnet
ping still succeeded — over Tailscale's table 52, not NetBird.

**`net.ipv4.ip_forward` was `0` on both pi and maxdata.** Subnet routing cannot
work without it and neither product sets it. Phase 3/5 must set this
declaratively on every subnet router.

### 3.5 Behaviour when the control server is down — criterion 5

**Identical for both products, and more consequential than the plan assumes.**

| Scenario | Headscale | NetBird |
|---|---|---|
| Control stopped, clients untouched | Data plane fully survives; direct path and subnet routing keep working | Same — peer stays `Connected`, subnet routing works |
| Client daemon restarts while control is down | **Total loss.** `NoState`, "You are logged out", no peers, no routes | **Total loss.** `wt0` does not exist at all |
| Control returns | Automatic self-recovery, no manual re-auth | Automatic self-recovery |
| Subnet routes after outage | Withdrawn while the advertising peer is marked offline, restored on reconnect | Restored on reconnect |

The middle row is the finding that matters. State *is* persisted — recovery is
automatic once control returns — but neither client can **cold-start** without
reaching its control server.

Implication for Phases 6 and 7, which is not currently written down: once the
overlay carries the k3s node IPs, **ionos being unreachable at the moment a
home host reboots leaves that host with no overlay at all.** Both sites are
behind CGNAT, so for maxdata the overlay would be the only path in. This is a
concrete, measured justification for keeping the FritzBox↔ionos tunnel until
Phase 13 — and an argument for the Phase 6.5 dead-man's reboot discipline
applying to any overlay-carrying host, not just maxdata.

### 3.6 Relay fallback — where the two products genuinely diverge

Headscale's embedded DERP on ionos worked: it registered as region 999, served
STUN on 3478, and carried traffic at 23–25 ms before the direct path came up.
There is a working fallback when hole punching fails.

**NetBird had no usable relay at any point.** The client reported
`Relays: 0/0 Available`, later `0/2 Available`, and `Relay server address:`
was always empty.

The cause is in nixpkgs:

```
grep -rniE "relay" nixos/modules/services/networking/netbird/  →  0 matches
```

The module wires up **coturn only**. NetBird 0.71+ clients use NetBird's own
separate `relay` service, which the module does not know about. The clients
nixpkgs ships (0.71.4, 0.76.0) are newer than the server it ships (0.69.0), so
out of the box you get a server stack whose relay component the clients no
longer use.

I did not chase this to a fix — a fix means either pinning older clients,
packaging `netbird-relay` yourself, or patching the module. That effort is
itself the finding. **An overlay with no relay fallback fails completely
whenever P2P fails**, which for a household VPN spanning two CGNAT uplinks is
not an acceptable steady state.

### 3.7 Bootstrap dependencies — the D11 cost, quantified

`oidcConfigEndpoint` is confirmed **mandatory** — a bare `str` with no default
in `netbird/management.nix`, so the module will not evaluate without it. The
`server.md` quickstart is explicit that a self-hosted NetBird needs "both a
Coturn server **and an identity provider**".

Standing that up for the spike required, on ionos:

1. **Dex** as a native OIDC provider (the in-cluster Authentik cannot be used —
   it runs inside the cluster whose networking depends on the overlay).
2. **nginx** to multiplex management HTTP API, management gRPC, signal gRPC and
   Dex onto the single permitted TCP port.
3. **coturn**.
4. A scripted **OAuth device-authorization flow** just to create the first
   account, because in single-account mode no account and therefore no setup
   key exists until a human completes an OIDC login. That took four HTTP steps
   (`/device/code` → form POST to `/device/auth/verify_code` → GET the callback
   → poll `/token`), plus registering `/device/callback` as a redirect URI, and
   only then a REST call to mint a setup key.

So NetBird costs **three extra always-on services on ionos** (Dex, nginx,
coturn) plus a bootstrap ritual, versus Headscale's **one process and one port**.
Every one of those is another thing outside the cluster to secure, monitor,
back up and upgrade — on the single host whose availability the whole estate
already depends on.

This is the cost the plan asked to be carried into scoring rather than treated
as disqualifying. Carried: it is real and it is large, but on its own it would
not have decided the outcome. §3.6 would have.

### 3.8 Declarative in Nix + git

Headscale: the ACL is a **HuJSON file on disk** (`policy.mode: file`), and the
whole server is one YAML config. Both are ordinary files that go in git and
deploy with `nixos-rebuild`.

NetBird: policies, network routes, groups and setup keys live in **sqlite,
mutated over the REST API**. Every routing and policy change in this spike was
a `curl -X POST` whose only durable record is a database row. The nixpkgs module
declares the *services* but not their *policy*. For a repo whose organising
rule is that configuration lives in git, that is a structural mismatch.

### 3.9 k3s integration

k3s v1.35.2 has first-class Tailscale support, verified on ionos:

```
--vpn-auth value  (agent/networking) (experimental) Credentials for the VPN provider.
   It must include the provider name and join key in the format
   name=<vpn-provider>,joinKey=<key>[,controlServerURL=<url>][,extraArgs=<args>]
```

`controlServerURL` is exactly the self-hosted-Headscale case. It is marked
experimental and I did **not** test it — D3 pins `--node-ip` and
`--flannel-iface` explicitly anyway, which is the more predictable route. But
the option exists for Tailscale and has no equivalent for NetBird.

### 3.10 Re-enrolment and key rotation

Both are clean. Headscale: reusable pre-auth key, and I wiped and re-enrolled
both nodes twice (once to move from HTTP to HTTPS) with no manual steps.
NetBird: reusable setup key, same. No difference worth scoring.

### 3.11 UniFi OS — criterion 6

**The premise in the plan appears to be wrong.** §2.2 and §3.2 assert that
"UniFi OS ships a first-party Tailscale app for the UDM/UDR line". I could find
no such first-party app. What exists is a third-party community package
([`SierraSoftworks/tailscale-unifi`](https://github.com/SierraSoftworks/tailscale-unifi),
~1.7k stars), installed by `curl … | sh` over SSH, persisting under `/data`.

That package runs a real `tailscaled`, so it *does* accept
`--login-server` and would work against Headscale, including
`--advertise-routes`. But it is unsupported by Ubiquiti, requires SSH on the
UDM SE (which UniFi explicitly warns against), and is a candidate to break on
UniFi OS upgrades — a poor foundation for the thing that keeps cross-site
routing alive.

**Not verified.** I have no shell or console on the UDM SE, so this could not
be tested. It needs someone to look at the UniFi OS app store and confirm
whether a Tailscale app exists and whether it exposes a custom login-server
field.

Provisional consequence, to be confirmed: the UDM SE does **not** become its
own subnet router, brink-server remains the cross-site SPOF at Brink, and
Phase 3.2's static-route design stands as written. NetBird has no UniFi OS
integration of any kind, so this criterion cannot favour NetBird either way.

---

## 4. Scoring

| Criterion | Headscale | NetBird | Winner |
|---|---|---|---|
| Direct site-to-site over native IPv6 | ✅ direct, 5 ms | ✅ direct, 5.9 ms | tie |
| Cross-site RTT / jitter | 5.535 avg | 5.407 avg | tie |
| Overlay MTU | 1280 | 1280 | tie |
| Subnet routes to unmodified clients | ✅ both directions | ✅ both directions | tie |
| Control server down | survives; cold start fatal | survives; cold start fatal | tie |
| **Relay fallback** | ✅ embedded DERP on ionos, 23–25 ms | ❌ **none available in nixpkgs** | **Headscale** |
| **Bootstrap dependencies** | 1 process, 1 port | +Dex +nginx +coturn, OIDC device-flow ritual | **Headscale** |
| **Declarative in git** | HuJSON ACL + YAML, both files | policy/routes in sqlite via REST | **Headscale** |
| **Provider firewall surface** | 1 TCP + 1 UDP | 4 TCP + 16 384 UDP (default) | **Headscale** |
| k3s integration | `--vpn-auth` exists (experimental) | manual only | Headscale (weak) |
| nixpkgs coherence | server + client versions align | server 0.69 vs clients 0.71/0.76 | **Headscale** |
| GUI | Headplane (third-party) | dashboard (first-party) | NetBird |
| Re-enrolment / key rotation | clean | clean | tie |
| Runs on UniFi OS | third-party pkg only, **unverified** | no integration | neither |

NetBird wins exactly one criterion — the first-party dashboard — and per the
layering rule the GUI is a cluster workload talking to the control server's
API, which is the least load-bearing item on the list.

---

## 5. Decision

**Headscale + Tailscale.**

Not because the data plane is better; it is not, it is a tie, and that tie is
itself worth recording because it means the choice carries no latency or MTU
penalty either way.

It wins because:

1. **It has a working relay fallback and NetBird, as packaged, does not.** A
   direct path was measured today across two consumer uplinks whose prefixes
   are explicitly not guaranteed stable (D2). When it eventually fails, the
   difference between "23 ms via ionos" and "no connectivity" is the difference
   between a slow cluster and a broken one.
2. **It adds nothing to ionos.** One process, one port, one config file.
   NetBird adds Dex, nginx and coturn to the single host the entire estate
   already depends on — directly against the layering rule's principle that the
   overlay's control plane must not grow dependencies on things it bootstraps.
3. **Its policy is a file.** The ACL is git-managed HuJSON. NetBird's lives in
   a database behind a dashboard.
4. **Its firewall surface fits the environment.** Under a default-deny provider
   firewall, one TCP port plus one UDP port beats four TCP ports plus a
   16 384-port UDP range.

The NetBird OIDC dependency was carried into scoring as instructed and was
*not* treated as disqualifying — it is item 2 of four, and the decision would
be the same without it on the strength of item 1 alone.

### 5.1 Fallback not triggered

§2.3's fallback (plain WireGuard site-to-site with a hub on ionos) is not
needed. Both candidates passed the direct-path and subnet-routing criteria.

---

## 6. What this changes in the migration plan

| Item | Value | Where it lands |
|---|---|---|
| Overlay product | **Headscale + Tailscale** | Decision log |
| Overlay path | **Direct over native IPv6**, asymmetric (v6 one way, CGNAT v4 the other) | Decision log |
| Overlay MTU | **1280** → flannel **1230** | Decision log, D3, Phase 7 |
| Cross-site RTT | **p50 5.8 ms, p95 6.1 ms, p99 6.8 ms, jitter 0.45 ms**, both directions, 347 samples/direction over 5 h 55 min, zero loss, zero relay fallback. Relayed via ionos measures 23–25 ms | Decision log, D4 |
| IONOS Cloud firewall | default-deny, only 22/80/443; must be opened for the control plane | **New Phase 3 prerequisite** |
| Control-plane TLS | mandatory; plain HTTP on an alternate port wedges clients | Phase 3 |
| `ip_forward` | `0` on pi and maxdata; must be set declaratively | Phase 3, Phase 5 |
| Cold start needs control | a host rebooting while ionos is down loses the overlay entirely | Phase 6, Phase 7, and the case for keeping the FritzBox tunnel to Phase 13 |
| UniFi OS first-party app | **appears not to exist**; plan §2.2/§3.2 premise is wrong | Phase 3.2 — correct the text |

### 6.1 New Phase 3 work items this surfaced

- Open the IONOS Cloud firewall for the control plane, and record which ports
  in the repo. This is invisible from inside the VPS and will otherwise be
  rediscovered painfully.
- Decide how Headscale gets TLS on 443. Options: share 443 with the Phase 9
  hostNetwork Traefik via SNI (preferred — no extra firewall opening), or keep
  a dedicated port. Until Phase 9, 443 is DNAT'd to the cluster.
- Run the embedded DERP on ionos (region 999 + STUN 3478) so relay fallback
  exists and stays inside the estate rather than using Tailscale's public DERP.
- Set `net.ipv4.ip_forward` / `net.ipv6.conf.all.forwarding` on every subnet
  router.
- Pin the ACL as a HuJSON file in git from the start.

---

## 7. Confidence and what was not tested

Stated plainly, because several of these matter:

- **The 24-hour window has not closed.** Every RTT number here is a spot sample
  or the first minutes of the run. §3.2 says where to read the real figures.
- **UniFi OS was not tested at all** (no UDM SE access). §3.11.
- **`--vpn-auth` was not exercised**; only its presence in k3s v1.35.2 verified.
- **No GUI was deployed** for either product. Headplane and the NetBird
  dashboard were scored on architecture, not on use.
- **NetBird's relay was not made to work.** I established that the nixpkgs
  module contains no relay support and that the clients found none; I did not
  determine whether a hand-rolled `netbird-relay` or a client downgrade would
  fix it. It is possible NetBird is fine with more effort — the point is the
  effort, on a component that is load-bearing for reliability.
- **Neither product was run under real load.** MTU was probed with ICMP; no
  throughput or sustained cross-site traffic test was done. Phase 7's
  full-MTU pod-to-pod check remains necessary.
- **Version skew was present throughout** (tailscale 1.98.3 vs 1.98.10; netbird
  client 0.71.4 vs 0.76.0 vs server 0.69.0) because each host resolves its own
  nixpkgs pin. Phase 3 should pin overlay packages from one nixpkgs for all
  hosts.

---

## 8. Reproduction notes

Control server (Headscale), on ionos:

```sh
headscale serve --config /var/lib/headscale-spike/config.yaml
headscale --config … users create spike
headscale --config … preauthkeys create --user 1 --reusable --expiration 48h
headscale --config … nodes approve-routes --identifier <id> --routes <cidr>
```

Client, per host:

```sh
tailscaled --state=… --socket=… --port=41641 --tun=ts-spike0
tailscale --socket=… up \
  --login-server=https://headscale-spike.mvissing.de:8443 \
  --authkey=… --hostname=… --advertise-routes=<site cidr> \
  --accept-dns=false --accept-routes
```

`--accept-dns=false` was deliberate: the spike must not touch either host's
resolver. Phase 4 decides DNS.

Certificate, without handing over DNS credentials:

```sh
certbot certonly --manual --preferred-challenges dns \
  --manual-auth-hook <hook that publishes $CERTBOT_VALIDATION and waits> \
  -d headscale-spike.mvissing.de
```

The hook must have coreutils on `PATH`; under `systemd-run` it does not by
default, and a hook that cannot `sleep` fails the challenge silently.

---

## 9. Teardown

All spike state is throwaway — none of it is in any host's NixOS config, and
every firewall change is a runtime `iptables` rule that a reboot or
`nixos-rebuild` clears.

### Already done (2026-08-05 17:49) — the whole NetBird side

Torn down early, because running both overlays at once contaminated the RTT
sampling (see §3.2):

| Host | Removed |
|---|---|
| ionos | units `netbird-mgmt-spike`, `netbird-signal-spike`, `dex-spike`, `coturn-spike`, `nginx-spike`; `/var/lib/netbird-spike` |
| ionos | runtime rules for TCP 8444, TCP 5349, UDP 49152–49200 |
| pi, maxdata | unit `netbird-spike`, `/var/lib/netbird-spike`; `wt0` gone, routing table 7120 / rule 110 gone |

### Still running at time of writing — safe to remove, measurements are complete

| Host | Item |
|---|---|
| ionos | unit `headscale-spike`, `/var/lib/headscale-spike` (incl. the LE cert and account) |
| ionos | runtime rules for TCP 8443, UDP 3478 |
| pi, maxdata | units `tailscaled-spike`, `ts-sampler`; `/var/lib/tailscale-spike`; `/run/tailscale-spike.sock` |
| pi, maxdata | `net.ipv4.ip_forward` / `net.ipv6.conf.all.forwarding` left at `1` |

### Final teardown

1. ~~Read the CSVs and record the figure.~~ **Done 2026-08-05 23:21** — see §3.2.
   Copies of both CSVs are the evidence behind the table there.
2. `systemctl stop ts-sampler tailscaled-spike` on pi and maxdata; remove
   `/var/lib/tailscale-spike`.
3. `systemctl stop headscale-spike` on ionos; remove `/var/lib/headscale-spike`.
4. Reset `ip_forward` / `forwarding` to `0` on pi and maxdata, or reboot.
5. **IONOS Cloud panel:** close TCP 8443 and UDP 3478. TCP 8444, TCP 5349 and
   UDP 49152–49200 are already unused host-side but are still open at the
   provider — close those too.
6. **IONOS DNS:** delete `headscale-spike.mvissing.de` A and AAAA, and the
   `_acme-challenge.headscale-spike.mvissing.de` TXT.

Note the Let's Encrypt certificate for `headscale-spike.mvissing.de` remains
valid until 2026-11-03 and is not auto-renewed; nothing depends on it after
teardown.

**Do not tear down before reading the 24-hour sampler output** (§3.2) — the CSVs
live on pi and maxdata under `/var/lib/tailscale-spike/`.

The FritzBox↔ionos WireGuard tunnel was not touched at any point and is
unaffected.
