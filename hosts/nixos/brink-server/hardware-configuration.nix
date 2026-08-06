# Lenovo ThinkCentre M70q — i5-10500T, 32 GB DDR4, single 1 TB NVMe.
#
# ⚠️ Partly provisional. The `fileSystems` block is *not* generated output — it
# is the layout docs/brink-server-install.md creates, and is therefore the
# source of truth for it rather than a record of it. The kernel-module lists are
# an educated guess and must be reconciled against
# `nixos-generate-config --root /mnt --no-filesystems` run on the hardware.
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

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  # Single-vdev ZFS on the one NVMe. No redundancy — that is accepted in the
  # migration plan (5.1) and paid for by replication into maxdata's `tank` in
  # Phase 11, not by mirroring here.
  #
  # The pool is called `fast` to match maxdata's NVMe pool, so that
  # /fast/k8s/local-path-provisioner means the same thing on both k3s servers
  # (Phases 6.2 and 8 both depend on that path).
  fileSystems."/" = {
    device = "fast/root";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "fast/nix";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "fast/home";
    fsType = "zfs";
  };

  fileSystems."/fast/k8s" = {
    device = "fast/k8s";
    fsType = "zfs";
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
