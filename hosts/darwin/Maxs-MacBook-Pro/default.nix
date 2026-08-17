{
  config,
  lib,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  hostSpec = {
    username = "maxvissing";
    hostName = "Maxs-MacBook-Pro";
  };

  imports = map lib.custom.relativeToRoot [
    # User profiles
    "modules/profiles/core-user"
    "modules/profiles/development.nix"
    "modules/profiles/fonts.nix"
    "modules/profiles/gcloud.nix"
    "modules/profiles/full-nvim.nix"
    "modules/profiles/darwin-nvim.nix"
    "modules/profiles/personal-ssh.nix"
    "modules/profiles/projects.nix"
    # Applications
    "modules/apps/google-chrome.nix"
    "modules/apps/discord.nix"
    "modules/apps/intellij"
    "modules/apps/rust-rover.nix"
    "modules/apps/vlc.nix"
    "modules/apps/ghostty.nix"
    "modules/apps/affinity.nix"
    "modules/apps/bambu-studio.nix"
    "modules/apps/autodesk-fusion.nix"
    "modules/apps/arc.nix"
    "modules/apps/docker-desktop.nix"
    "modules/apps/insomnia.nix"
    "modules/apps/k9s.nix"
    "modules/apps/kubeconfig.nix"
    # Overlay client, for when this machine is at neither site. In-site access
    # does not need it — the `brink` and `winkel` kubeconfig contexts reach the
    # API directly over each site's LAN.
    #
    # ⚠️ Registration is manual and the flags are not optional. **Both flipped
    # on 2026-08-09** — this used to be `--accept-routes=false
    # --accept-dns=false`:
    #
    #   tailscale up --login-server=https://headscale.mvissing.de \
    #                --accept-routes --accept-dns
    #
    # A roaming client needs *both* to reach anything, and neither alone is
    # enough — which is why the estate looked like it had one DNS bug rather
    # than two independent faults:
    #
    #   --accept-dns   so `*.mvissing.de` resolves to a site ingress VIP at all.
    #                  ionos's roaming AdGuard now rewrites to Brink's
    #                  192.168.1.240 (modules/system/roaming-dns.nix); without
    #                  this flag the machine uses whatever the café hands it,
    #                  which returns the public edge and 404.
    #   --accept-routes  so that VIP is *reachable*. It is a LAN address behind
    #                  brink-server's subnet router; without the route the name
    #                  resolves and then times out, which reads as an outage.
    #
    # ⚠️ **`--accept-routes` is genuinely dangerous on this machine and the
    # mitigation is client-side, not a flag.** 3.6.1 is exactly this failure: an
    # accepted route covering the subnet you are *sitting on* outranks your own
    # LAN route and takes the LAN away — it cost maxdata its network. This
    # laptop moves between both advertised sites, so it must never be on the
    # mesh while on either LAN. Enforce that with the Tailscale app's
    # **on-demand rules: connect except on the Brink and Winkel SSIDs**, which
    # is also what preserves Phase 4's split-horizon at home.
    #
    # ⚠️ macOS route precedence is *not* Linux's `ip rule` priority 5270, so the
    # 3.6.1 failure may present differently or not at all here. Untested on
    # purpose — the on-demand rule means we never find out, and that is the
    # point. Do not remove it on the grounds that "it seemed fine once".
    #
    # In-site access still does not need any of this: the `brink` and `winkel`
    # kubeconfig contexts reach the API directly over each site's LAN.
    "modules/apps/tailscale.nix"
    "modules/apps/opencode"
    "modules/apps/1password.nix"
    "modules/apps/teleport.nix"
  ];

  # Ad-hoc packages & Pulumi secrets (personal use only)
  home-manager.users.${config.hostSpec.username} = {config, ...}: {
    sops = {
      defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
      defaultSopsFormat = "yaml";
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      # ⚠️ Render secrets somewhere that survives a reboot.
      #
      # The default is `%r/secrets.d`, where `%r` is the runtime directory. On
      # Linux that is a tmpfs which systemd re-populates at boot, so secrets
      # reappear. **On macOS `%r` is `$TMPDIR`** —
      # `/var/folders/…/T/secrets.d` — which the OS clears, and nothing
      # re-renders it until the next `darwin-rebuild switch`. Every secret
      # therefore silently vanishes on reboot: `~/.kube/config` becomes a
      # dangling symlink, and the `$(cat …)` calls below fail on every new
      # shell.
      #
      # Persisting them means the plaintext lives on disk rather than in a
      # temp dir. That is an acceptable trade here and not really a new one:
      # the age key that decrypts everything already sits at
      # ~/.config/sops/age/keys.txt, and the disk is FileVault-encrypted.
      defaultSecretsMountPoint = "${config.home.homeDirectory}/.config/sops-nix/secrets.d";
    };

    # personal/pulumi-token and personal/pulumi-passphrase are gone (moved off
    # sops 2026-08-16): the homelab-k8s stack's secrets provider is now
    # Pulumi Cloud's per-stack managed key rather than a local passphrase, and
    # `~/.pulumi/credentials.json` (from `pulumi login`) already authenticates
    # the CLI without PULUMI_ACCESS_TOKEN.

    home.packages = with pkgs; [
      ffmpeg_6
      rclone
    ];
  };
}
