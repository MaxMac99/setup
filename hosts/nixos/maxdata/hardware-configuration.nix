{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

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

  fileSystems."/" =
      { device = "fast/root";
        fsType = "zfs";
      };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/4F5B-A624";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  fileSystems."/nix" =
    { device = "fast/nix";
      fsType = "zfs";
    };

  fileSystems."/fast/pve" =
    { device = "fast/pve";
      fsType = "zfs";
    };

  fileSystems."/tank/data" =
    { device = "tank/data";
      fsType = "zfs";
    };

  fileSystems."/tank/backups" =
    { device = "tank/backups";
      fsType = "zfs";
    };

  fileSystems."/tank/pve" =
    { device = "tank/pve";
      fsType = "zfs";
    };

  fileSystems."/tank/k8s" =
    { device = "tank/k8s";
      fsType = "zfs";
    };

  fileSystems."/tank/fast-backup" =
    { device = "tank/fast-backup";
      fsType = "zfs";
    };

  fileSystems."/fast/k8s" =
    { device = "fast/k8s";
      fsType = "zfs";
    };

  fileSystems."/tank/timemachine-max" =
    { device = "tank/timemachine-max";
      fsType = "zfs";
    };

  fileSystems."/tank/timemachine-michael" =
    { device = "tank/timemachine-michael";
      fsType = "zfs";
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  services.fstrim.enable = true;
}