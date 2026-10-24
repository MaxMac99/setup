{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  hostSpec = {
    username = "maxvissing";
    hostName = "kopf3-NB-26";
  };

  imports = map lib.custom.relativeToRoot [
    # User profiles
    "modules/profiles/core-user"
    "modules/profiles/development.nix"
    "modules/profiles/fonts.nix"
    "modules/profiles/gcloud.nix"
    "modules/profiles/full-nvim.nix"
    "modules/profiles/darwin-nvim.nix"
    "modules/profiles/work.nix"
    "modules/profiles/projects.nix"
    # Applications
    "modules/apps/google-chrome.nix"
    "modules/apps/intellij"
    "modules/apps/rust-rover.nix"
    "modules/apps/ghostty.nix"
    "modules/apps/affinity.nix"
    "modules/apps/tunnelblick.nix"
    "modules/apps/tailscale.nix"
    "modules/apps/1password.nix"
    "modules/apps/bambu-studio.nix"
    "modules/apps/autodesk-fusion.nix"
    "modules/apps/arc.nix"
    "modules/apps/zen.nix"
    "modules/apps/docker-desktop.nix"
    "modules/apps/insomnia.nix"
    "modules/apps/k9s.nix"
    "modules/apps/opencode"
    "modules/apps/opencode-desktop.nix"
    "modules/apps/claude-code"
    "modules/apps/t3code.nix"
  ];

  home-manager.users.maxvissing.home.packages = [pkgs.copier];

  # Casks install into ~/Applications here: the user is not in `admin` on this
  # Mac, and /Applications is root:admin 775, so every in-app updater that
  # swaps its bundle in place asked for an admin password. Casks that only run
  # from /Applications pin `args.appdir` back in their own module.
  homebrew.caskArgs.appdir = "~/Applications";
  # Same default for a manual `brew install --cask` between rebuilds
  # (docs/sudoless-workflow.md). The Brewfile run at rebuild is unaffected:
  # it does not inherit the user's session environment.
  home-manager.users.maxvissing.home.sessionVariables.HOMEBREW_CASK_OPTS = "--appdir=~/Applications";

  # Work Mac: fixed Homebrew update slots Tue + Thu 10:00 (launchd runs a
  # missed slot on next wake), plus a login catch-up guarded by the same
  # 3-day minimum interval as the private Mac - protects against double runs.
  brewAutoupdate = {
    enable = true;
    catchup = {
      enable = true;
      minDays = 3;
    };
    calendar = [
      {
        Weekday = 2; # Tuesday
        Hour = 10;
        Minute = 0;
      }
      {
        Weekday = 4; # Thursday
        Hour = 10;
        Minute = 0;
      }
    ];
  };

  # ~/.ssh/config is managed outside nix here, so home-manager must not generate
  # it (this also drops the blocks from projects.nix). The username is spelled
  # out because a `config.hostSpec.username` attr name would recurse into the
  # hostSpec defined above.
  home-manager.users.maxvissing.programs.ssh.enable = lib.mkForce false;
}
