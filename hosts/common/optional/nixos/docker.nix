{...}: {
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      # ipv6 = true;
    };
  };
}
