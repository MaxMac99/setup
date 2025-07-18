{pkgs, ...}: {
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    userEmail = "max_vissing@yahoo.de";
    userName = "Max Vissing";
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
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      rebase.autoStash = true;
    };
    includes = [
      {
        condition = "gitdir:~/kopf3/";
        path = "~/.gitconfig-kopf3";
      }
    ];
  };

  home.file.".gitconfig-kopf3".text = ''
    [user]
      email = max.vissing@kopf3.de
  '';
}
