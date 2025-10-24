# User config applicable to both nixos and darwin
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  pubKeys = lib.filesystem.listFilesRecursive ./keys;
  cfg = config.hostSpec;
in {
  users.users.${cfg.username} = {
    name = cfg.username;
    shell = pkgs.zsh; # default shell

    # These get placed into /etc/ssh/authorized_keys.d/<name> on nixos
    openssh.authorizedKeys.keys = lib.lists.forEach pubKeys (key: builtins.readFile key);
  };

  # No matter what environment we are in we want these tools
  programs.zsh.enable = true;
  environment.systemPackages = with pkgs; [
    rsync
    curl
    vim
    git
    inetutils
  ];

  # Import the user's personal/home configurations
  # Skip home-manager for minimal hosts (they use system-wide config instead)
  home-manager = lib.mkIf (!cfg.isMinimal) {
    extraSpecialArgs = {
      inherit pkgs inputs;
      hostSpec = cfg;
    };

    users.${cfg.username} = {
      imports = lib.flatten [
        # Always import common core home-manager config
        (lib.custom.relativeToRoot "home/common/core")
      ] ++ lib.optionals (builtins.pathExists (lib.custom.relativeToRoot "home/${cfg.hostName}.nix")) [
        # Conditionally import host-specific config if it exists
        (
          {config, ...}:
            import (lib.custom.relativeToRoot "home/${cfg.hostName}.nix") {
              inherit
                pkgs
                inputs
                config
                lib
                ;
              hostSpec = cfg;
            }
        )
      ];
    };
  };
}
