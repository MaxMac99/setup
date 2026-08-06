{modulesPath, ...}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage" "uas"];
    # Disable UAS for the ASM1153 USB-SATA bridge — Pi 4 + ASM1153 drops under
    # sustained write load (e.g. kernel rebuilds), corrupting the root fs.
    kernelParams = ["usb-storage.quirks=174c:55aa:u"];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = ["nofail"];
  };
}
