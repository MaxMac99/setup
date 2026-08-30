# Development tools profile
{
  config,
  pkgs,
  ...
}: let
  # Worktree helper enforcing the <repo>/.work/<repo>-<branch> convention.
  # Layout rules live in the script header and in each repo's AGENTS.md.
  wt = pkgs.writeShellApplication {
    name = "wt";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      findutils
      git
    ];
    text = builtins.readFile ./wt.sh;
  };
in {
  home-manager.users.${config.hostSpec.username} = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      # Auto-allow .envrc under the projects tree so fresh checkouts and
      # worktrees get their environment on first `cd` without `direnv allow`.
      config.whitelist.prefix = ["/Users/maxvissing/projects/"];
    };
    home = {
      sessionVariables.PUPPETEER_EXECUTABLE_PATH = "/Applications/Nix Apps/Google Chrome.app/Contents/MacOS/Google Chrome";
      packages = with pkgs;
        [
          wt
        ]
        ++ [
          # General dev tools
          claude-code
          exiftool
          cargo
          dotenv-cli

          # Nix tooling
          nixpkgs-fmt
          selene
          (statix.overrideAttrs (_: {doCheck = false;}))

          # Cloud / API
          azure-cli
          pulumi
          pulumiPackages.pulumi-nodejs
          openapi-generator-cli
          openapi-down-convert

          # Documentation
          asciidoctor-with-extensions
          mermaid-cli
          # snacks.image shells out to `mmdc` to render mermaid inline in neovim,
          # and to ImageMagick's `identify` for image dimensions.
          imagemagick

          # JS / Java
          nodejs_24
          pnpm
          yarn
          maven
          temurin-bin-21
        ];
    };
  };
}
