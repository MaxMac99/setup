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
      # Chrome is a homebrew cask now (modules/apps/google-chrome.nix) - it
      # lives at the plain /Applications path, not the old "Nix Apps" dir.
      sessionVariables.PUPPETEER_EXECUTABLE_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
      packages = with pkgs;
        [
          wt
        ]
        ++ [
          # General dev tools
          exiftool
          cargo
          dotenv-cli

          # Nix tooling
          nixpkgs-fmt
          selene
          # TEMP-FIX(2026-09-27): statix's own check phase fails on this
          # nixpkgs rev; retry without override at the next nixpkgs release
          # jump. See docs/workarounds.md.
          (statix.overrideAttrs (_: {doCheck = false;}))

          # Cloud / API
          azure-cli
          pulumi
          pulumiPackages.pulumi-nodejs
          pulumiPackages.pulumi-bun
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
          bun
          maven
          temurin-bin-21
        ];
    };
  };
}
