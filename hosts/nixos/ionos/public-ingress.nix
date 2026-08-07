# Public ingress front end on ionos — Phase 9 / D16, Stage A.
#
# Public DNS wildcards *.mvissing.de onto this host (9.1a), so every hostname
# in the estate arrives here. Until now Headscale answered all of them: it held
# both :80 and :443 and serves only its own API, so ingress was not
# "unconfigured" but *shadowed* — names resolved and TLS completed against the
# wrong service. That is why every ACME HTTP-01 challenge returned 403 and no
# certificate could issue for any name.
#
# This module takes :80 only, and splits it by `Host`:
#
#   headscale.mvissing.de  → Headscale's own ACME listener on loopback
#   everything else        → the public Traefik, which serves cert-manager's
#                            HTTP-01 solver Ingresses
#
# **Stage B is now in too**, and :443 is split by SNI:
#
#   headscale.mvissing.de  → Headscale on loopback, PROXY header stripped first
#   everything else        → the public Traefik's `websecure`, PROXY intact
#
# Port 80 cannot be split by SNI: plaintext HTTP has none. Hence an `http`
# block matching on `Host` *and* a separate `stream` block for 443 — the two
# are not interchangeable and both are required.
#
# ⚠️ **Stage B moved a dependency that Stage A deliberately avoided.** Headscale
# no longer holds a public socket, so the overlay control plane now depends on
# this nginx being healthy. That was accepted, not overlooked: ionos answers
# public SSH on :22 independently of nginx, so a broken split is fixable
# without the overlay — which is what made the asymmetry in D16 (Brink has no
# independent way in) tolerable. Verify :22 still works before touching this.
#
# ⚠️ Nothing is *published* publicly by landing this. The public Traefik is
# default-closed: its ingress class is `traefik-public` and its CRD label
# selector is `ingress=public`, so a name only becomes reachable when something
# opts in explicitly. Stage B grants the capability, not the access.
{
  config,
  ...
}: let
  overlay = config.networkConfig.overlay;

  # Where Headscale's ACME listener moved to, so this nginx can own :80.
  # Must match `tls_letsencrypt_listen` in ./overlay-server.nix.
  headscaleAcme = "http://127.0.0.1:8081";

  # The public Traefik's `web` entrypoint.
  #
  # 8000 is the Traefik chart's *container* port for `web` — its `exposedPort:
  # 80` is the Service port, and this Traefik has no Service at all. The pod
  # runs hostNetwork pinned to ionos, so the container port is a host port and
  # loopback reaches it.
  traefikWeb = "http://127.0.0.1:8000";

  # Stage B — the three loopback sockets the :443 SNI split needs.
  #
  # ⚠️ All three are duplicated elsewhere and none of them is checked by
  # anything:
  #   8443 is the Traefik chart's container port for `websecure`
  #        (infrastructure/traefik-public.ts)
  #   8444 is `services.headscale.port` (./overlay-server.nix)
  #   9444 is local to this file
  traefikWebsecure = "127.0.0.1:8443";
  headscaleControl = "127.0.0.1:8444";

  # ⚠️ Exists only to *strip* the PROXY protocol header again.
  #
  # `proxy_protocol on` is a property of the `server` block, not of an upstream,
  # so the :443 splitter necessarily speaks it to whichever backend it selects.
  # Traefik wants that — it is the only way a passthrough proxy can tell it the
  # real client IP, since TCP passthrough leaves no room for `X-Forwarded-For`.
  # **Headscale does not implement PROXY protocol at all** (its documented
  # reverse-proxy story is HTTP with `trusted_proxies`, which passthrough
  # cannot use), and would treat the header as the first bytes of a TLS
  # ClientHello and drop the connection.
  #
  # So the Headscale path takes one extra loopback hop whose only job is to
  # parse the header and forward plain TCP. nginx preserves the original client
  # address across that hop, which is why the ordering works at all.
  headscaleStripProxy = "127.0.0.1:9444";

  # ⚠️ Explicit, because the NixOS module otherwise adds a :443 listener to
  # any vhost and that would collide with Headscale on startup.
  onPort80 = [
    {
      addr = "0.0.0.0";
      port = 80;
      ssl = false;
    }
    {
      addr = "[::]";
      port = 80;
      ssl = false;
    }
  ];
in {
  services.nginx = {
    enable = true;

    # Sets X-Forwarded-For / -Proto / -Host on proxied requests. Traefik is
    # told to trust them from loopback only — see infrastructure/traefik-public.ts.
    recommendedProxySettings = true;

    virtualHosts = {
      # Headscale renews its own certificate and terminates its own TLS. This
      # forwards only the ACME challenge. ⚠️ Since Stage B the control API
      # *does* pass through nginx as well — as raw TCP through the `stream`
      # block below, never through this `http` block.
      "${overlay.controlServerHost}" = {
        listen = onPort80;
        locations."/".proxyPass = headscaleAcme;
      };

      # Everything else. Chiefly cert-manager's HTTP-01 solver Ingresses, which
      # exist for a few seconds per challenge.
      #
      # ⚠️ A 404 here is the expected steady state — no challenge is in flight
      # most of the time, and the public Traefik has no routes of its own until
      # Stage B. A 502 means the Traefik pod is not running; that is the
      # failure worth alerting on, not the 404.
      "public-ingress" = {
        default = true;
        listen = onPort80;
        locations."/".proxyPass = traefikWeb;
      };
    };

    # Stage B — the :443 SNI split.
    #
    # Plaintext HTTP has no SNI, which is why :80 above is an `http` block
    # matching on `Host` and this is a separate `stream` block. Both are needed;
    # neither replaces the other.
    #
    # ⚠️ **Passthrough, not termination.** nginx reads only the SNI field of the
    # ClientHello and then copies bytes. It holds no certificate and no private
    # key for any of these names: Headscale keeps its own ACME, and Traefik
    # keeps cert-manager's per-hostname Secrets. That property is the whole
    # reason D16 chose this over terminating here.
    streamConfig = ''
      map $ssl_preread_server_name $publicBackend {
        ${overlay.controlServerHost}  ${headscaleStripProxy};
        default                       ${traefikWebsecure};
      }

      server {
        listen 0.0.0.0:443;
        listen [::]:443;

        ssl_preread on;
        proxy_pass $publicBackend;

        # Both backends receive the PROXY protocol header; the Headscale path
        # has it stripped one hop later. See the `let` block above.
        proxy_protocol on;

        # ⚠️ Not tuning. Tailscale clients hold a long-poll control connection
        # open, and nginx's stream default is a 10-minute *inactivity* timeout,
        # which would tear down an idle-but-healthy control connection and make
        # the overlay look flaky in a way that points at everything except this
        # line.
        proxy_timeout 1h;
      }

      server {
        listen ${headscaleStripProxy} proxy_protocol;
        proxy_pass ${headscaleControl};
        proxy_timeout 1h;
      }
    '';
  };

  # No firewall change: 80 and 443 are already open (./default.nix). The ports
  # behind this — 8000, 8081, 8443, 8444 and 9444 — are not, which is what
  # keeps them private. The IONOS Cloud firewall is default-deny in front of
  # that as a second layer.
  #
  # ⚠️ 8443 is bound by Traefik on `*`, not on loopback, because the chart runs
  # hostNetwork and does not offer a bind address. It is unreachable from the
  # internet only because both firewalls drop it. Losing either one exposes an
  # ingress that expects to be spoken to in PROXY protocol by a trusted peer.
}
