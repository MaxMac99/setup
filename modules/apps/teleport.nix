# Teleport access platform client (tsh, tctl, tbot)
{pkgs, ...}: {
  environment.systemPackages = [pkgs.teleport];
}
