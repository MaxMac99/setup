# Rust Rover - nixpkgs + HM rust toolchain
{
  config,
  pkgs,
  ...
}: let
  rustToolchain = pkgs.symlinkJoin {
    name = "rust-toolchain";
    paths = [
      # unwrapped rustc is the only part that carries the target rlibs
      # (lib/rustlib/<target>/lib); the wrapped pkgs.rustc only ships bin/.
      pkgs.rustc.unwrapped
      pkgs.cargo
      pkgs.rustfmt
      pkgs.clippy
    ];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      mkdir -p $out/lib/rustlib/src/rust
      # Real tree, not a symlink: JetBrains copies the stdlib sources into its
      # own cache without following symlinks, so a symlinked src dir yields an
      # empty (→ "corrupted") copy. Only library/ is needed (76 MB of the
      # 1.6 GB rust-src tarball); the root manifests make it look like the
      # upstream rust workspace.
      cp -RL ${pkgs.rustPlatform.rustcSrc}/library $out/lib/rustlib/src/rust/library/
      cp ${pkgs.rustPlatform.rustcSrc}/Cargo.toml $out/lib/rustlib/src/rust/Cargo.toml
      cp ${pkgs.rustPlatform.rustcSrc}/Cargo.lock $out/lib/rustlib/src/rust/Cargo.lock
      # Wrapped rustc reports its inner (sourceless) store path as sysroot, so
      # IDEs auto-attaching stdlib via `rustc --print sysroot` find nothing and
      # produce an empty (→ "corrupted") copy. Pin the sysroot to the merged
      # toolchain, which has both the src symlink and the rlibs.
      for tool in rustc rustdoc; do
        rm $out/bin/$tool
        makeWrapper ${pkgs.rustc}/bin/$tool $out/bin/$tool --add-flags "--sysroot $out"
      done
    '';
  };
in {
  environment.systemPackages = [pkgs.jetbrains.rust-rover];

  home-manager.users.${config.hostSpec.username} = {
    home.file.".rust-toolchain".source = rustToolchain;
    # rust-analyzer comes from config.lspPackages (modules/data/lsp.nix).
    home.packages = [
      rustToolchain
      pkgs.protobuf
    ];
  };
}
