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
    # ⚠️ Registration is manual and the flags are not optional:
    #
    #   tailscale up --login-server=https://headscale.mvissing.de \
    #                --accept-routes=false --accept-dns=false
    #
    # `--accept-routes=false` because this machine *moves between the sites
    # whose subnets are advertised on the mesh*, and 3.6.1 is exactly that
    # failure: an accepted route covering the subnet you are sitting on
    # outranks your own LAN route and takes the LAN away. It is also
    # unnecessary — each router already has a static route to the other site.
    #
    # `--accept-dns=false` because Phase 4 put DNS on the site's own AdGuard,
    # and the overlay must not rewrite the resolver as a side effect of
    # joining. nix-darwin's `overrideLocalDns` already defaults to false; this
    # is the client-side half of the same decision.
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

      secrets."personal/pulumi-token" = {};
      secrets."personal/pulumi-passphrase" = {};
    };

    programs.zsh.initContent = lib.mkAfter ''
      export PULUMI_ACCESS_TOKEN=$(cat ${config.sops.secrets."personal/pulumi-token".path})
      export PULUMI_CONFIG_PASSPHRASE=$(cat ${config.sops.secrets."personal/pulumi-passphrase".path})
    '';

    home.packages = with pkgs; [
      ffmpeg_6
      rclone
    ];
  };
}
