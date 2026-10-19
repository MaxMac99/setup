# Docker Desktop for macOS - homebrew cask
{...}: {
  # ⚠️ Pinned to /Applications so a host-wide `homebrew.caskArgs.appdir`
  # (kopf3-NB-26) cannot move it: its privileged helper refuses to install from anywhere else.
  homebrew.casks = [
    {
      name = "docker-desktop";
      args.appdir = "/Applications";
    }
  ];
}
