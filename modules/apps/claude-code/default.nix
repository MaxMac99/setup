# Claude Code - plugin wiring only. The agent itself is a package in
# modules/profiles/development.nix; nothing here installs it.
{
  config,
  pkgs,
  ...
}: let
  # Same pin as `adhdSkill` in modules/apps/opencode/default.nix. Identical
  # owner/repo/rev/hash means nix resolves both to ONE store path and one fetch,
  # so opencode gets the skill and claude-code gets the plugin out of the same
  # tree. ⚠️ They are still two separate expressions: bumping one rev and not
  # the other leaves the two agents on different versions of the same ruleset,
  # with no error anywhere. Bump them together.
  adhdPlugin = pkgs.fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "2ed064090711586e0c97a2fbbf15465fe8f1808b";
    hash = "sha256-/h4HxkUbtRGoqgyFvjJrd++XmOd1KSVku5dR2/f9b/s=";
  };

  # Anthropic's skill collection, and the only thing here that both agents read:
  # claude-code loads ~/.claude/skills natively and opencode scans the same path,
  # so this one pin serves both. It lives in this module rather than opencode's
  # because the path is claude-code's; see the note on `skills` over there.
  # Fetched at build time, never redistributed, so the source-available document
  # skills are not a licensing concern. ⚠️ Their scripts shell out to Python
  # libraries that are not in this profile, so those skills may not run.
  anthropicSkills = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "b29e7cf65e5cb78a5ac33d582270551bc74a14eb";
    hash = "sha256-RH2B03gj4kzw1j5LORezgUZPPu8mW+mWb+Kl2U7WUbY=";
  };

  # claude-code has a native LSP tool (goToDefinition, findReferences, hover,
  # documentSymbol, workspaceSymbol, call hierarchy) but only for extensions
  # some plugin claims. A "LSP plugin" carries no code at all - Anthropic's own
  # ship a README and a LICENSE, and the whole payload is the `lspServers` block
  # in marketplace.json. So the marketplace below is generated rather than
  # fetched, which buys three things their official plugins cannot:
  #
  #   1. nixd, texlab, bash and yaml have no official plugin at all. Nix is most
  #      of the work in this repo, so nixd is the one that actually matters.
  #   2. `command` is an absolute store path, not a bare name looked up on PATH.
  #      jdtls and kotlin-language-server are NOT on PATH - modules/data/lsp.nix
  #      omits them and the opencode module pins them by path for exactly this
  #      reason - so `jdtls-lsp@claude-plugins-official` would install happily
  #      and then fail to start. These do not.
  #   3. The server binary is pinned by the flake lock, so claude-code, neovim
  #      and opencode cannot drift onto different builds of the same server.
  #
  # ⚠️ Couples to modules/data/lsp.nix. That list is what puts these servers on
  # PATH for every *other* consumer; this one duplicates the choice because it
  # additionally needs an extension map, which is a claude-code-specific schema
  # and does not belong in shared data. Adding a server to one and not the other
  # is silent - the editors get it and claude-code does not, or vice versa.
  lspServers = {
    nixd = {
      command = "${pkgs.nixd}/bin/nixd";
      extensionToLanguage = {".nix" = "nix";};
    };
    rust-analyzer = {
      command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
      extensionToLanguage = {".rs" = "rust";};
    };
    gopls = {
      command = "${pkgs.gopls}/bin/gopls";
      extensionToLanguage = {".go" = "go";};
    };
    typescript = {
      command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
      args = ["--stdio"];
      extensionToLanguage = {
        ".ts" = "typescript";
        ".tsx" = "typescriptreact";
        ".mts" = "typescript";
        ".cts" = "typescript";
        ".js" = "javascript";
        ".jsx" = "javascriptreact";
        ".mjs" = "javascript";
        ".cjs" = "javascript";
      };
    };
    pyright = {
      command = "${pkgs.pyright}/bin/pyright-langserver";
      args = ["--stdio"];
      extensionToLanguage = {
        ".py" = "python";
        ".pyi" = "python";
      };
    };
    lua = {
      command = "${pkgs.lua-language-server}/bin/lua-language-server";
      extensionToLanguage = {".lua" = "lua";};
    };
    bash = {
      command = "${pkgs.bash-language-server}/bin/bash-language-server";
      args = ["start"];
      extensionToLanguage = {
        ".sh" = "shellscript";
        ".bash" = "shellscript";
      };
    };
    yaml = {
      command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
      args = ["--stdio"];
      extensionToLanguage = {
        ".yaml" = "yaml";
        ".yml" = "yaml";
      };
    };
    texlab = {
      command = "${pkgs.texlab}/bin/texlab";
      extensionToLanguage = {".tex" = "latex";};
    };
    jdtls = {
      command = "${pkgs.jdt-language-server}/bin/jdtls";
      extensionToLanguage = {".java" = "java";};
    };
    kotlin = {
      command = "${pkgs.kotlin-language-server}/bin/kotlin-language-server";
      extensionToLanguage = {
        ".kt" = "kotlin";
        ".kts" = "kotlin";
      };
    };
  };

  # Every server rides in ONE plugin - claude-code reads all the keys under a
  # single `lspServers`, so this is one marketplace entry to enable instead of
  # eleven. The `source` directory has to exist even though nothing reads it.
  lspMarketplaceJson = (pkgs.formats.json {}).generate "marketplace.json" {
    name = "nix-lsp";
    description = "Language servers from this flake's nixpkgs, pinned by store path";
    owner.name = config.hostSpec.username;
    plugins = [
      {
        name = "nix-lsp";
        description = "Nix-pinned language servers for the native LSP tool";
        version = "1.0.0";
        source = "./plugins/nix-lsp";
        category = "development";
        strict = false;
        inherit lspServers;
      }
    ];
  };

  lspMarketplace = pkgs.runCommand "claude-lsp-marketplace" {} ''
    mkdir -p $out/.claude-plugin $out/plugins/nix-lsp
    cp ${lspMarketplaceJson} $out/.claude-plugin/marketplace.json
    echo "Generated by modules/apps/claude-code/default.nix." \
      > $out/plugins/nix-lsp/README.md
  '';

  # The half of ~/.claude/settings.json that nix owns. A `directory` marketplace
  # is read in place, so claude-code points at the store path rather than
  # copying into ~/.claude/plugins/cache - the pins above are the only versions
  # that can ever load, and `claude plugin marketplace update` cannot move them.
  #
  # ⚠️ `rust-analyzer-lsp` is force-disabled, not merely left out. Its command is
  # a bare `rust-analyzer` off PATH and it claims `.rs`, which nix-lsp also
  # claims - leaving both enabled points two servers at the same extension.
  # swift-lsp is deliberately untouched: sourcekit-lsp comes from Xcode at
  # /usr/bin, so there is no store path to pin and no duplicate to resolve.
  declared = (pkgs.formats.json {}).generate "claude-code-declared.json" {
    extraKnownMarketplaces = {
      "i-have-adhd".source = {
        source = "directory";
        path = "${adhdPlugin}";
      };
      "nix-lsp".source = {
        source = "directory";
        path = "${lspMarketplace}";
      };
    };
    enabledPlugins = {
      "i-have-adhd@i-have-adhd" = true;
      "nix-lsp@nix-lsp" = true;
      "rust-analyzer-lsp@claude-plugins-official" = false;
    };
  };

  # ~/.claude/settings.json CANNOT be a home.file symlink: claude-code writes to
  # it itself (`tui`, `alwaysThinkingEnabled`, and every `claude plugin` command
  # land there), and a read-only store path makes those writes fail. So the keys
  # above are deep-merged in with `*`, leaving every other key - and any plugin
  # installed by hand - alone. Idempotent; the same merge every switch.
  #
  # ⚠️ Merge only adds. Renaming a marketplace here leaves the old name behind in
  # settings.json forever, still pointing at a store path that will be garbage
  # collected. Remove the stale entry by hand when renaming.
  #
  # ⚠️ `CLAUDE_CODE_MANAGED_SETTINGS_PATH` looks like the clean declarative way
  # to do all this and is NOT honoured - a managed file denying Bash was ignored
  # and the tool ran anyway. Do not reach for it again.
  syncSettings = pkgs.writeShellScript "claude-code-sync-settings" ''
    set -euo pipefail
    settings="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    [ -s "$settings" ] || printf '{}\n' > "$settings"
    tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${declared} > "$tmp"
    mv "$tmp" "$settings"
  '';
in {
  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
    # ⚠️ Takes TWO sessions to appear. The first syncs the marketplaces from
    # settings.json into plugins/known_marketplaces.json, the second installs
    # the enabled plugins. On a fresh machine the first launch after a switch
    # looks like this module did nothing.
    home.activation.claudeCodeSettings =
      lib.hm.dag.entryAfter ["writeBoundary"] "$DRY_RUN_CMD ${syncSettings}";

    # ⚠️ Whole-directory symlink, so ~/.claude/skills is exactly this collection
    # and nothing else. A second source cannot be dropped in beside it without
    # merging both into one store directory first.
    home.file.".claude/skills".source = "${anthropicSkills}/skills";

    # Without this flag the ADHD plugin is inert until someone types
    # /i-have-adhd. The flag arms its SessionStart hook, which is what makes the
    # ruleset always-on and so matches what ./opencode/global/context.md already
    # does for opencode. Delete this line to go back to on-demand.
    home.file.".claude/.i-have-adhd-always".text = "";
  };
}
