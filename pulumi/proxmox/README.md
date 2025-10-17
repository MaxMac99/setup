# Proxmox VM Management with Pulumi

This project manages Proxmox VMs declaratively using Pulumi and TypeScript.

## Project Structure

```
proxmox/
├── index.ts              # Main entry point
├── vms/                  # VM configurations
│   └── windows11.ts      # Windows 11 VM configuration
├── package.json          # Node.js dependencies
├── tsconfig.json         # TypeScript configuration
└── Pulumi.yaml          # Pulumi project configuration
```

## Setup

1. **Install dependencies**:
   ```bash
   yarn install
   ```

2. **Configure Proxmox credentials**:
   ```bash
   pulumi config set proxmoxve:endpoint https://192.168.178.2:8006
   pulumi config set proxmoxve:username root@pam
   pulumi config set proxmoxve:password YOUR_PASSWORD --secret
   pulumi config set proxmoxve:insecure true
   ```

## Deploy VMs

```bash
# Preview changes
pulumi preview

# Deploy all VMs
pulumi up

# Destroy all VMs
pulumi destroy
```

## Adding New VMs

1. Create a new file in `vms/` (e.g., `vms/ubuntu-server.ts`)
2. Export a function that creates the VM resource
3. Import and call it in `index.ts`

Example:

```typescript
// vms/ubuntu-server.ts
import * as proxmox from "@muhlba91/pulumi-proxmoxve";

export function createUbuntuServer() {
    return new proxmox.vm.VirtualMachine("ubuntu-server", {
        nodeName: "maxdata",
        name: "Ubuntu Server",
        vmId: 101,
        // ... configuration
    });
}
```

```typescript
// index.ts
import { createWindows11VM } from "./vms/windows11";
import { createUbuntuServer } from "./vms/ubuntu-server";

const windows11 = createWindows11VM();
const ubuntuServer = createUbuntuServer();

export const vms = {
    windows11: windows11.vmId,
    ubuntuServer: ubuntuServer.vmId,
};
```

## Windows 11 VM

### Configuration

The Windows 11 VM is configured to match the Unraid setup:

- **VM ID**: 100
- **CPU**: 6 vCPUs (host-passthrough with AES)
- **Memory**: 8GB
- **Machine**: Q35 with UEFI + TPM 2.0
- **Disk**: 70GB on fast NVMe pool (SATA initially, upgradeable to VirtIO SCSI)
- **Network**: VirtIO-Net with preserved MAC address (52:54:00:35:78:2a)
- **Video**: QXL with 128MB VRAM
- **USB**: Device 0d7a:0001 passthrough
- **VirtIO Drivers**: Auto-downloaded and mounted

### Customizing Windows 11 VM

You can customize the Windows 11 VM by passing a config object:

```typescript
import { createWindows11VM } from "./vms/windows11";

const windows11 = createWindows11VM({
    vmId: 100,
    vmName: "windows11",
    cpuCores: 8,
    memoryMB: 16384,
    diskSizeGB: 100,
    macAddress: "52:54:00:35:78:2a",
    usbDeviceId: "0d7a:0001",
});
```

### Migration from Unraid

#### Step 1: Upload Disk Image

```bash
# On Unraid, find your vdisk file (usually in /mnt/user/domains/Windows11/)
scp vdisk1.img max@192.168.178.2:/tmp/
```

#### Step 2: Import the Disk

```bash
# SSH to Proxmox
ssh max@192.168.178.2

# Import the disk
sudo qm importdisk 100 /tmp/vdisk1.img fast --format raw

# Check which disk has your data (look for significant "used" space)
sudo zfs list | grep vm-100

# Example output:
# fast/pve/vms/vm-100-disk-1  71.1G   782G    56K  -  (empty placeholder)
# fast/pve/vms/vm-100-disk-3  71.1G   747G  34.8G  -  (your Windows data!)

# Attach the disk with data (replace X with the correct disk number)
sudo qm set 100 --delete sata0
sudo qm set 100 --sata0 fast:vm-100-disk-X,cache=writeback,discard=on,ssd=1
```

#### Step 3: Start the VM

```bash
sudo qm start 100
```

**Important**: Make sure USB device 0d7a:0001 is plugged in before starting!

#### Troubleshooting: Boot Errors

If you see `INACCESSIBLE_BOOT_DEVICE` error:
- Windows uses SATA interface initially for compatibility
- The disk should boot correctly with SATA
- You can upgrade to VirtIO SCSI later for better performance (see below)

### Network Configuration

#### Option A: DHCP Reservation (Recommended)

Configure your DHCP server to assign a static IP to the VM's MAC address.

