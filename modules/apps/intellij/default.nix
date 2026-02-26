# IntelliJ IDEA Ultimate - nixpkgs + HM .ideavimrc
{config, pkgs, ...}: {
  environment.systemPackages = [pkgs.jetbrains.idea];

  home-manager.users.${config.hostSpec.username} = {
    home.file.".ideavimrc" = {
      source = ./ideavimrc;
      force = true;
    };
  };
}