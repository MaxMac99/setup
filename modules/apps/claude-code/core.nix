# The portable part of the Claude Code setup: the shared skills, subagents and
# context from modules/data/agents in Claude Code's layout. No darwin, no
# home-manager - the flake exposes `tree` for hosts outside home-manager, so
# T3 can run the same setup on its `claude` provider, which, unlike opencode
# behind Meridian, shows token use and context size and can compact.
{
  lib,
  pkgs,
}: let
  agents = import ../../data/agents {inherit lib pkgs;};

  # `name` is required here, and a read-only agent gets a tool denylist.
  subagentFile = name: a:
    pkgs.writeText "${name}.md" (lib.concatStringsSep "\n" ([
        "---"
        "name: ${name}"
        "description: ${a.description}"
      ]
      ++ lib.optional a.readOnly "disallowedTools: Edit, Write, NotebookEdit"
      ++ ["---" a.body]));
in {
  inherit (agents) adhd;

  # The ~/.claude entries, as one store tree. Link them one by one:
  # ~/.claude/skills also holds the skills synced from claude.ai, and
  # claude-code writes settings, sessions and credentials beside them.
  tree = profile:
    pkgs.linkFarm "claude-config-${profile}" ([
        {
          name = "CLAUDE.md";
          path = agents.context;
        }
      ]
      ++ lib.mapAttrsToList (name: a: {
        name = "agents/${name}.md";
        path = subagentFile name a;
      })
      agents.subagents
      ++ lib.mapAttrsToList (name: path: {
        name = "skills/${name}";
        inherit path;
      }) (agents.skills // agents.profileSkills profile));
}
