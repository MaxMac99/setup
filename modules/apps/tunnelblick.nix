# VPN client - homebrew cask
{...}: {
  # ⚠️ Pinned to /Applications so a host-wide `homebrew.caskArgs.appdir`
  # (kopf3-NB-26) cannot move it: it refuses to run its VPN helper from anywhere else.
  homebrew.casks = [
    {
      name = "tunnelblick";
      args.appdir = "/Applications";
    }
  ];
}
