# Universal system configuration - included on every host via flake.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.hostSpec;
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
  pubKeys = lib.filesystem.listFilesRecursive (lib.custom.relativeToRoot "modules/data/keys");
in {
  time.timeZone = "Europe/Berlin";

  networking = {
    inherit (cfg) hostName;
    domain = lib.mkDefault config.networkConfig.domain;
  };

  # User creation
  users.users.${cfg.username} =
    {
      name = cfg.username;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = lib.lists.forEach pubKeys (key: builtins.readFile key);
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      home = "/home/${cfg.username}";
      isNormalUser = true;
      extraGroups = lib.flatten [
        "wheel"
        (ifTheyExist [
          "docker"
          "git"
        ])
      ];
    };

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs;
    [
      rsync
      curl
      vim
      git
      inetutils
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      unixtools.netstat
    ];

  # Nix settings
  nix = {
    settings = {
      connect-timeout = 5;
      download-buffer-size = 268435456; # 256 MiB
      allowed-users = ["@admin" cfg.username];
      trusted-users = ["@admin" cfg.username];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://nixos-raspberrypi.cachix.org"
        # sops-install-secrets ships from the sops-nix *flake*, not nixpkgs, so
        # cache.nixos.org has never built it: without this every host compiles
        # it from source and runs its Go test suite whenever the input moves.
        # That cost ionos ~20 min in a single buildPhase on 2026-08-06 (3.0.5)
        # and applies to every sops-nix host, which is all of them.
        "https://nix-community.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
  };

  # Home-manager bootstrap (profiles set home-manager.users.* as needed)
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit pkgs inputs;
      hostSpec = cfg;
    };
  };
}
