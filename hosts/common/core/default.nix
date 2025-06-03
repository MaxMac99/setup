{ inputs
, config
, lib
, isDarwin
, ...
}:
let
  platform = if isDarwin then "darwin" else "nixos";
  platformModules = "${platform}Modules";
in
{
  imports = lib.flatten [
    inputs.home-manager.${platformModules}.home-manager
    inputs.sops-nix.${platformModules}.sops

    (map lib.custom.relativeToRoot [
      "modules/common"
      "hosts/common/users/primary"
      "hosts/common/users/primary/${platform}.nix"
    ])
  ];

  hostSpec = {
    handle = "MaxMac99";
  };

  networking.hostName = config.hostSpec.hostName;

  # Force home-manager to use global packages
  home-manager.useGlobalPkgs = true;

  #
  # ======== Nix Settings ========
  #
  nix = {
    settings = {
      connect-timeout = 5;

      allowed-users = [ "@admin" "${config.hostSpec.username}" ];
      trusted-users = [ "@admin" "${config.hostSpec.username}" ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 1w";
    };
  };
}
