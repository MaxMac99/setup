{ config, pkgs, modulesPath, lib, ... }:

{
  imports =
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/common/optional/nixos/openssh.nix"
      "modules/nixos/k3s-base.nix"
    ])
    ++ [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  # System platform
  nixpkgs.hostPlatform = "x86_64-linux";

  # Host specification
  hostSpec = {
    username = "max";
    hostName = "k3s-template";
    isDarwin = false;
    isWork = false;
    isServer = true;
    isMinimal = true;
  };

  # Bootloader - Simple GRUB setup for Proxmox (nixos-generators handles the rest)
  boot = {
    loader.grub = {
      enable = lib.mkDefault true;
      device = lib.mkDefault "/dev/vda";
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Networking (time zone set in hosts/common/core)
  networking = {
    hostId = "00000000"; # Placeholder - cloud-init will set unique IDs
    useDHCP = false; # Static IPs configured via cloud-init
    firewall.enable = false; # K3S manages its own firewall rules
    nameservers = config.networkConfig.dns.servers;
    fqdn = "k3s-template.local"; # Set explicitly to avoid evaluation issues
  };

  # Enable cloud-init for VM customization
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # Disable k3s auto-start in template - cloud-init will start it after hostname is set
  systemd.services.k3s.wantedBy = lib.mkForce [];

  # Additional system packages (basic packages from hosts/common/users/primary)
  environment.systemPackages = with pkgs; [
    htop
    wget
  ];

  # K3S service is enabled in k3s-base.nix but not started on boot
  # Cloud-init will start it after configuring hostname, role, token, etc.

  system.stateVersion = "24.11";
}