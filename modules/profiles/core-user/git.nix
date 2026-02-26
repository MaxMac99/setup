{...}: {
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
  };
}
