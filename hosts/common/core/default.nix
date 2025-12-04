{
  inputs,
  config,
  lib,
  isDarwin,
  ...
}: let
  platform =
    if isDarwin
    then "darwin"
    else "nixos";
  platformModules = "${platform}Modules";
in {
  imports = lib.flatten [
    inputs.home-manager.${platformModules}.home-manager
    inputs.sops-nix.${platformModules}.sops
    ./${platform}.nix

    (map lib.custom.relativeToRoot [
      "modules/common"
      "hosts/common/users/primary"
      "hosts/common/users/primary/${platform}.nix"
    ])
  ];

  hostSpec = {
    handle = "MaxMac99";
  };

  time.timeZone = "Europe/Berlin";

  networking = {
    inherit (config.hostSpec) hostName;
    domain = lib.mkDefault config.networkConfig.domain;
  };

  # Force home-manager to use global packages
  home-manager.useGlobalPkgs = true;

  #
  # ======== Nix Settings ========
  #
  nix = {
    settings = {
      connect-timeout = 5;

      allowed-users = ["@admin" "${config.hostSpec.username}"];
      trusted-users = ["@admin" "${config.hostSpec.username}"];
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
}
