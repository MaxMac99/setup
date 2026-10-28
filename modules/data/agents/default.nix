# The agent setup every harness shares - output rules, skills, subagents and
# per-identity profiles - as plain data in harness-neutral formats.
# modules/apps/opencode/core.nix and modules/apps/claude-code/core.nix each
# render it into their own layout; anything only one harness understands
# (commands, permissions, primary agents) stays in that harness's module.
{
  lib,
  pkgs,
}: let
  dirs = dir:
    lib.mapAttrs (name: _: dir + "/${name}")
    (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));

  # The output-shaping ruleset. Its short form is always on via ./context.md;
  # this pin only adds the long form - a skill behind an explicit
  # /i-have-adhd, and for claude-code also a plugin. Upstream's own installers
  # (`npx skills add`, `claude plugin marketplace`) all mutate the config
  # directory in place, so it is vendored instead.
  adhd = pkgs.fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "2ed064090711586e0c97a2fbbf15465fe8f1808b";
    hash = "sha256-/h4HxkUbtRGoqgyFvjJrd++XmOd1KSVku5dR2/f9b/s=";
  };

  # Subagent frontmatter is flat `key: value`: `description`, and
  # `read-only: true` for an agent that must not edit files. Any other key
  # fails evaluation, so no harness silently drops a field it cannot render.
  subagentFields = ["description" "read-only"];
  subagent = file: let
    parts = lib.splitString "\n---\n" (lib.removePrefix "---\n" (builtins.readFile (./subagents + "/${file}")));
    field = line: let
      m = builtins.match "([a-z-]+): (.+)" line;
    in
      assert lib.assertMsg (m != null && lib.elem (builtins.head m) subagentFields)
      "agents: subagents/${file}: unsupported frontmatter line `${line}`";
        lib.nameValuePair (builtins.head m) (builtins.elemAt m 1);
    front = builtins.listToAttrs (map field (lib.filter (l: l != "") (lib.splitString "\n" (builtins.head parts))));
  in {
    inherit (front) description;
    readOnly = (front.read-only or "false") == "true";
    body = lib.concatStringsSep "\n---\n" (builtins.tail parts);
  };
in {
  inherit adhd;

  # Output shaping, applied to every session on every host and in every repo.
  context = ./context.md;

  # Name -> skill directory.
  skills = dirs ./skills // {i-have-adhd = "${adhd}/skills/i-have-adhd";};

  # Name -> {description, readOnly, body}.
  subagents =
    lib.mapAttrs' (file: _: lib.nameValuePair (lib.removeSuffix ".md" file) (subagent file))
    (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir ./subagents));

  # Identity-specific skills, on top of the shared ones. A harness that takes
  # a skills directory uses the first, one that links skills one by one the
  # second.
  profileSkillDir = profile: ./profiles + "/${profile}/skills";
  profileSkills = profile: dirs (./profiles + "/${profile}/skills");
}
