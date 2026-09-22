# OpenCode desktop app, straight from nixpkgs - tracks the CLI there too.
{pkgs, ...}: {
  environment.systemPackages = [pkgs.opencode-desktop];
}
