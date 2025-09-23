{pkgs, ...}: let
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
  home.file.".rust-toolchain".source = rustToolchain;
  home.packages = with pkgs; [
    jetbrains.rust-rover
    rustToolchain
    rust-analyzer
  ];
}
