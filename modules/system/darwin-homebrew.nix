# Homebrew infrastructure + shared hardware casks - included on every darwin host via flake.nix
{
  config,
  inputs,
  ...
}: {
  nix-homebrew = {
    user = config.hostSpec.username;
    enable = true;
    enableRosetta = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };
    mutableTaps = false;
    autoMigrate = false;
  };

  homebrew = {
    enable = true;
    taps = builtins.attrNames config.nix-homebrew.taps;
    onActivation = {
      # Taps are store-pinned (mutableTaps = false), so `brew update` has
      # nothing to move - new versions arrive via Renovate bumping the tap
      # inputs, then land with the next darwin-rebuild.
      autoUpdate = false;
      cleanup = "uninstall";
      # ⚠️ Deliberately NOT upgrade = true: activation runs `brew upgrade`
      # during darwin-rebuild, and .pkg casks (macfuse, displaylink) then
      # demand a sudo prompt mid-rebuild. Upgrades run from the user-owned
      # LaunchAgent instead (modules/system/darwin-brew-update.nix), which
      # skips casks with auto_updates - the pkg casks among them wait for
      # their bundle reinstall at the next rebuild, as before.
      upgrade = false;
    };
    # CLI formulae that should track brew, not nixpkgs (updates via the
    # brew-autoupdate LaunchAgent rather than flake bumps).
    brews = ["claude-code"];
    # Shared hardware/driver casks that every Mac needs
    casks = [
      "displaylink"
      "elgato-stream-deck"
      "focusrite-control"
      "macfuse"
      "logi-options+"
      "logitune"
    ];
  };
}
