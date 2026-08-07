# Headscale — the mesh overlay control server. Phase 3.
#
# Lives on ionos because it is the only host with a fixed, reachable address:
# both sites are on Deutsche Glasfaser DS-Lite behind CGNAT, so neither can be
# dialled from outside and neither can be the rendezvous point (D2).
#
# ⚠️ Cold start depends on this service. A host that reboots while ionos is
# unreachable loses the overlay entirely and does not recover until control
# returns (overlay-evaluation §3.5). That is why the FritzBox WireGuard tunnel
# stays up as an independent path until Phase 13.
{
  config,
  lib,
  ...
}: let
  overlay = config.networkConfig.overlay;
in {
  services.headscale = {
    enable = true;

    # ⚠️ **Stage B (D16): nginx owns the public :443 now and splits it by SNI**,
    # so Headscale moved off the public socket onto loopback.
    #
    # Phase 2's finding is unchanged and is *why* the public :443 must still
    # answer TLS for this hostname: after any control interruption the client
    # escalates to HTTPS and then to 443, and if nothing answers there it wedges
    # permanently (§2.1). The split is **TCP passthrough via `ssl_preread`**, not
    # termination — Headscale still presents its own certificate and still runs
    # its own ACME, so the escalation path and the trust chain are both exactly
    # as they were. What changed is only which process accepts the socket.
    #
    # ⚠️ **8444, not 8443**: the public Traefik runs hostNetwork on this node and
    # already binds `*:8443` for its `websecure` entrypoint. Picking 8443 here
    # would leave whichever process started second unable to bind.
    #
    # ⚠️ The old comment noted that `port < 1024` earned the unit
    # CAP_NET_BIND_SERVICE. That no longer applies and nothing needs it: the
    # ACME listener is on 8081 and this socket is on 8444, both unprivileged.
    address = "127.0.0.1";
    port = 8444;

    settings = {
      server_url = overlay.controlServerUrl;

      prefixes.v4 = overlay.prefixV4;

      # Headscale terminates TLS itself. HTTP-01 needs no DNS API credential,
      # which is the cheap path now that port 80 is free — the alternative is
      # an IONOS DNS token, and that is Phase 9's problem (D8), not a
      # dependency the overlay should acquire. Phase 2 issued its certificate
      # by *manual* DNS-01, which is not viable for 90-day renewal on the
      # service the whole network depends on.
      tls_letsencrypt_hostname = overlay.controlServerHost;
      tls_letsencrypt_challenge_type = "HTTP-01";

      # ⚠️ Loopback, not `:80` — and nginx now owns the public :80 (D16,
      # ./public-ingress.nix). Renewal still works because that nginx routes
      # `Host: headscale.mvissing.de` straight back here; it is a hop, not a
      # change of protocol. Move this port and you must move the proxy_pass
      # with it, or Headscale's certificate quietly stops renewing and the
      # overlay control plane fails ~90 days later, far from the change.
      #
      # 8081 rather than 8080 on purpose: the public Traefik runs hostNetwork
      # on this node and its dashboard port takes 8080.
      #
      # ⚠️ **Stage B changed the risk here.** Headscale no longer owns a public
      # socket at all, so the overlay's reachability *does* now depend on nginx
      # being healthy — for both :80 and :443. That was the explicit cost of
      # D16 Stage B, accepted because ionos remains reachable on public SSH
      # (port 22) independently of nginx, so a broken split is recoverable
      # without the overlay.
      tls_letsencrypt_listen = "127.0.0.1:8081";

      dns = {
        magic_dns = true;
        # Must differ from the server_url hostname — Headscale rejects the
        # config otherwise.
        base_domain = overlay.magicDnsBaseDomain;

        # D15 step 2 — push the roaming resolver to every client.
        #
        # ⚠️ This used to be `override_local_dns = false` with the note that
        # "Phase 4 owns resolvers". Phase 4 owns the *sites*; it left a client
        # at **neither** site with no ad-blocking and no split-horizon, which
        # is the gap D15 exists to close.
        #
        # `global` names the AdGuard in ./roaming-dns.nix on this same host.
        # The address comes from networkConfig so the two cannot drift —
        # roaming-dns.nix asserts it equals the address it binds.
        #
        # ⚠️ **`override_local_dns = true` replaces the client's resolver, it
        # does not supplement it.** That is what makes the setting useful and
        # also what makes a mistake total: if this address stops answering,
        # every client that accepts tailnet DNS loses name resolution outright
        # the moment the VPN connects, rather than degrading.
        #
        # ⚠️ Safe fleet-wide only because `--accept-dns=false` is client-side
        # and every NixOS host sets it (modules/system/overlay-client.nix:78).
        # Headscale pushes this to all of them; they all ignore it. Drop that
        # flag on a host and it silently starts resolving through this VPS,
        # losing split-horizon — so a host at a site would resolve
        # `paperless.mvissing.de` to the public edge and get a 404.
        #
        # ⚠️ Open question, to settle when the phone's `--accept-dns=true` goes
        # on: a phone with always-on VPN follows this **at home too**, and then
        # gets the public address for `*.mvissing.de`, sending local traffic
        # out to ionos and back. Functional, but it discards Phase 4's
        # split-horizon. iOS Tailscale on-demand rules can disconnect on the
        # two home SSIDs, which keeps both behaviours correct. The Mac is
        # unaffected — it only joins the tailnet when away.
        override_local_dns = overlay.roamingResolver != null;
        nameservers.global = lib.optional (overlay.roamingResolver != null) overlay.roamingResolver;
      };

      # Embedded DERP, kept inside the estate. Phase 2 measured 347/347 direct
      # connections, so this is a fallback that should stay unused — but when
      # it is used, relaying through our own VPS beats relaying through
      # Tailscale's public infrastructure.
      derp = {
        # Empty: do not fetch Tailscale's public DERP map.
        urls = [];
        paths = [];
        auto_update_enabled = false;
        server = {
          enabled = true;
          region_id = overlay.derpRegionId;
          region_code = "ionos";
          region_name = "IONOS Frankfurt";
          stun_listen_addr = "0.0.0.0:${toString overlay.derpStunPort}";
        };
      };

      # Policy from a file in git, not from a database. See the file for why it
      # is permissive between nodes.
      policy = {
        mode = "file";
        path = lib.custom.relativeToRoot "modules/data/overlay-policy.hujson";
      };
    };
  };

  # STUN for NAT traversal.
  #
  # ⚠️ Opening it here is necessary but **not sufficient**. The IONOS Cloud
  # firewall is default-deny and invisible from inside the VPS: blocked packets
  # never reach `ens6`, so both the host firewall and tcpdump show nothing at
  # all. UDP 3478 and TCP 443 must also be opened in the IONOS web panel, or
  # this looks like a client bug for as long as you care to debug it.
  networking.firewall.allowedUDPPorts = [overlay.derpStunPort];
}
