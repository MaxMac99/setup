# OpenCode - terminal AI coding agent, fronted by Meridian
{
  config,
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  meridian = inputs.meridian.packages.${system}.meridian;
  scrub = inputs.meridian.legacyPackages.${system}.meridianPlugins.opencode-scrub;

  pluginManifest = (pkgs.formats.json {}).generate "plugins.json" {
    plugins = [
      {
        path = scrub.path;
        enabled = true;
      }
    ];
  };

  host = "127.0.0.1";
  port = "3456";
in {
  home-manager.users.${config.hostSpec.username} = {
    config,
    lib,
    ...
  }: let
    # pkgs.opencode's bun payload ships an ad-hoc signature that macOS 27
    # rejects, so AMFI SIGKILLs it. Re-signing fixes it, but sigtool aborts on
    # a binary this size - only /usr/bin/codesign works, hence activation.
    signedDir = "${config.xdg.stateHome}/opencode";
    signedBin = "${signedDir}/opencode";
    payload = "${pkgs.opencode}/bin/.opencode-wrapped";
  in {
    home.packages = [meridian];

    home.activation.signOpencode = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ "$(cat ${signedDir}/.source 2>/dev/null)" != "${payload}" ]; then
        $DRY_RUN_CMD mkdir -p ${signedDir}
        $DRY_RUN_CMD install -m 755 ${payload} ${signedBin}
        $DRY_RUN_CMD /usr/bin/codesign -f -s - ${signedBin}
        $DRY_RUN_CMD sh -c 'printf %s "${payload}" > ${signedDir}/.source'
      fi
    '';

    programs.opencode = {
      # Env is scoped here; a shell-wide export would also reroute claude-code.
      package = pkgs.writeShellScriptBin "opencode" ''
        export ANTHROPIC_BASE_URL="http://${host}:${port}"
        export ANTHROPIC_API_KEY=x
        exec ${signedBin} "$@"
      '';

      enable = true;

      settings = {
        autoupdate = false;
        share = "manual";
        plugin = ["${meridian}/lib/meridian/plugin/meridian.ts"];
      };

      tui = {
        theme = "tokyonight";
      };
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
          MERIDIAN_PLUGIN_CONFIG = "${pluginManifest}";
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/meridian.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/meridian.err.log";
      };
    };
  };
}
