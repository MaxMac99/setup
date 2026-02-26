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
      autoUpdate = true;
      cleanup = "uninstall";
      upgrade = true;
    };
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