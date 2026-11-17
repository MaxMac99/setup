# Herdr - native desktop app for terminals and coding agents; homebrew cask,
# self-updating (auto_updates). Apple silicon only. The `herdr` formula /
# nixpkgs package is the separate TUI and does not share agents with the app.
#
# Beyond the app, this module owns its interface in ~/.config/herdr-app: the
# herdr-t3 layout (T3 Code's look and Inbox) with a thread tree, a launcher
# with per-thread MCP servers, PRs, skills and a milestone board, a native
# chat for Claude Code, the Claude limits, and tab titles.
#
# ⚠️ The app writes into that folder itself: jsconfig.json and .d.ts files into
# every mod, t3-chrome its window-button offset into the layout, clicks into
# layouts/.state, and on every start it replaces its own shipped mods. So
# nothing here is a store symlink. The activation below copies the mods and
# the layout in, and merges keys.json, on every switch; what the app writes
# besides survives. An edit made in the app to a managed mod or the layout
# is overwritten on the next switch: make it in this folder instead.
#
# ⚠️ Third-party code is pinned to the commits that were read before adding
# them, and is bumped by hand: Renovate does not move fetchFromGitHub pins,
# and these run with the person's full rights (exec, network, files).
{
  config,
  lib,
  pkgs,
  ...
}: let
  # JinJieBeWater/herdr-t3: the layout and its t3-* mods. Local only: git, ls,
  # open and sh for file lists; writes its own layout file and cache/.
  t3 = pkgs.fetchFromGitHub {
    owner = "JinJieBeWater";
    repo = "herdr-t3";
    rev = "86dbccf77c82ff19cb52ad7ce13939c267a1e311";
    hash = "sha256-0pinX2/dW/8R57oLoE6FWnM6dA3aTjGW3e2chXbvOus=";
  };

  # nozikov/herdr-usage-limits: Claude's limits from `claude -p` get_usage,
  # reads no token. Patched with a `wide` prop: the bar over the whole block,
  # for the sidebar row the layout gives it.
  usageLimits = pkgs.applyPatches {
    name = "herdr-usage-limits";
    src = pkgs.fetchFromGitHub {
      owner = "nozikov";
      repo = "herdr-usage-limits";
      rev = "ca2261513bba2b0f272e33d759b93581a15c6fc8";
      hash = "sha256-PvOJtWGk9HLru0Ug900SdYPtoc9CRsODAf3/gcOD+Mk=";
    };
    patches = [./patches/usage-limits-wide.patch];
  };

  # ChmaraX/herdr-chat: the chat mods and their host, a Node program that
  # drives `claude -p` over stream-json and listens on 127.0.0.1 only. The
  # upstream installer downloads a release and edits layout and keys; here the
  # host is built from source (Node 24 runs its TypeScript as is), the layout
  # edit is already in layouts/herdr-t3.json and the key in keys.json below.
  # Its sub-agent notes and hc templates (--no-subagents) are left out.
  chatSrc = pkgs.fetchFromGitHub {
    owner = "ChmaraX";
    repo = "herdr-chat";
    rev = "be2bf7dd10aedfbdb89ac30bfa68498ef5f9a09e";
    hash = "sha256-wjhMa/LllkdYX9UhS2MzjwkeUMFznETQwH8EXcBYXdo=";
  };
  chatHost = pkgs.buildNpmPackage {
    pname = "herdr-chat";
    version = "0.4.0";
    src = chatSrc;
    nodejs = pkgs.nodejs_24;
    npmDepsHash = "sha256-kiDNvJRNV42VeqK8KMinZpi2Z3+HIhVusd1zO5PwZ+A=";
    npmFlags = ["--ignore-scripts"];
    dontNpmBuild = true;
    # ⚠️ Not the usual lib/node_modules/herdr-chat: Node refuses to strip the
    # types of a .ts file anywhere under node_modules, and the host is .ts.
    installPhase = ''
      runHook preInstall
      npm prune --omit=dev --ignore-scripts --offline
      mkdir -p $out/share
      cp -R . $out/share/herdr-chat
      runHook postInstall
    '';
  };
  chatRoot = "${chatHost}/share/herdr-chat";

  # kryptamine/herdr-auto-title: names tabs from the Claude session, branch or
  # program. No LLM; its only network is a daily HEAD for a newer release.
  # Runs as the launchd agent below instead of its own `desktop install`.
  autoTitle = pkgs.buildGoModule {
    pname = "herdr-auto-title";
    version = "0.22.3";
    src = pkgs.fetchFromGitHub {
      owner = "kryptamine";
      repo = "herdr-auto-title";
      rev = "1af236e95eb67adc77b3161937ff946c616b709c";
      hash = "sha256-jdAvUelzKQu6CJO7ku6QgEAO65E1M7odZpp4xHJY8+Y=";
    };
    vendorHash = "sha256-UfIpYaA2eIRl29fhi7ESEoHEsyiXmEZ4MO78T0Q6OCs=";
    subPackages = ["cmd/herdr-auto-title"];
    doCheck = false;
  };

  # Every mod folder this module owns, name -> source. ./mods are ours.
  t3Mods = lib.genAttrs [
    "t3-actions"
    "t3-agents"
    "t3-chrome"
    "t3-files"
    "t3-home"
    "t3-inbox"
    "t3-menu"
    "t3-new-menu"
    "t3-pane"
    "t3-picker"
    "t3-spaces"
    "t3-tabs"
  ] (name: "${t3}/mods/${name}");
  # Not chat-agents and chat-menu: the installer builds them from Herdr's own
  # agents and menu mods at install time, and herdr-t3 holds both of their
  # slots anyway (its own agents list and terminal menu).
  chatMods = lib.genAttrs ["chat" "new-chat"] (name: "${chatSrc}/herdr-app/mods/${name}");
  ownMods = lib.genAttrs ["board" "launch" "prs" "skills" "threads"] (name: ./mods + "/${name}");
  mods = t3Mods // chatMods // ownMods // {"usage-limits" = "${usageLimits}/mods/usage-limits";};

  # Keys merged into keys.json: the layout's own, then ours. A key the person
  # bound to something else is overwritten only if it is one of these.
  keys = (pkgs.formats.json {}).generate "herdr-keys.json" (lib.recursiveUpdate
    (lib.importJSON "${t3}/keys.json")
    {
      global = {
        "cmd-i" = "mod.open:new-chat"; # herdr-chat's launcher
        "cmd-shift-n" = "mod.open:launch";
        "cmd-shift-o" = "mod.open:prs";
        "cmd-shift-k" = "mod.open:skills";
        "cmd-shift-m" = "mod.open:board";
      };
    });

  profiled = "${config.hostSpec.home}/.config/claude-profiles/bin/claude-profiled";

  sync = pkgs.writeShellScript "herdr-app-sync" ''
    set -euo pipefail
    app="$HOME/.config/herdr-app"
    mkdir -p "$app/mods" "$app/layouts"

    # Copies, writable, keeping what the app writes into a mod (jsconfig.json, .d.ts).
    put() {
      ${pkgs.rsync}/bin/rsync -rL --delete --chmod=u+w,Du+wx \
        --exclude jsconfig.json --exclude '*.d.ts' --exclude test/ "$1/" "$app/mods/$2/"
    }
    ${lib.concatStrings (lib.mapAttrsToList (name: src: "put ${src} ${name}\n") mods)}
    # herdr-chat's installer marks the mods it owns.
    for m in ${lib.concatStringsSep " " (builtins.attrNames chatMods)}; do : > "$app/mods/$m/.herdr-chat"; done

    # A mod this module no longer lists goes; the app's own and hand-made ones stay.
    managed="$app/.nix-managed-mods"
    if [ -f "$managed" ]; then
      while IFS= read -r m; do
        case " ${lib.concatStringsSep " " (builtins.attrNames mods)} " in *" $m "*) ;; *) rm -rf "$app/mods/$m" ;; esac
      done < "$managed"
    fi
    printf '%s\n' ${lib.concatStringsSep " " (builtins.attrNames mods)} > "$managed"

    install -m 0644 ${./layouts/herdr-t3.json} "$app/layouts/herdr-t3.json"
    install -m 0644 ${t3}/layouts/herdr-t3.svg "$app/layouts/herdr-t3.svg"

    # The chat host and the claude it starts: the profiled wrapper, so a thread
    # gets its MCP servers and extra repos from the launcher.
    # build: the id the host reports, as the installer records it.
    build="$(${pkgs.nodejs_24}/bin/node ${chatRoot}/host/main.ts build | ${pkgs.jq}/bin/jq -r .build)"
    ${pkgs.jq}/bin/jq -n \
      --arg host "${chatRoot}/bin/herdr-chat-host" --arg node "${pkgs.nodejs_24}/bin/node" \
      --arg hc "$HOME/.local/bin/hc" --arg build "$build" --arg claude "${profiled}" \
      '{host: $host, node: $node, hc: $hc, version: "0.4.0", build: $build, channel: "nix", update: "", claude: $claude}' \
      > "$app/mods/chat/config.json"

    keys="$app/keys.json"
    [ -s "$keys" ] || printf '{}\n' > "$keys"
    tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$keys" ${keys} > "$tmp"
    mv "$tmp" "$keys"
  '';
