# Self-hosted GitHub Actions runners for the iOS jobs of meals and photonic.
# The Linux jobs of both repos run on ARC in the cluster (homelab-k8s
# infrastructure/github-runner.ts); only the Xcode work lands here.
#
# ⚠️ LaunchAgents as the logged-in user, deliberately *not* nix-darwin's
# `services.github-runners`. That module runs a LaunchDaemon (as
# `_github-runner` by default), which has no GUI session — and both repos run
# `xcodebuild test` on the iOS Simulator, which needs one. GitHub's own
# `svc.sh` installs a LaunchAgent on macOS for the same reason. The daemon
# would also break `brew install xcodegen` (nix-homebrew's /opt/homebrew
# belongs to this user and brew refuses other users) and its PATH hides
# /usr/bin/xcodebuild. The cost: jobs run with this user's home and keychain
# in reach. Acceptable because both repos are private and only the owner
# pushes; never point one of these at a public repo.
#
# Runners only run while this user is logged in. Lid closed or logged out →
# jobs queue, and GitHub cancels a job still queued after 24 h.
#
# Registration is one-time and manual, so no PAT lives on this machine. Per
# repo: GitHub → Settings → Actions → Runners → New self-hosted runner, copy
# the token from the `config.sh` line (valid 1 h), then
#
#   github-runner-register meals <token>
#
# The runner keeps its own credentials in its root after that. Until then the
# agent logs "not registered" and exits cleanly instead of crash-looping.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.hostSpec.username;
  home = config.hostSpec.home;
  package = pkgs.github-runner;

  repos = ["meals" "photonic"];
  rootOf = repo: "${home}/.local/share/github-runners/${repo}";

  # Xcode's tools live in /usr/bin, brew's in /opt/homebrew/bin; launchd hands
  # agents a bare PATH, so set it here like darwin-brew-update.nix does.
  # home.packages (xcodegen, from xcode.nix) land in ~/.nix-profile, not
  # /etc/profiles/per-user: useUserPackages stays false (base.nix).
  #
  # ⚠️ Apple's rsync must win. Xcode's IPA export runs /usr/bin/rsync -E,
  # which spawns its receiving side as whatever `rsync` PATH finds first —
  # base.nix's GNU rsync 3.x, which rejects --extended-attributes, and the
  # export fails with a bare "Copy failed". Only rsync is pinned; everything
  # else keeps the nix-first order.
  appleRsync = pkgs.runCommand "apple-rsync" {} ''
    mkdir -p $out/bin
    ln -s /usr/bin/rsync $out/bin/rsync
  '';
  path = lib.concatStringsSep ":" [
    "${appleRsync}/bin"
    "/opt/homebrew/bin"
    "${home}/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  run = repo:
    pkgs.writeShellApplication {
      name = "github-runner-${repo}";
      text = ''
        export PATH="${path}"
        export RUNNER_ROOT="${rootOf repo}"
        if [[ ! -f "$RUNNER_ROOT/.runner" ]]; then
          echo "not registered: run 'github-runner-register ${repo} <token>'"
          exit 0
        fi
        exec ${lib.getExe' package "Runner.Listener"} run --startuptype service
      '';
    };

  register = pkgs.writeShellApplication {
    name = "github-runner-register";
    text = ''
      repo="''${1:?usage: github-runner-register <${lib.concatStringsSep "|" repos}> <token>}"
      token="''${2:?usage: github-runner-register <repo> <token>}"
      case "$repo" in
        ${lib.concatStringsSep "|" repos}) ;;
        *) echo "unknown repo: $repo" >&2; exit 1 ;;
      esac
      export RUNNER_ROOT="${home}/.local/share/github-runners/$repo"
      mkdir -p "$RUNNER_ROOT"
      ${lib.getExe' package "config.sh"} \
        --unattended --disableupdate --replace \
        --url "https://github.com/MaxMac99/$repo" \
        --token "$token" \
        --name "${config.hostSpec.hostName}-$repo" \
        --labels macbook \
        --work "$RUNNER_ROOT/_work"
      launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.github-runner-$repo"
    '';
  };
in {
  home-manager.users.${username} = {
    home.packages = [register];

    launchd.agents = lib.listToAttrs (map (repo: {
        name = "github-runner-${repo}";
        value = {
          enable = true;
          config = {
            ProgramArguments = [(lib.getExe (run repo))];
            RunAtLoad = true;
            # Restart on crash, not after the clean "not registered" exit.
            KeepAlive.SuccessfulExit = false;
            ThrottleInterval = 30;
            ProcessType = "Interactive";
            # Not under the runner root: it does not exist before
            # registration, and launchd creates no parent directories.
            StandardOutPath = "${home}/Library/Logs/github-runner-${repo}.log";
            StandardErrorPath = "${home}/Library/Logs/github-runner-${repo}.log";
          };
        };
      })
      repos);
  };
}
