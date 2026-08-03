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
      # Server choice is aligned with opencode's built-ins (modules/data/lsp.nix):
      # opencode only knows nixd, and its pyright recipe handles venv detection.
      nix = {
        enable = true;
        lsp.servers = ["nixd"];
      };
      python = {
        enable = true;
        lsp.servers = ["pyright"];
      };
      rust = {
        enable = true;
        extensions = {
          crates-nvim.enable = true;
        };
      };
      sql = {
        enable = true;
        extraDiagnostics.enable = false;
        format.enable = false;
      };
      typescript = {
        enable = true;
        lsp.enable = true;
      };
      yaml.enable = true;
    };
  };
}
