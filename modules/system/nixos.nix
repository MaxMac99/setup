# NixOS base configuration - included on every NixOS host via flake.nix
{
  i18n.defaultLocale = "en_US.UTF-8";

  security.sudo.wheelNeedsPassword = false;

  nix.gc.dates = "weekly";
}