**In AdGuard Home:**
1. Go to Settings → DHCP settings
2. Add static lease:
   - MAC: `52:54:00:35:78:2a`
   - IP: `192.168.178.100` (or your preferred IP)
   - Hostname: `windows11`

#### Option B: Static IP in Windows

1. Boot into Windows
2. Open Network Settings (Win+X → Netzwerkverbindungen)
3. Right-click Ethernet adapter → Eigenschaften
4. Select "Internetprotokoll, Version 4 (TCP/IPv4)" → Eigenschaften
5. Set:
   - IP-Adresse: `192.168.178.100`
   - Subnetzmaske: `255.255.255.0`
   - Standardgateway: `192.168.178.1`
   - DNS-Server: `192.168.178.1`

### Upgrading to VirtIO SCSI (Optional)

After Windows boots successfully with SATA, you can upgrade to VirtIO SCSI for better performance.

#### Step 1: Install VirtIO SCSI Driver in Windows

The VirtIO drivers ISO is automatically mounted in Windows.

1. Open Device Manager (Win+X → Geräte-Manager)
2. Click **Aktion** → **Legacyhardware hinzufügen** → **Weiter**
3. Select **"Hardware manuell aus einer Liste auswählen und installieren"** → **Weiter**
4. Select **"Speichercontroller"** → **Weiter** → **Datenträger**
5. Browse to the mounted CD (e.g., `E:\vioscsi\w11\amd64`)
6. Install **"Red Hat VirtIO SCSI controller"**
7. Reboot Windows to load the driver

#### Step 2: Switch to VirtIO SCSI

1. **Shut down the VM from within Windows** (important!)
2. SSH to Proxmox and switch the disk controller:

```bash
ssh max@192.168.178.2

# Replace X with your actual disk number
sudo qm set 100 --delete sata0
sudo qm set 100 --scsi0 fast:vm-100-disk-X,cache=writeback,discard=on,iothread=1,ssd=1
sudo qm set 100 --boot order=scsi0

# Start the VM
sudo qm start 100
```

Windows should now boot with high-performance VirtIO SCSI!

### Installing Additional VirtIO Drivers

Install these drivers for better performance and integration:

#### VirtIO Network Driver (Better network performance)

1. Open Device Manager (Win+X → Geräte-Manager)
2. Find your network adapter (might show as "Ethernet-Controller" with warning)
3. Right-click → **Treiber aktualisieren** (Update Driver)
4. **Durchsuchen meines Computers** → **Auswählen aus einer Liste**
5. Click **Datenträger** (Have Disk)
6. Browse to `E:\NetKVM\w11\amd64`
7. Select "Red Hat VirtIO Ethernet Adapter" → Install
8. Reboot if prompted

#### Balloon Driver (Better memory management)

1. Open Device Manager (Win+X → Geräte-Manager)
2. Click **Aktion** → **Legacyhardware hinzufügen** → **Weiter**
3. Select **"Hardware manuell aus einer Liste auswählen und installieren"** → **Weiter**
4. Select **"Systemgeräte"** (System devices) → **Weiter** → **Datenträger**
5. Browse to `E:\Balloon\w11\amd64`
6. Install "VirtIO Balloon Driver"
7. Reboot if prompted

#### QEMU Guest Agent (Highly Recommended)

The Guest Agent provides better VM integration with Proxmox:
- See VM's IP address in Proxmox UI
- Cleanly shut down from Proxmox
- Better snapshot support
- Execute commands from host

**Installation:**
1. Open File Explorer
2. Navigate to the mounted VirtIO CD (usually D: or E:)
3. Go to `guest-agent` folder
4. Double-click `qemu-ga-x86_64.msi`
5. Follow the installation wizard (default settings are fine)
6. Service starts automatically after installation

## Storage Pools

- **fast**: NVMe (1TB) - For OS disks, databases, performance-critical VMs
- **tank**: RAIDZ1 HDD (12TB) - For bulk storage, backups, media

## Useful Commands

```bash
# Check Pulumi state
pulumi stack

# View outputs
pulumi stack output

# Refresh state from Proxmox
pulumi refresh

# View stack history
pulumi stack history
```

## Troubleshooting

### VM fails to start
- Check Proxmox logs: `journalctl -u pveproxy -f`
- Check VM status: `qm status <vmid>`
- View VM config: `qm config <vmid>`

### USB passthrough not working
- Verify USB device is plugged in: `lsusb`
- Check device ID matches: `lsusb | grep 0d7a:0001`

### Disk import fails
- Check available space: `zfs list`
- Verify pool exists: `zpool status`
- Check file permissions: `ls -lh /tmp/vdisk1.img`