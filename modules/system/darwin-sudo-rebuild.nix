# Passwordless darwin-rebuild for the primary user.
#
# nix-darwin's activation must run as root (`activate` writes /etc, user
# accounts, /Library/LaunchDaemons - see activation-scripts.nix), so a
# fully sudo-free `switch` is architecturally impossible. What CAN be
# removed is the password prompt: this drop-in grants NOPASSWD for exactly
# the flake-rebuild entry points, nothing else. It lands as
# /etc/sudoers.d/20-nix-darwin-rebuild on the next sudo-needing rebuild
# and survives, because darwin-rebuild always writes its own sudoers.d.
{
  config,
  lib,
  ...
}: {
  security.sudo.extraConfig = lib.mkAfter ''
    # managed by modules/system/darwin-sudo-rebuild.nix
    ${config.hostSpec.username} ALL=(root) NOPASSWD: SETENV: /run/current-system/sw/bin/darwin-rebuild
  '';
}
