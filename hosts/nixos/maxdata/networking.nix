{ config, lib, pkgs, ... }:

{
  # Enable networking
  networking.networkmanager.enable = false; # We use systemd-networkd for servers
  networking.useDHCP = false; # Disable default DHCP since we use systemd-networkd
  networking.useNetworkd = true; # Use systemd-networkd

  # Use systemd-networkd for consistent network configuration
  systemd.network.enable = true;
  
  # Proxmox bridge interface (vmbr0)
  # This is where VM network interfaces will be attached
  systemd.network.netdevs."20-vmbr0" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "vmbr0";
    };
  };

  # Bind physical interface to bridge (no IP on physical interface)
  systemd.network.networks."20-vmbr0-bind" = {
    matchConfig.Name = "enp*";
    networkConfig.Bridge = "vmbr0";
    linkConfig.RequiredForOnline = "enslaved";
  };

  systemd.network.networks."30-vmbr0" = {
    matchConfig.Name = "vmbr0";
    # Optional: Static IP on bridge
     networkConfig = {
       Address = "192.168.178.2/24";
       Gateway = "192.168.178.1";
       DNS = [ "192.168.178.1" "1.1.1.1" ];
       IPv6AcceptRA = true;
     };
  };

  # Open firewall for Proxmox
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      8006  # Proxmox Web UI
      5900  # VNC (for VM consoles) - adjust range as needed
      111   # NFS portmapper
      2049  # NFS
      3128  # Proxmox Subscription (optional)
    ];
    allowedUDPPorts = [
      111   # NFS portmapper
      2049  # NFS
    ];
    # Allow traffic between VMs on the bridge
    trustedInterfaces = [ "vmbr0" ];
  };

  # Enable avahi for mDNS (optional - for .local domain)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

  # Hostname resolution
  # IMPORTANT: Proxmox requires hostname to resolve to non-loopback IP
  networking.extraHosts = ''
    192.168.178.2 maxdata.local maxdata
  '';
}
