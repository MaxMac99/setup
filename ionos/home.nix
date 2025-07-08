{
  config,
  pkgs,
  ...
}: {
  home.username = "max";
  home.homeDirectory = "/home/max";

  home.packages = with pkgs; [
    # archives
    zip
    unzip

    # utils
    jq

    # networking
    iperf3
    dnsutils
    socat
    nmap
  ];

  programs.git = {
    enable = true;
    userName = "Max Vissing";
    userEmail = "max_vissing@yahoo.de";
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = ["git" "dirhistory" "docker" "docker-compose" "jsontools"];
      theme = "robbyrussell";
    };
    shellAliases = {
      ll = "ls -lA";
    };
  };

  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
}
