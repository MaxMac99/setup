# Development tools profile
{
  config,
  pkgs,
  ...
}: {
  home-manager.users.${config.hostSpec.username} = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    home = {
      sessionVariables.PUPPETEER_EXECUTABLE_PATH = "/Applications/Nix Apps/Google Chrome.app/Contents/MacOS/Google Chrome";
      packages = with pkgs; [
        # General dev tools
        claude-code
        exiftool
        cargo
        dotenv-cli

        # Nix tooling
        nixpkgs-fmt
        selene
        statix

        # Cloud / API
        azure-cli
        pulumi
        pulumiPackages.pulumi-nodejs
        openapi-generator-cli
        openapi-down-convert

        # Documentation
        asciidoctor-with-extensions
        mermaid-cli

        # JS / Java
        nodejs_24
        yarn
        maven
        temurin-bin-21
      ];
    };
  };
}
