{pkgs, ...}: {
  home.packages = with pkgs; [
    jetbrains.idea-ultimate
  ];

  home.file.".ideavimrc".source = ./ideavimrc;
}
