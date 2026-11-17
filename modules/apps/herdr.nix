# Herdr - native desktop app for terminals and coding agents; homebrew cask,
# self-updating (auto_updates). Apple silicon only. The `herdr` formula /
# nixpkgs package is the separate TUI and does not share agents with the app.
{...}: {
  homebrew.casks = ["herdr-app"];
}
