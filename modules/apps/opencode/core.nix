# The portable part of the OpenCode setup: settings, commands, agents, TUI and
# the Meridian runtime it is fronted by, plus the shared skills and context
# from modules/data/agents. No darwin, no home-manager, no secrets -
# ./default.nix feeds this into programs.opencode on the Macs, and the same
# values build the config for Linux hosts.
{
  lib,
  pkgs,
  inputs,
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

  # Skills, subagents and context, shared with claude-code.
  agents = import ../../data/agents {inherit lib pkgs;};

  # The shared subagents as opencode agent files, plus the opencode-only
  # primary agent of the /milestone workflow.
  agentFiles = pkgs.linkFarm "opencode-agents" (lib.mapAttrsToList (name: a: {
      name = "${name}.md";
      path = pkgs.writeText "${name}.md" (lib.concatStringsSep "\n" ([
          "---"
          "description: ${a.description}"
          "mode: subagent"
        ]
        ++ lib.optionals a.readOnly ["permission:" "  edit: deny" "  write: deny"]
        ++ ["---" a.body]));
    })
    agents.subagents
    ++ [
      {
        name = "milestone.md";
        path = ./milestone-agent.md;
      }
    ]);

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
            .${
              value
            }
            or value);
    in
      lib.nameValuePair (lib.removeSuffix ".md" file)
      (builtins.listToAttrs (map field (lib.filter (l: l != "") (lib.splitString "\n" (builtins.head parts))))
        // {template = lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (builtins.tail parts));}))
    (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir dir));

  # Per-directory profiles, selected by the wrapper in ./default.nix.
  # ⚠️ OpenCode 2 treats OPENCODE_CONFIG_DIR as a *replacement* for
  # ~/.config/opencode, not an addition: setting it drops every global setting
  # (Meridian's baseURL and plugin, permissions, LSP, global commands/skills)
  # and the background service then fails writing service.json into the
  # read-only store. So a profile's commands and skills ride in its
  # OPENCODE_CONFIG file instead, which merges above the global config.
  profileSettings = {
    # Work code must never end up on a public share URL.
    work = {share = "disabled";};
    personal = {share = "manual";};
  };
  profileAttrs = name:
    {
      skills = ["${agents.profileSkillDir name}"];
      commands = profileCommands (./profiles + "/${name}/commands");
    }
    // profileSettings.${name};

  profileConfig = name:
    (pkgs.formats.json {}).generate "opencode-${name}.json" ({
        "$schema" = "https://opencode.ai/config.json";
      }
      // profileAttrs name);

  self = {
    meridian = {
      package = meridian;
      inherit host port pluginManifest;
      # Meridian with its runtime env baked in, for hosts without launchd.
      service = pkgs.writeShellScriptBin "meridian" ''
        export MERIDIAN_HOST=${host}
        export MERIDIAN_PORT=${port}
        export MERIDIAN_PLUGIN_CONFIG=${pluginManifest}
        exec ${meridian}/bin/meridian "$@"
      '';
    };

    profiles = {
      work = profileConfig "work";
      personal = profileConfig "personal";
    };

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
      # modules/data/agents/context.md's "Tool call visibility" rule makes every call
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

          # Diagram rendering for the diagram skill - reads a mermaid
          # source, writes a PNG into gitignored .work/.
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
    # live in ./profiles/*/commands instead. Commands are opencode's alone: Claude Code
    # makes every skill a slash command of its own name.
    commands = ./commands;
    # A string, not the derivation: programs.opencode would read a
    # derivation's attributes as agent definitions.
    agents = "${agentFiles}";

    # These are opencode's *own* skills. The ones it picks up from
    # ~/.claude/skills are denied in `permission.skill` above.
    inherit (agents) skills context;

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
in
  self
  // {
    # The ~/.config/opencode entries home-manager would write, as one store
    # tree, with the profile merged into opencode.json instead of riding in
    # OPENCODE_CONFIG. Link its entries one by one: opencode writes
    # service.json, package.json and node_modules into the config directory
    # itself, so the directory must stay writable.
    tree = profile:
      pkgs.linkFarm "opencode-config-${profile}" ([
          {
            name = "opencode.json";
            path = (pkgs.formats.json {}).generate "opencode.json" ({
                "$schema" = "https://opencode.ai/config.json";
              }
              // self.settings
              // profileAttrs profile);
          }
          {
            name = "tui.json";
            path = (pkgs.formats.json {}).generate "tui.json" ({
                "$schema" = "https://opencode.ai/tui.json";
              }
              // self.tui);
          }
          {
            name = "AGENTS.md";
            path = self.context;
          }
          {
            name = "agents";
            path = self.agents;
          }
          {
            name = "commands";
            path = self.commands;
          }
        ]
        ++ lib.mapAttrsToList (name: path: {
          name = "skills/${name}";
          inherit path;
        })
        self.skills);
  }
