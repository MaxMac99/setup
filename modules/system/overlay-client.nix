# Mesh overlay client — Tailscale against the self-hosted Headscale on ionos.
#
# Phase 3 of docs/multi-site-migration.md. Every host joins; two of them also
# advertise their site's subnet so unmodified LAN clients at one site can reach
# the other (networkConfig.hosts.<host>.subnetRouter).
#
# This is deliberately *not* in the cluster: all three home hosts are behind
# CGNAT, so the overlay is the only path between them for pod-to-pod traffic,
# and its control plane cannot depend on the thing it bootstraps.
{
  config,
  lib,
  ...
}: let
  cfg = config.overlayClient;
  net = config.networkConfig;
  self = net.hosts.${config.hostSpec.hostName} or null;
  site = if self == null || self.site == "public" then null else net.sites.${self.site};
  advertises = self != null && self.subnetRouter && site != null;
in {
  options.overlayClient = {
    enable = lib.mkEnableOption "the Tailscale overlay client";

    authKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "overlay_authkey";
      description = ''
        Name of the sops secret holding this host's Headscale pre-auth key.

        **Null by default, and that is load-bearing.** Headscale has to be
        running before it can mint a key, so the key cannot exist in
        `secrets/common.yaml` until after the control server's first deploy.
        Declaring `sops.secrets.<name>` for a key that is not in the file fails
        *activation*, which on a subnet router means losing the host. So the
        secret is only declared once this is set, and the client simply runs
        unauthenticated until then — `tailscaled` starts, `tailscale up` does
        not run, and nothing else on the host is affected.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.mkIf (cfg.authKeySecret != null) {
      ${cfg.authKeySecret} = {
        sopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
        restartUnits = ["tailscaled-autoconnect.service"];
      };
    };

    services.tailscale = {
      enable = true;
      openFirewall = true;

      authKeyFile = lib.mkIf (cfg.authKeySecret != null) config.sops.secrets.${cfg.authKeySecret}.path;

      # "both" also turns on net.ipv4.conf.all.forwarding and
      # net.ipv6.conf.all.forwarding (tailscale.nix), which is what Phase 3
      # item 4 requires — Phase 2 measured ip_forward = 0 on both candidates
      # and subnet routing fails silently without it.
      #
      # "none" rather than "client" for everyone else, to match the
      # --accept-routes decision below: "client" exists to loosen reverse-path
      # filtering for accepted routes, and a host that accepts none does not
      # want its rp_filter relaxed for nothing.
      useRoutingFeatures =
        if advertises
        then "both"
        else "none";

      extraUpFlags =
        [
          "--login-server=${net.overlay.controlServerUrl}"
          "--hostname=${config.hostSpec.hostName}"

          # Phase 4 owns DNS. The overlay must not rewrite either site's
          # resolver as a side effect of joining.
          "--accept-dns=false"
        ]
        ++ lib.optionals advertises [
          "--advertise-routes=${site.subnet}"

          # ⚠️ **Only subnet routers accept routes, and this is not a
          # preference — it is a correctness requirement.** Learned by breaking
          # maxdata on 2026-08-06.
          #
          # Accepting routes installs them in table 52, which tailscale
          # consults via `ip rule` at priority **5270 — ahead of the main table
          # at 32766**. So an accepted route for a prefix the host is
          # *directly connected to* silently outranks its own LAN route.
          #
          # maxdata accepted winkel-pi's 192.168.178.0/24 — its own subnet —
          # and every reply to a LAN neighbour went into the tunnel instead of
          # out vmbr0. Incoming worked, outgoing did not: ARP fine, ping dead,
          # host reachable only over the overlay. ionos failed differently and
          # more quietly: its wg0 carries 192.168.178.201/24, so the accepted
          # route displaced the **FritzBox tunnel**, dissolving the second
          # independent path into Winkel that Phase 13 still depends on, while
          # everything appeared to work.
          #
          # Subnet routers are safe because tailscale never installs an
          # accepted route for a prefix the node itself advertises — which is
          # exactly why brink-server was unaffected while maxdata was not.
          #
          # Non-routers lose nothing that matters: every overlay peer stays
          # reachable at its 100.64.0.0/10 address, and reaching the *far
          # site's LAN* is the subnet router's job by construction (3.1).
          "--accept-routes"
        ];
    };

    # Routes are advertised, not granted: they stay inactive until approved on
    # the control server. `headscale nodes approve-routes --identifier <id>
    # --routes <cidr>` — a silent no-op to forget, because the client reports
    # itself perfectly healthy while the far side is unreachable.
    warnings =
      lib.optional (advertises && cfg.authKeySecret == null)
      "overlayClient: ${config.hostSpec.hostName} is a subnet router but has no auth key yet; it will not join until overlayClient.authKeySecret is set.";
  };
}
