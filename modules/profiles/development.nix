# Development tools profile
{config, pkgs, ...}: {
  home-manager.users.${config.hostSpec.username}.home.packages = with pkgs; [
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

    # JS / Java
    nodejs_24
    yarn
    maven
    temurin-bin-21
  ];
}