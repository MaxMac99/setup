import * as proxmox from "@muhlba91/pulumi-proxmoxve";

/**
 * Windows 11 VM Configuration
 *
 * Migrated from Unraid with the following specs:
 * - CPU: 6 vCPUs (3 cores × 2 threads, host-passthrough)
 * - Memory: 8GB
 * - Machine: Q35 with UEFI + TPM 2.0
 * - Disk: 70GB on fast NVMe pool
 * - Network: VirtIO-Net (MAC: 52:54:00:35:78:2a)
 * - USB: Device 0d7a:0001 passthrough
 */

export interface Windows11Config {
    vmId: number;
    vmName: string;
    cpuCores: number;
    memoryMB: number;
    diskSizeGB: number;
    macAddress: string;
    usbDeviceId: string;
}

export const defaultConfig: Windows11Config = {
    vmId: 100,
    vmName: "windows11",  // DNS-compliant name (no spaces, lowercase)
    cpuCores: 6,
    memoryMB: 8192,
    diskSizeGB: 70,
    macAddress: "52:54:00:35:78:2a",
    usbDeviceId: "0d7a:0001",
};

// Download VirtIO drivers ISO to Proxmox
// This provides Windows drivers for VirtIO devices (SCSI, Network, etc.)
export const virtioISO = new proxmox.storage.File("virtio-drivers", {
    nodeName: "maxdata",
    datastoreId: "local",
    contentType: "iso",
    sourceFile: {
        path: "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso",
        fileName: "virtio-win.iso",
    },
});

export function createWindows11VM(config: Windows11Config = defaultConfig) {
    return new proxmox.vm.VirtualMachine("windows11", {
        nodeName: "maxdata",
        name: config.vmName,
        vmId: config.vmId,

        // CPU configuration - matching Unraid: 6 vCPUs (3 cores × 2 threads)
        cpu: {
            cores: config.cpuCores,
            sockets: 1,
            type: "host", // host-passthrough equivalent in Proxmox
            flags: ["+aes"], // Enable AES instructions
            numa: false,
        },

        // Memory configuration
        memory: {
            dedicated: config.memoryMB,
        },

        // UEFI BIOS with Secure Boot (matching OVMF)
        bios: "ovmf",

        // EFI disk
        efiDisk: {
            datastoreId: "fast",
            fileFormat: "raw",
            type: "4m",
        },

        // TPM 2.0 (matching Unraid TPM configuration)
        tpmState: {
            datastoreId: "fast",
            version: "v2.0",
        },

        // Main OS disk - SATA for Windows compatibility
        // NOTE: We create a placeholder disk here, but you'll import vdisk1.img after deployment
        // Stored on FAST (NVMe) for better Windows performance
        // Using SATA instead of SCSI to avoid INACCESSIBLE_BOOT_DEVICE errors when migrating from Unraid
        disks: [
            {
                interface: "scsi0",
                datastoreId: "fast", // Use fast NVMe pool for OS disk
                size: config.diskSizeGB,
                fileFormat: "raw",
                cache: "writeback", // Matching Unraid cache setting
                discard: "on", // Matching Unraid discard=unmap
                ssd: true, // This is an SSD (NVMe)
            },
        ],

        // Network - VirtIO with specific MAC address
        networkDevices: [
            {
                bridge: "vmbr0",
                model: "virtio",
                macAddress: config.macAddress, // Preserve MAC from Unraid
            },
        ],

        // USB passthrough (Device from Unraid)
        usbs: [
            {
                host: config.usbDeviceId, // Vendor:Product ID
                usb3: false, // USB 2.0
            },
        ],

        // Mount VirtIO drivers ISO for Windows driver installation
        // This allows upgrading from SATA to VirtIO SCSI for better performance
        cdrom: {
            fileId: virtioISO.id,
        },

        // SATA controller (better Windows compatibility for migrations)
        // Note: Can switch to VirtIO SCSI after installing VirtIO drivers in Windows
        scsiHardware: "virtio-scsi-single",

        // Machine type - Q35 (matching Unraid)
        machine: "q35",

        // QEMU Guest Agent
        agent: {
            enabled: true,
            trim: true,
            type: "virtio",
        },

        // Keyboard layout
        keyboardLayout: "de",

        // Boot order
        bootOrders: ["scsi0"],

        // Start on boot
        onBoot: true,
        started: true, // Don't auto-start until disk is restored

        // Operating system type
        operatingSystem: {
            type: "win11",
        },

        // Advanced settings for Windows optimization
        // These match the Hyper-V enlightenments from Unraid
        vga: {
            type: "qxl", // QXL video (matching Unraid)
            memory: 128, // 128MB VRAM (Unraid has 131072 KB ≈ 128MB)
        },
    });
}