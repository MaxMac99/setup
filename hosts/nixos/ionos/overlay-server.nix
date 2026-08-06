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

    # Bind the public interface on 443 directly rather than proxying. Phase 2
    # proved plain HTTP on an alternate port is a trap: after any control
    # interruption the client escalates to HTTPS and then to 443, and if
    # nothing answers there it wedges permanently (§2.1). 443 is free because
    # the ingress it used to be DNAT'd to has been dead since before Phase 0 —
    # see the removed rules in default.nix.
    #
    # port < 1024 makes the module grant CAP_NET_BIND_SERVICE, which also
    # covers the ACME listener on 80.
    address = "0.0.0.0";
    port = 443;

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
      tls_letsencrypt_listen = ":80";

      dns = {
        magic_dns = true;
        # Must differ from the server_url hostname — Headscale rejects the
        # config otherwise.
        base_domain = overlay.magicDnsBaseDomain;
        # Phase 4 owns resolvers. Clients pass --accept-dns=false, so this
        # names nodes without touching either site's DNS.
        override_local_dns = false;
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
