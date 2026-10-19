# 1Password - homebrew cask
{...}: {
  # ⚠️ Pinned to /Applications so a host-wide `homebrew.caskArgs.appdir`
  # (kopf3-NB-26) cannot move it: the browser extensions and the SSH agent only trust the app in /Applications.
  homebrew.casks = [
    {
      name = "1password";
      args.appdir = "/Applications";
    }
  ];
}
