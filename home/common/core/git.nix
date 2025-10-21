{config, lib, ...}: {
  programs.git = {
    enable = true;
    lfs.enable = true;
    ignores = [
      ".DS_Store"
      ".idea"
      ".vscode"
      "*.swp"
      "result"
      "node_modules"
      "dist"
      "build"
      "target"
      "*.log"
    ];
    settings = {
      user = {
        email = "max_vissing@yahoo.de";
        name = "Max Vissing";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      rebase.autoStash = true;
    };
    includes = lib.optionals config.hostSpec.isWork [
      {
        condition = "gitdir:~/kopf3/";
        path = "~/.gitconfig-kopf3";
      }
    ];
  };

  home.file = lib.optionalAttrs config.hostSpec.isWork {
    ".gitconfig-kopf3".text = ''
      [user]
        email = max.vissing@kopf3.de
    '';
  };
}
