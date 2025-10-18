{pkgs, ...}: {
  systemd.services.ipforward = {
    description = "Forwards IPv4 through Wireguard to the internal network";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:443,fork,su=nobody TCP4:192.168.178.2:443";
      Restart = "always";
    };
  };
}
