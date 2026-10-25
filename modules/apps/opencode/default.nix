# OpenCode - terminal AI coding agent, fronted by Meridian
#
# Everything portable lives in ./core.nix; this module only adds what is
# Mac-specific: the brew binary, the profile wrapper, sops and launchd.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  core = import ./core.nix {inherit lib pkgs inputs;};
  inherit (core.meridian) host port;
  meridian = core.meridian.package;
in {
  # ⚠️ Must be declared: homebrew.onActivation.cleanup = "uninstall" removes
  # every formula not listed.
  homebrew.brews = ["opencode"];

  home-manager.users.${config.hostSpec.username} = {
    config,
    lib,
    ...
  }: let
    # OpenCode 2 comes from homebrew-core (nixpkgs is still on 1.x). The
    # wrapper below execs the keg's stable `opt` path, which exists whether or
    # not the formula is linked into /opt/homebrew/bin.
    # ⚠️ Brew's own /opt/homebrew/bin/opencode link sits ahead of
    # ~/.nix-profile/bin on PATH and would shadow the wrapper, silently dropping
    # Meridian, the profile split and the LSP setting. So unlink it. `brew
    # bundle` (darwin-rebuild) re-creates the link, hence this runs on every
    # activation rather than once.
    brewOpencode = "/opt/homebrew/opt/opencode/bin/opencode";
  in {
    home.packages = [meridian];

    home.activation.unlinkBrewOpencode = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ -L /opt/homebrew/bin/opencode ]; then
        $DRY_RUN_CMD /opt/homebrew/bin/brew unlink opencode >/dev/null || true
      fi
    '';

    # OpenRouter provider key, from secrets/opencode.yaml (Mac-only recipients).
    # Rendered straight to auth.json in the shape `opencode auth login` writes,
    # so provider config stays declarative and identical on both Macs.
    # ⚠️ sops re-renders this on every activation: a manual `opencode auth
    # login` for openrouter is overwritten on the next rebuild. Rotate the key
    # in secrets/opencode.yaml, not here.
    sops.secrets."openrouter/api_key" = {
      sopsFile = lib.custom.relativeToRoot "secrets/opencode.yaml";
    };
    sops.templates."opencode-auth" = {
      path = "${config.home.homeDirectory}/.local/share/opencode/auth.json";
      mode = "0600";
      content = builtins.toJSON {
        openrouter = {
          type = "api";
          key = config.sops.placeholder."openrouter/api_key";
        };
      };
    };

    programs.opencode = {
      # Env is scoped here; a shell-wide export would also reroute claude-code.
      package = pkgs.writeShellScriptBin "opencode" ''
        export ANTHROPIC_BASE_URL="http://${host}:${port}"
        export ANTHROPIC_API_KEY=x
        # Nix supplies the language servers; without this opencode fetches its
        # own from GitHub/npm into ~/.local/share/opencode/bin.
        export OPENCODE_DISABLE_LSP_DOWNLOAD=1

        # Profile is picked from the launch directory and fixed for the session.
        # Mirrors the identity split in modules/profiles/projects.nix - keep the
        # two patterns in sync. OPENCODE_CONFIG merges above the global config
        # but below a project's own .opencode/, so per-repo settings still win.
        case "$PWD/" in
          "$HOME"/projects/kopf3/*)
            export OPENCODE_CONFIG=${core.profiles.work}
            ;;
          *)
            export OPENCODE_CONFIG=${core.profiles.personal}
            ;;
        esac

        exec ${brewOpencode} "$@"
      '';

      enable = true;

      inherit (core) settings commands agents skills context tui;
    };

    launchd.agents.meridian = {
      enable = true;
      config = {
        ProgramArguments = ["${meridian}/bin/meridian"];
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ThrottleInterval = 5;
        EnvironmentVariables = {
          MERIDIAN_HOST = host;
          MERIDIAN_PORT = port;
          MERIDIAN_PLUGIN_CONFIG = "${core.meridian.pluginManifest}";
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/meridian.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/meridian.err.log";
      };
    };
  };
}
