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
    // lib.optionalAttrs pkgs.stdenv.isLinux {
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
    ++ lib.optionals pkgs.stdenv.isLinux [
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