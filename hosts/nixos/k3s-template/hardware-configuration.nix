{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  # Filesystems
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/BOOT-UUID";
    fsType = "vfat";
  };
}
