{pkgs, ...}: {
  home.file.".ideavimrc" = {
    source = ./ideavimrc;
    force = true;
  };
}
