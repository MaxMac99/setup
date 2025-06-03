{ pkgs, config, ... }:
{
  nix = {
    package = pkgs.nix;

    settings = {
      allowed-users = [ "@admin" "${config.user}" ];
      trusted-users = [ "@admin" "${config.user}" ];
      experimental-features = [ "nix-command" "flakes" ];
    };

    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 1w";
    };
  };
}
