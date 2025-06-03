{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userEmail = "max_vissing@yahoo.de";
    userName = "Max Vissing";
  };
}
