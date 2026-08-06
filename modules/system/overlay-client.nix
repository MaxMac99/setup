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
      useRoutingFeatures =
        if advertises
        then "both"
        else "client";

      extraUpFlags =
        [
          "--login-server=${net.overlay.controlServerUrl}"
          "--hostname=${config.hostSpec.hostName}"

          # Phase 4 owns DNS. The overlay must not rewrite either site's
          # resolver as a side effect of joining.
          "--accept-dns=false"

          # Accept the *other* site's advertised subnet. Without this a host
          # joins the mesh but still cannot reach the far LAN.
          "--accept-routes"
        ]
        ++ lib.optional advertises "--advertise-routes=${site.subnet}";
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
