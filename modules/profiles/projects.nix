# Directory-based identities: ~/projects/kopf3 (work) vs ~/projects/private (personal)
#
# Git picks the email via includeIf on the repo location, ssh picks the key via
# the current working directory. Because ssh inherits git's cwd, `git clone`
# from inside ~/projects/kopf3 already uses the work key, so remotes can stay
# plain git@github.com:... URLs.
{
  config,
  pkgs,
  ...
}: let
  username = config.hostSpec.username;
  homeDir = config.hostSpec.home;

  # ssh_config attribute names cannot carry a store path, so the predicate is
  # deployed to a fixed location and referenced via %d (the local home dir).
  inKopf3DirName = ".ssh/in-kopf3-dir";
  inKopf3Dir = pkgs.writeShellScript "ssh-in-kopf3-dir" ''
    case "$(pwd)/" in
      "$HOME"/projects/kopf3/*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';
  # `originalhost` (the name as typed) rather than `host`, so the kopf3.github.com
  # alias below is not also caught by these blocks. The two are mutually exclusive
  # on purpose: IdentityFile accumulates across matching blocks and ssh offers
  # agent-resident keys first, so overlapping blocks would offer the wrong key.
  kopf3Match = "Match originalhost github.com exec %d/${inKopf3DirName}";
  defaultMatch = "Match originalhost github.com !exec %d/${inKopf3DirName}";
in {
  home-manager.users.${username} = {lib, ...}: {
    home.activation.projectDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${homeDir}/projects/kopf3" "${homeDir}/projects/private"
    '';

    home.file.${inKopf3DirName} = {
      source = inKopf3Dir;
      executable = true;
    };

    programs.git.includes = [
      {
        condition = "gitdir:~/projects/kopf3/";
        contents.user.email = "max.vissing@kopf3.de";
      }
      {
        condition = "gitdir:~/projects/private/";
        contents.user.email = "max_vissing@yahoo.de";
      }
    ];

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          AddKeysToAgent = "yes";
        };
        ${kopf3Match} = {
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_kopf3_github";
        };
        # Escape hatch for remotes that still spell out the alias.
        "kopf3.github.com" = lib.hm.dag.entryAfter [kopf3Match] {
          HostName = "github.com";
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_kopf3_github";
        };
        ${defaultMatch} = lib.hm.dag.entryAfter ["kopf3.github.com"] {
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_github";
        };
      };
    };
  };
}
