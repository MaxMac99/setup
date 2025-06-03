{ config
, ...
}:
let
  hostSpec = config.hostSpec;
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in
{
  # User config applicable to both nixos and darwin
  users.users.${hostSpec.username} = {
    home = "/home/${hostSpec.username}";
    isNormalUser = true;
    extraGroups = lib.flatten [
      "wheel"
      (ifTheyExist [
        "docker"
        "git"
      ])
    ];
  };
  users.defaultUserShell = pkgs.zsh;

  programs.git.enable = true;
}
