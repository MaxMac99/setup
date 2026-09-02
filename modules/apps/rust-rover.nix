# Rust Rover - nixpkgs + HM rust toolchain
{
  config,
  lib,
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
      # toolchain, which has both the src tree and the rlibs.
      for tool in rustc rustdoc; do
        rm $out/bin/$tool
        makeWrapper ${pkgs.rustc}/bin/$tool $out/bin/$tool --add-flags "--sysroot $out"
      done
    '';
  };

  # JetBrains copies stdlib sources into its own cache
  # (~/Library/Caches/JetBrains/*/intellij-rust/stdlib-local-copy/<ver>-<hash>)
  # preserving directory attributes, so the copy of the read-only Nix store
  # tree ends up read-only (→ AccessDeniedException / "corrupted"). Pre-filling
  # the versioned cache dir with writable content makes the IDE accept it
  # as-is (it early-returns when the marker exists and looks valid). Run with
  # the IDE closed; needed again after a rustc version bump (marker name
  # changes with the version).
  rustStdlibCacheFix = pkgs.writeShellScriptBin "rust-stdlib-cache-fix" ''
    set -euo pipefail
    src="$HOME/.rust-toolchain/lib/rustlib/src/rust"
    [ -d "$src/library" ] || {
      echo "no stdlib sources at $src" >&2
      exit 1
    }
    shopt -s nullglob
    filled=0
    for marker in "$HOME/Library/Caches/JetBrains/"*"/intellij-rust/stdlib-local-copy/"*/; do
      [ -f "$marker/Cargo.lock" ] && continue
      chmod -R u+w "$marker"
      cp -R "$src/library" "$marker/library"
      cp "$src/Cargo.toml" "$src/Cargo.lock" "$marker/"
      # the copies carry the read-only store modes; make the whole marker
      # writable so the IDE can (re)write into it
      chmod -R u+w "$marker"
      filled=1
      echo "filled: $marker"
    done
    [ "$filled" = 1 ] || echo "nothing to fill (all markers already valid)"
  '';
in {
  environment.systemPackages = [pkgs.jetbrains.rust-rover];

  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
    home.file.".rust-toolchain".source = rustToolchain;
    # rust-analyzer comes from config.lspPackages (modules/data/lsp.nix).
    home.packages = [
      rustToolchain
      rustStdlibCacheFix
      pkgs.protobuf
    ];
    # Fill empty IDE stdlib caches on every rebuild, so a rustc version bump
    # is healed without manual steps (no-op while all markers are valid).
    home.activation.rustStdlibCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${rustStdlibCacheFix}/bin/rust-stdlib-cache-fix || true
    '';
  };
}
