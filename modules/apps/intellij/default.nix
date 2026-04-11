# IntelliJ IDEA Ultimate - homebrew cask + HM .ideavimrc
{config, ...}: {
  homebrew.casks = ["intellij-idea"];

  home-manager.users.${config.hostSpec.username} = {
    home.file.".ideavimrc" = {
      source = ./ideavimrc;
      force = true;
    };
  };
}
