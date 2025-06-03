{ pkgs, homebrew-core, homebrew-cask, homebrew-bundle, ... }:

let user = "max"; in
{
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ./hardware-configuration.nix
  ];

  environment = {
    systemPackages = with pkgs; [
      curl
      vim
      git
    ];
    variables.EDITOR = "vim";
  };

  boot = {
    tmp.cleanOnBoot = true;
    loader
      };
      zramSwap.enable = true;

    networking = {
      hostName = "ionos";
      domain = "";
      firewall = {
        allowedTCPPorts = [ 22 80 443 ];
        allowedUDPPorts = [ 56527 ];
      };
      wireguard.interfaces = {
        wg0 = {
          ips = [ "192.168.178.201/24" "fda8:a1db:5685::201/64" ];
          listenPort = 56527;
          privateKeyFile = "/home/max/.wireguard/private_key";

          peers = [
            {
              publicKey = "ulBtv6Iou8HKpJzeJS9YALlZTSKE1+W+fZCEzM3hGiw=";
              presharedKeyFile = "/home/max/.wireguard/preshared_key";
              allowedIPs = [ "192.168.178.0/24" "fda8:a1db:5685::/64" ];
              endpoint = "bzwkhrd8hexv5q4g.myfritz.net:56527";
              persistentKeepalive = 25;
            }
          ];
        };
      };
    };

    users = {
      users.${user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGn3D12oPl2/DO5fdKseTbJCD74ozEOjljPcI0sDNHKl maxvissing@Maxs-MacBook-Pro.local"
        ];
      };
      defaultUserShell = pkgs.zsh;
    };
    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    systemd.services.ipforward = {
      description = "Forwards IPv4 through Wireguard to the internal network";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:443,fork,su=nobody TCP4:192.168.178.97:443";
        Restart = "always";
      };
    };

    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
      daemon.settings = {
        # ipv6 = true;
      };
    };

    system.stateVersion = "25.05";
  }
