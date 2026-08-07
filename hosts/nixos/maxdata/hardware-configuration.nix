{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # NVIDIA Quadro RTX 4000 GPU
  # Uncomment if you want to use the GPU in the host or for GPU passthrough
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.nvidia.modesetting.enable = true;
  # hardware.nvidia.open = false; # Use proprietary driver for Quadro

  # For GPU passthrough to VMs:
  # boot.kernelParams = [ "amd_iommu=on" "iommu=pt" ];
  # boot.kernelModules = [ "vfio-pci" ];
  # boot.extraModprobeConfig = ''
  #   options vfio-pci ids=10de:1eb8 # Replace with your GPU device ID
  # '';

  fileSystems."/" = {
    device = "fast/root";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/4F5B-A624";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  fileSystems."/nix" = {
    device = "fast/nix";
    fsType = "zfs";
  };

  fileSystems."/tank/data" = {
    device = "tank/data";
    fsType = "zfs";
  };

  fileSystems."/tank/backups" = {
    device = "tank/backups";
    fsType = "zfs";
  };

  fileSystems."/tank/k8s" = {
    device = "tank/k8s";
    fsType = "zfs";
  };

  # ⚠️ Declared because it is `mountpoint=legacy`, and a legacy dataset with no
  # `fileSystems` entry never mounts — it just loses to a directory of the same
  # name in the parent. That is not hypothetical here: this dataset sat at 96 K
  # and unmounted while 689 G of Time Machine data accumulated in `tank/k8s`
  # itself, inheriting the parent's properties and ignoring the 3 T quota meant
  # to bound it. Moved into the real dataset 2026-08-07.
  #
  # Nested under `/tank/k8s`, so systemd orders this mount after its parent's
  # automatically. That ordering is the reason this one is declared rather than
  # given a native mountpoint like D13 prefers for data datasets: the parent is
  # a legacy fstab mount, and leaving the child to `zfs-mount.service` would put
  # two independent mounting mechanisms in a race at boot — the losing order
  # recreating exactly the shadowing this fixes.
  fileSystems."/tank/k8s/timemachine" = {
    device = "tank/k8s/timemachine";
    fsType = "zfs";
  };

  fileSystems."/tank/fast-backup" = {
    device = "tank/fast-backup";
    fsType = "zfs";
  };

  fileSystems."/fast/k8s" = {
    device = "fast/k8s";
    fsType = "zfs";
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  services.fstrim.enable = true;
}
