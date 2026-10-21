# OpenCode - terminal AI coding agent, fronted by Meridian
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  # ⚠️ bun2nix's setup hook populates the offline cache with `cp -r`, though its
  # own comment says `-RL` — so every cache entry stays a symlink into the
  # read-only store. `bun install --linker=hoisted` clones package dirs from
  # there with the store's r-xr-xr-x, then cannot mkdir the nested
  # `node_modules` the hoisted linker needs (zod under @opencode-ai/plugin,
  # glob under rimraf, …) and dies with `AccessDenied` on exactly those 19
  # packages. Upstream's `chmod -R u+rwx ./node_modules` only runs in the later
  # lifecycle-scripts phase, too late to help. Re-materialise the cache as real,
  # writable directories before the install phase reads it.
  meridian =
    inputs.meridian.packages.${system}.meridian.overrideAttrs
    (_: {
      preBunNodeModulesInstallPhase = ''
        writableCache=$(mktemp -d)
        cp -rL "$BUN_INSTALL_CACHE_DIR"/. "$writableCache"
        chmod -R u+w "$writableCache"
        export BUN_INSTALL_CACHE_DIR="$writableCache"
      '';
    });
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

  # Estimated cost is noise on a subscription. The TUI only renders a dollar
  # figure when it is > 0, so zeroing the catalog pricing removes it from the
  # prompt footer and the subagent panel. Model overrides merge field-by-field
  # over the models.dev entry, so limit.context and capabilities survive.
  # Models added upstream after this list will show cost again until added here.
  anthropicModels = [
    "claude-fable-5"
    "claude-haiku-4-5"
    "claude-haiku-4-5-20251001"
    "claude-opus-4-5"
    "claude-opus-4-5-20251101"
    "claude-opus-4-6"
    "claude-opus-4-6-fast"
    "claude-opus-4-7"
    "claude-opus-4-7-fast"
    "claude-opus-4-8"
    "claude-opus-4-8-fast"
    "claude-opus-5"
    "claude-opus-5-fast"
    "claude-sonnet-4-5"
    "claude-sonnet-4-5-20250929"
    "claude-sonnet-4-6"
    "claude-sonnet-5"
  ];
  noCost = {
    cost = {
      input = 0;
      output = 0;
      cache_read = 0;
      cache_write = 0;
    };
  };

  # The output-shaping ruleset. Its short form is always on via ./global/context.md;
  # this pin only adds the long form, behind an explicit /i-have-adhd. Upstream's
  # own installers (`npx skills add`, `claude plugin marketplace`) all mutate the
  # config directory in place, so the skill is vendored instead.
  adhdSkill = pkgs.fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "2ed064090711586e0c97a2fbbf15465fe8f1808b";
    hash = "sha256-/h4HxkUbtRGoqgyFvjJrd++XmOd1KSVku5dR2/f9b/s=";
  };

  # A profile's commands/*.md, as `commands` entries. Frontmatter must be flat
  # `key: value` lines; `true`/`false` become booleans. Only fields V2 commands
  # accept are allowed, so a typo fails evaluation instead of being ignored.
  commandFields = ["description" "agent" "model" "subagent"];
  profileCommands = dir:
    lib.mapAttrs' (file: _: let
      parts = lib.splitString "\n---\n" (lib.removePrefix "---\n" (builtins.readFile (dir + "/${file}")));
      field = line: let
        m = builtins.match "([a-z]+): (.+)" line;
        value = builtins.elemAt m 1;
      in
        assert lib.assertMsg (m != null && lib.elem (builtins.head m) commandFields)
        "opencode: ${file}: unsupported frontmatter line `${line}`";
          lib.nameValuePair (builtins.head m) ({
              "true" = true;
              "false" = false;
            }
            .${value}
            or value);
    in
      lib.nameValuePair (lib.removeSuffix ".md" file)
      (builtins.listToAttrs (map field (lib.filter (l: l != "") (lib.splitString "\n" (builtins.head parts))))
        // {template = lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (builtins.tail parts));}))
    (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir dir));

  # Per-directory profiles, selected by the wrapper below.
  # ⚠️ OpenCode 2 treats OPENCODE_CONFIG_DIR as a *replacement* for
  # ~/.config/opencode, not an addition: setting it drops every global setting
  # (Meridian's baseURL and plugin, permissions, LSP, global commands/skills)
  # and the background service then fails writing service.json into the
  # read-only store. So a profile's commands and skills ride in its
  # OPENCODE_CONFIG file instead, which merges above the global config.
  profileConfig = name: settings: let
    dir = ./profiles + "/${name}";
  in
    (pkgs.formats.json {}).generate "opencode-${name}.json" ({
        "$schema" = "https://opencode.ai/config.json";
        skills = ["${dir}/skills"];
        commands = profileCommands (dir + "/commands");
      }
      // settings);

  # Work code must never end up on a public share URL.
  workConfig = profileConfig "work" {share = "disabled";};
  personalConfig = profileConfig "personal" {share = "manual";};
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
            export OPENCODE_CONFIG=${workConfig}
            ;;
          *)
            export OPENCODE_CONFIG=${personalConfig}
            ;;
        esac

        exec ${brewOpencode} "$@"
      '';

      enable = true;

      settings = {
        autoupdate = false;
        share = "manual";
        plugin = ["${meridian}/lib/meridian/plugin/meridian.ts"];
        provider.anthropic.models = lib.genAttrs anthropicModels (_: noCost);
        # ⚠️ OpenCode 2's native Anthropic client reads ANTHROPIC_API_KEY from
        # the env but NOT ANTHROPIC_BASE_URL, so without this every request
        # goes straight to api.anthropic.com with the dummy key and fails as
        # "invalid x-api-key". The /v1 suffix is required.
        provider.anthropic.options.baseURL = "http://${host}:${port}/v1";

        # Enables every built-in server; each one only starts if it finds its
        # binary, which config.lspPackages puts on PATH. The two entries below
        # are the exceptions - their built-ins download a release from GitHub,
        # so pin them to nixpkgs. nvf resolves the same derivations, so neovim
        # and opencode stay on identical binaries.
        lsp = {
          jdtls.command = ["${pkgs.jdt-language-server}/bin/jdtls"];
          kotlin-ls.command = ["${pkgs.kotlin-language-server}/bin/kotlin-language-server"];
        };

        # Read freely, ask before writing.
        #
        # opencode applies the LAST matching rule. Nix attrsets are unordered and
        # serialize alphabetically, so the order written here is NOT the order
        # opencode sees - do not try to express precedence by position. What
        # makes this safe is that no `allow` pattern is a superset of a `deny`
        # one, and "*" sorts first so it stays the fallback. Before adding a
        # broad allow (`git p*`, `kubectl *`), check it cannot swallow a deny
        # that sorts earlier.
        #
        # `git add` is allowed on purpose: the /commit workflow stages logical
        # groups for you, and staging is undone with `git reset`. Commit, push,
        # `pulumi up` and `kubectl apply` fall through to the catch-all and ask.
        #
        # `gh api` is deliberately absent: `gh api repos/O/R/issues -f title=x`
        # implies POST, so any `gh api repos/*` allow would auto-approve writes.
        #
        # ./global/context.md's "Tool call visibility" rule makes every call
        # narrate (`read|write · what · why`), so allowlisting reads here costs
        # no visibility - it only skips the approval prompt, not the
        # explanation. Adding an allow never silences a call. The deny rules
        # below still hard-block regardless of narration.
        # ⚠️ The permission dialog renders only the command - its metadata is
        # {command, directories, patterns}, with no field a plugin or config can
        # write - which is why the explanation has to precede the call instead.
        permission = {
          bash = {
            "*" = "ask";

            # Inspection
            "which *" = "allow";
            "grep *" = "allow";
            "echo *" = "allow";
            "ls *" = "allow";
            "cat *" = "allow";
            "head *" = "allow";
            "tail *" = "allow";
            "wc *" = "allow";
            "find *" = "allow";
            "rg *" = "allow";
            "jq *" = "allow";
            "file *" = "allow";
            "stat *" = "allow";
            "readlink *" = "allow";
            "basename *" = "allow";
            "dirname *" = "allow";
            "diff *" = "allow";
            "tree *" = "allow";
            "du *" = "allow";
            "df *" = "allow";
            "strings *" = "allow";
            "cut *" = "allow";
            "uniq *" = "allow";
            "pwd" = "allow";
            "uname*" = "allow";

            # Git, read-only plus staging
            "git status*" = "allow";
            "git diff*" = "allow";
            "git log*" = "allow";
            "git show*" = "allow";
            "git branch" = "allow";
            "git remote -v" = "allow";
            "git worktree list*" = "allow";
            "git add*" = "allow";
            "git blame*" = "allow";
            "git rev-parse*" = "allow";
            "git merge-base*" = "allow";
            "git describe*" = "allow";
            "git ls-files*" = "allow";
            "git shortlog*" = "allow";
            "git stash list*" = "allow";
            "git config --get*" = "allow";

            # Rust
            "cargo check*" = "allow";
            "cargo clippy*" = "allow";
            "cargo test*" = "allow";
            "cargo tree*" = "allow";
            "cargo fmt --check*" = "allow";

            # Diagram rendering for /diagram - reads a mermaid source, writes a
            # PNG into gitignored .work/.
            "mmdc *" = "allow";

            # Nix
            "nix eval*" = "allow";
            "nix flake check*" = "allow";
            "nix flake metadata*" = "allow";
            "nix flake show*" = "allow";
            "nix fmt -- --check*" = "allow";
            "nix path-info*" = "allow";
            "nix derivation show*" = "allow";
            "nix search*" = "allow";
            "nix why-depends*" = "allow";

            # Infra, read-only. `kubectl config view` and `pulumi stack output`
            # are deliberately absent: both take a flag (`--raw`,
            # `--show-secrets`) that prints the kubeconfig's client key or a
            # stack's secrets straight into the transcript, and a trailing `*`
            # cannot exclude a flag.
            "kubectl get*" = "allow";
            "kubectl describe*" = "allow";
            "kubectl logs*" = "allow";
            "kubectl top*" = "allow";
            "kubectl explain*" = "allow";
            "kubectl api-resources*" = "allow";
            "kubectl config get-contexts*" = "allow";
            "kubectl config current-context*" = "allow";
            "pulumi preview*" = "allow";
            "pulumi stack ls*" = "allow";
            "pulumi about*" = "allow";
            "pulumi whoami*" = "allow";

            # GitHub, read-only
            "gh pr view*" = "allow";
            "gh pr diff*" = "allow";
            "gh pr list*" = "allow";
            "gh pr checks*" = "allow";
            "gh issue view*" = "allow";
            "gh issue list*" = "allow";
            "gh run view*" = "allow";
            "gh run list*" = "allow";
            "gh repo view*" = "allow";
            "gh release view*" = "allow";
            "gh release list*" = "allow";
            "gh workflow list*" = "allow";
            "gh search*" = "allow";

            # Irreversible or outward-facing: never without a human.
            #
            # `git push --force*` also matches `--force-with-lease`, which the
            # /review-comments rebase-and-push flow needs to update a rewritten
            # PR branch. The lease variant gets its own `ask` rule: this key
            # sorts after the deny (`-` > `*`) and opencode applies the LAST
            # matching rule, so only the lease form is loosened to a prompt. A
            # bare `--force` matches nothing else and stays hard-blocked.
            "git push --force*" = "deny";
            "git push --force-with-lease*" = "ask";
            "git reset --hard*" = "deny";
            "kubectl delete*" = "deny";
            "pulumi destroy*" = "deny";
          };

          # opencode also scans ~/.claude/skills, which modules/apps/claude-code
          # fills with Anthropic's pinned collection. Those are general
          # knowledge the model already has, so they are kept out of opencode
          # entirely; `deny` hides them and refuses loading. V2 has no switch to
          # stop scanning that directory, so the IDs are listed by hand.
          # ⚠️ Bumping that pin can add a skill that is not listed here; it then
          # shows up in opencode until it is added. `opencode api get /api/skill`
          # shows what opencode sees.
          skill =
            {"*" = "allow";}
            // lib.genAttrs [
              "algorithmic-art"
              "brand-guidelines"
              "canvas-design"
              "claude-api"
              "doc-coauthoring"
              "docx"
              "frontend-design"
              "internal-comms"
              "mcp-builder"
              "pdf"
              "pptx"
              "skill-creator"
              "slack-gif-creator"
              "theme-factory"
              "web-artifacts-builder"
              "webapp-testing"
              "xlsx"
            ] (_: "deny");
        };
      };

      # Universal habits, shared by both profiles. Identity-specific commands
      # and skills live in profiles/*/ instead.
      commands = ./global/commands;
      agents = ./global/agents;

      # These are opencode's *own* skills. The ones it picks up from
      # ~/.claude/skills are denied in `permission.skill` above.
      #
      # The option takes either a directory *or* an attrset, never both, so
      # pulling in one out-of-tree skill means enumerating the in-tree ones too.
      # readDir keeps that a one-place change when a skill is added.
      skills =
        lib.mapAttrs (name: _: ./global/skills + "/${name}")
        (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./global/skills))
        // {i-have-adhd = "${adhdSkill}/skills/i-have-adhd";};

      # Output shaping, applied to every session on both Macs and in every repo.
      # ⚠️ Writing ~/.config/opencode/AGENTS.md SUPPRESSES ~/.claude/CLAUDE.md:
      # opencode takes the first match per category, so a global Claude-side
      # rules file added later would be ignored with no error. None exists today.
      context = ./global/context.md;

      tui = {
        theme = "tokyonight";
        # Swaps the built-in sidebar section (tokens / % used / $ spent) for a
        # percentage-only one. Must be listed here rather than in settings:
        # settings.plugin is the server plugin list and does not load TUI plugins.
        plugin = ["${./context-percent.tsx}"];
        plugin_enabled = {
          "internal:sidebar-context" = false;
        };
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
