# Rust Rover - nixpkgs + HM rust toolchain
{config, pkgs, ...}: let
  rustToolchain = pkgs.symlinkJoin {
    name = "rust-toolchain";
    paths = [
      pkgs.rustc
      pkgs.cargo
      pkgs.rustfmt
      pkgs.clippy
    ];
    postBuild = ''
      mkdir -p $out/lib/rustlib/src
      ln -s ${pkgs.rustPlatform.rustcSrc} $out/lib/rustlib/src/rust
    '';
  };
in {
  environment.systemPackages = [pkgs.jetbrains.rust-rover];

  home-manager.users.${config.hostSpec.username} = {
    home.file.".rust-toolchain".source = rustToolchain;
    home.packages = [
      rustToolchain
      pkgs.rust-analyzer
    ];
  };
}