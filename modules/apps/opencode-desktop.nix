# OpenCode desktop app from nixpkgs - same pin as the CLI in modules/apps/opencode.
{pkgs, ...}: {
  environment.systemPackages = [pkgs.opencode-desktop];
}
