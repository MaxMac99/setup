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

  # Per-directory profiles, selected by the wrapper below. The settings file is
  # generated outside the profile directory on purpose: anything named
  # opencode.json *inside* OPENCODE_CONFIG_DIR is loaded at a precedence that
  # would outrank a repo's own .opencode/opencode.json.
  profileConfig = name: settings:
    (pkgs.formats.json {}).generate "opencode-${name}.json" ({
        "$schema" = "https://opencode.ai/config.json";
      }
      // settings);

  # Work code must never end up on a public share URL.
  workConfig = profileConfig "work" {share = "disabled";};
  personalConfig = profileConfig "personal" {share = "manual";};
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
        # Nix supplies the language servers; without this opencode fetches its
        # own from GitHub/npm into ~/.local/share/opencode/bin.
        export OPENCODE_DISABLE_LSP_DOWNLOAD=1

        # Profile is picked from the launch directory and fixed for the session.
        # Mirrors the identity split in modules/profiles/projects.nix - keep the
        # two patterns in sync. OPENCODE_CONFIG merges above the global config
        # but below a project's own .opencode/, so per-repo settings still win.
        # OPENCODE_CONFIG_DIR contributes the profile's agent/, command/, skills/.
        case "$PWD/" in
          "$HOME"/projects/kopf3/*)
            export OPENCODE_CONFIG=${workConfig}
            export OPENCODE_CONFIG_DIR=${./profiles/work}
            ;;
          *)
            export OPENCODE_CONFIG=${personalConfig}
            export OPENCODE_CONFIG_DIR=${./profiles/personal}
            ;;
        esac

        exec ${signedBin} "$@"
      '';

      enable = true;

      settings = {
        autoupdate = false;
        share = "manual";
        plugin = ["${meridian}/lib/meridian/plugin/meridian.ts"];
        provider.anthropic.models = lib.genAttrs anthropicModels (_: noCost);

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
        # This list is what makes ./global/context.md's "Shell approvals" rule
        # cheap: the reads below never reach a prompt, so anything that does
        # prompt is by construction not a known-safe read and is worth a line of
        # explanation. Adding an allow here silently removes that explanation.
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
            "git push --force*" = "deny";
            "git reset --hard*" = "deny";
            "kubectl delete*" = "deny";
            "pulumi destroy*" = "deny";
          };
        };
      };

      # Universal habits, shared by both profiles. Identity-specific commands
      # and skills live in profiles/*/ instead.
      commands = ./global/commands;
      agents = ./global/agents;

      # These are opencode's *own* skills. It ALSO scans ~/.claude/skills, which
      # modules/apps/claude-code owns - so Anthropic's pinned collection reaches
      # opencode from there, not from here. ⚠️ That makes this module depend on
      # claude-code being imported alongside it: drop claude-code from a host and
      # opencode silently loses ~20 skills with no evaluation error.
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
