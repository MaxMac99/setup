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

  # TEMP-FIX(2026-10-15): pulumi 3.268.0 added a `tool` dependency
  # (go-ruleguard/dsl) to pulumi-language-bun's go.mod, but nixpkgs still
  # builds it with `vendorHash = null`, so `-mod=vendor` fails with
  # "inconsistent vendoring". Vendor the modules ourselves. Expires when
  # nixpkgs sets a vendorHash for pulumi-bun. See docs/workarounds.md.
  pulumi-bun = pkgs.pulumiPackages.pulumi-bun.overrideAttrs (old: {
    paths = [
      (old.passthru.unwrapped.overrideAttrs {
        vendorHash = "sha256-Fps7U7ORVPaOloJCAiz9sxqinZIxQmYxPv7eQoiR4hk=";
      })
      pkgs.pulumiPackages.pulumi-nodejs
    ];
  });
in {
  # TEMP-FIX(2026-10-25): nixpkgs bumped invoke to 3.x, which no released
  # fabric supports, so fabric is marked broken and azure-cli (which depends
  # on it) refuses to evaluate. Mirror NixOS/nixpkgs#576874: build fabric from
  # the unreleased commit that adds invoke 3 support. Expires when #576874
  # (or another fabric fix) lands in our nixpkgs. See docs/workarounds.md.
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions =
        prev.pythonPackagesExtensions
        ++ [
          (_: pyPrev: {
            fabric = pyPrev.fabric.overridePythonAttrs (old: {
              version = "3.2.3-unstable-2026-04-07";
              src = final.fetchFromGitHub {
                owner = "fabric";
                repo = "fabric";
                rev = "cc098ad475dbbe2e10aba72692d83aee58919570";
                hash = "sha256-Z1tGcjdLrzbqcbS6XwapSgDNpyLbBiO21yeqi7XhbpQ=";
              };
              meta = old.meta // {broken = false;};
            });
          })
        ];
    })
  ];

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
          statix

          # Cloud / API
          azure-cli
          pulumi
          pulumiPackages.pulumi-nodejs
          pulumi-bun
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