in {
  homebrew.casks = ["herdr-app"];

  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
    home.activation.herdrApp = lib.hm.dag.entryAfter ["writeBoundary"] "$DRY_RUN_CMD ${sync}";

    # claude with a per-thread MCP selection and extra repos, read from the
    # environment the launcher gives a chat (CLAUDE_MCP_PROFILE, CLAUDE_ADD_DIRS).
    # ⚠️ The chat runs `claude -p`, which never loads claude.ai connectors and
    # cannot sign in: an OAuth server signs in once per Mac in an interactive
    # `claude --strict-mcp-config --mcp-config <file>` → /mcp → Authenticate.
    home.file.".config/claude-profiles/bin/claude-profiled" = {
      source = ./claude-profiles/claude-profiled;
      executable = true;
    };
    # One server per file: each is a chip in the launcher. keine.json is the
    # empty set a thread with none picked gets.
    home.file.".config/claude-profiles/mcp".source = ./claude-profiles/mcp;

    home.file.".config/herdr-auto-title/config.env".text = ''
      # No "1 · " before the title: T3's tabs carry no number.
      HERDR_AUTO_TITLE_POSITION=false
    '';
    launchd.agents.herdr-auto-title = {
      enable = true;
      config = {
        ProgramArguments = ["${autoTitle}/bin/herdr-auto-title" "desktop"];
        RunAtLoad = true;
        # A clean exit is a newer instance claiming the session: not restarted.
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = "${config.hostSpec.home}/Library/Logs/herdr-auto-title.log";
        StandardErrorPath = "${config.hostSpec.home}/Library/Logs/herdr-auto-title.log";
        EnvironmentVariables.PATH = lib.concatStringsSep ":" [
          "${config.hostSpec.home}/.local/bin" # hc
          "${config.hostSpec.home}/.nix-profile/bin"
          "/etc/profiles/per-user/${config.hostSpec.username}/bin"
          "/run/current-system/sw/bin"
          "/opt/homebrew/bin"
          "/usr/bin"
          "/bin"
        ];
      };
    };
  };
}
