{...}: {
  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;
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
      # Scratch space for the opencode ticket workflow - drafts, fetched ticket
      # bodies. See docs/opencode-workflow.md.
      ".work/"
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
