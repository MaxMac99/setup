{pkgs, ...}: {
  imports = [
    common/optional/terminals/ghostty.nix
    common/optional/ides/intellij.nix
    common/optional/ides/rust-rover.nix
    common/optional/ides/zed.nix
  ];
  home.packages = with pkgs; [
    ffmpeg_6
    rclone
  ];
}
