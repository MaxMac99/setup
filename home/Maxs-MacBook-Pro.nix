{pkgs, ...}: {
  imports = [
    common/optional/terminals/ghostty.nix
    common/optional/ides/intellij.nix
    common/optional/ides/rust-rover.nix
  ];
  home.packages = with pkgs; [
    ffmpeg_6
    rclone
  ];
}
