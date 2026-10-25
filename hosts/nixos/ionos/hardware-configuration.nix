{modulesPath, ...}: {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];

  boot = {
    loader.grub.device = "/dev/vda";
    # ⚠️ qxl hung the shutdown on 2026-10-25: it logged `[TTM] Buffer eviction
    # failed` ~100k times over 18 days, and PID 1 blocked in D state on a mutex
    # held by qxl's framebuffer damage worker while writing to the console, so
    # `systemctl reboot` never completed and the box needed a panel reset. The
    # VPS is headless; without qxl the panel console falls back to vgacon.
    blacklistedKernelModules = ["qxl"];
    initrd = {
      availableKernelModules = ["ata_piix" "uhci_hcd" "xen_blkfront" "vmw_pvscsi"];
      kernelModules = ["nvme"];
    };
  };
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };
}
