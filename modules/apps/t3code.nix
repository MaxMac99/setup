# T3 Code - homebrew cask; nixpkgs trails upstream (0.0.40 vs 0.0.42 as of
# 2026-09), the cask carries auto_updates.
{...}: {
  homebrew.casks = ["t3-code"];
}
