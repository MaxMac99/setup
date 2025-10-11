{pkgs, ...}: {
  imports = [
    common/core

    common/optional/browsers/chrome.nix

    # common/optional/terminals/alacritty.nix
    common/optional/terminals/ghostty.nix
    common/optional/ides/clion.nix
    common/optional/ides/intellij.nix
    common/optional/ides/rust-rover.nix
    common/optional/discord.nix
  ];
  home.packages = with pkgs; [
    ffmpeg_6
    (texlive.combine {
      inherit
        (texlive)
        scheme-medium
        latexmk
        minted
        fvextra
        upquote
        ifplatform
        xstring
        framed
        enumitem
        ;
    })
    python3
    python3Packages.pygments
  ];
}
