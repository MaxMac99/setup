# Host metadata - data about each machine
{
  config,
  pkgs,
  lib,
  ...
}: {
  options.hostSpec = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "The username of the host";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "The hostname of the host";
    };
    email = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "The email of the user";
      default = {};
    };
    work = lib.mkOption {
      default = {};
      type = lib.types.attrsOf lib.types.anything;
      description = "An attribute set of work-related information";
    };
    networking = lib.mkOption {
      default = {};
      type = lib.types.attrsOf lib.types.anything;
      description = "An attribute set of networking information";
    };
    wifi = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used to indicate if a host has wifi";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      description = "The domain of the host";
      default = "local";
    };
    userFullName = lib.mkOption {
      type = lib.types.str;
      description = "The full name of the user";
      default = "Max Vissing";
    };
    handle = lib.mkOption {
      type = lib.types.str;
      description = "The handle of the user (eg: github user)";
      default = "MaxMac99";
    };
    home = lib.mkOption {
      type = lib.types.str;
      description = "The home directory of the user";
      default = let
        user = config.hostSpec.username;
      in
        if pkgs.stdenv.isLinux
        then "/home/${user}"
        else "/Users/${user}";
    };
    persistFolder = lib.mkOption {
      type = lib.types.str;
      description = "The folder to persist data if impermenance is enabled";
      default = "";
    };
    isMinimal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Used to indicate a minimal host (no home-manager)";
    };
  };
}