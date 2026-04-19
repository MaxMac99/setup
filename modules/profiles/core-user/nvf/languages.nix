{
  programs.nvf.settings.vim = {
    lsp.presets.tailwindcss-language-server.enable = true;
    languages = {
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
      markdown = {
        enable = true;
        lsp.enable = false; # marksman LSP pulls in dotnet SDK built from source
      };
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
        extraDiagnostics.enable = false;
        format.enable = false;
      };
      typescript = {
        enable = true;
        lsp.enable = false;
      };
      yaml.enable = true;
    };
  };
}
