# User config applicable to both nixos and darwin
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (config) hostSpec;
  pubKeys = lib.filesystem.listFilesRecursive ./keys;
in
  {
    users.users.${hostSpec.username} = {
      name = hostSpec.username;
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
    ];
  }
  # Import the user's personal/home configurations, unless the environment is minimal
  // lib.optionalAttrs (inputs ? "home-manager") {
    home-manager = {
      extraSpecialArgs = {
        inherit pkgs inputs;
        inherit (config) hostSpec;
      };
      users.${hostSpec.username}.imports = lib.flatten [
        (
          {config, ...}:
            import (lib.custom.relativeToRoot "home/${hostSpec.hostName}.nix") {
              inherit
                pkgs
                inputs
                config
                lib
                hostSpec
                ;
            }
        )
      ];
    };
  }
