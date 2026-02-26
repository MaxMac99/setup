{
  programs.nvf.settings.vim.languages = {
    enableDAP = true;
    enableExtraDiagnostics = true;
    enableFormat = true;
    enableTreesitter = true;

    bash.enable = true;
    css.enable = true;
    go.enable = true;
    html.enable = true;
    java.enable = true;
    kotlin.enable = true;
    lua.enable = true;
    markdown.enable = true;
    nix.enable = true;
    python.enable = true;
    rust = {
      enable = true;
      extensions = {
        crates-nvim.enable = true;
      };
    };
    sql = {
      enable = true;
      dialect = "postgres";
    };
    tailwind.enable = true;
    ts = {
      enable = true;
      lsp.enable = false;
    };
    yaml.enable = true;
  };
}
