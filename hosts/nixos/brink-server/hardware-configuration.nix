# Lenovo ThinkCentre M70q — i5-10500T, 32 GB DDR4, single 1 TB NVMe.
#
# The `fileSystems` block is *not* generated output — it is the layout
# docs/brink-server-install.md creates, and is therefore the source of truth for
# it rather than a record of it. Everything else below was verified byte-for-byte
# against `nixos-generate-config --root /mnt --no-filesystems` on the hardware,
# 2026-08-06, and matched.
#
# Regenerate with `--no-filesystems` only, or the generated file will overwrite
# the layout below with by-uuid device paths.
{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  # Single-vdev ZFS on the one NVMe, pool `main`. No redundancy — that is
  # accepted in the migration plan (5.1) and paid for by replication into
  # maxdata's `tank` in Phase 11, not by mirroring here.
  #
  # **Native ZFS mountpoints, mounted with `-o zfsutil` — not `mountpoint=legacy`.**
  # Legacy makes NixOS the only thing able to mount a dataset, so every dataset
  # created later needs a matching `fileSystems` entry or it silently never
  # mounts. That is exactly how maxdata acquired SMB datasets that appear
  # nowhere in its configuration (Phase 0.1 lists them as a surprise). With
  # native mountpoints `zfs list` shows the truth, and relocating a dataset is
  # `zfs set mountpoint=` with no rebuild.
  #
  # Only the boot-critical datasets are declared here. Data datasets —
  # `main/k8s` and anything added later — are deliberately *absent*:
  # `zfs-mount.service` mounts them from the pool, which is the whole point.
  # `/home` is declared despite not being boot-critical, so that user creation
  # at activation cannot land files on the root dataset before ZFS mounts over
  # the top.
  fileSystems."/" = {
    device = "main/root";
    fsType = "zfs";
    options = ["zfsutil"];
  };

  fileSystems."/nix" = {
    device = "main/nix";
    fsType = "zfs";
    options = ["zfsutil"];
  };

  fileSystems."/home" = {
    device = "main/home";
    fsType = "zfs";
    options = ["zfsutil"];
  };

  # By label rather than by-uuid: the UUID is only known once mkfs has run, and
  # the install procedure sets this label explicitly (`mkfs.vfat -n BOOT`).
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # No services.fstrim: it does nothing for ZFS. The pool is created with
  # `autotrim=on` instead.
}
