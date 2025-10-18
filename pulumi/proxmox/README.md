# Proxmox VM Management with Pulumi

This project manages Proxmox VMs declaratively using Pulumi and TypeScript.

## Project Structure

```
proxmox/
├── index.ts              # Main entry point
├── vms/                  # VM configurations
│   ├── windows11.ts      # Windows 11 VM configuration
│   └── k3s.ts            # K3S cluster node configurations
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

## K3S Cluster

### Configuration

The K3S cluster consists of 3 NixOS-based nodes:

| Node | VM ID | Role | CPU | Memory | Disk | Storage |
|------|-------|------|-----|--------|------|---------|
| k3s-node1 | 201 | Control Plane + Worker | 2 vCPUs | 6GB | 32GB | fast |
| k3s-node2 | 202 | Control Plane + Worker | 2 vCPUs | 6GB | 32GB | fast |
| k3s-node3 | 203 | Control Plane + Worker | 2 vCPUs | 6GB | 32GB | fast |

All nodes use:
- **UEFI boot** for modern boot process
- **VirtIO SCSI** for best performance (Linux native support)
- **VirtIO-Net** for networking
- **QEMU Guest Agent** for Proxmox integration

### Deployment Steps

The deployment uses **nixos-generators** to create a Proxmox template, then Pulumi clones that template for each node. This is fast and follows Proxmox best practices.

#### Step 1: Build the NixOS Template

**On your Proxmox host**, run the build script:

```bash
# SSH to Proxmox
ssh root@192.168.178.2

# Clone your configuration repository
git clone https://github.com/YOUR_USERNAME/setup.git
cd setup

# Update flake
nix flake update

# Build the template (takes 5-10 minutes)
./scripts/build-k3s-image.sh
```

This will:
1. Use nixos-generators to build a Proxmox image from your `k3s-template` configuration
2. Save it to `/var/lib/vz/dump/`
3. Restore as VM template with ID 9000
4. Template includes NixOS + k3s pre-installed

**One-time setup!** You only need to rebuild the template when you change the base NixOS configuration.

#### Step 2: Configure Pulumi

**On your local machine:**

1. Update SSH keys in `pulumi/proxmox/vms/k3s.ts` (line 38):
   ```typescript
   const SSH_KEYS = [
       "ssh-ed25519 AAAA... your-actual-key",
   ];
   ```

2. Update k3s token in `pulumi/proxmox/vms/k3s.ts` (line 36):
   ```typescript
   const K3S_TOKEN = pulumi.output(pulumi.secret("your-strong-secret-token"));
   ```

#### Step 3: Deploy with Pulumi

```bash
cd pulumi/proxmox

# Preview what will be created
pulumi preview

# Deploy the cluster (clones template 3x, takes ~30 seconds)
pulumi up
```

Pulumi will:
1. Clone template 9000 three times (for nodes 201, 202, 203)
2. Customize each clone via cloud-init:
   - Set hostname
   - Configure SSH keys
   - Set k3s token and cluster settings
3. Start all VMs
4. Cloud-init configures k3s automatically

**Total time: ~1 minute** (vs 30-45 minutes with manual installation)

#### Step 4: Verify Cluster

Wait ~2 minutes for k3s to initialize, then:

```bash
# SSH to first node
ssh max@192.168.178.201

# Check cluster status
sudo kubectl get nodes
```

Expected output:
```
NAME        STATUS   ROLES                       AGE   VERSION
k3s-node1   Ready    control-plane,etcd,master   2m    v1.28.x+k3s1
k3s-node2   Ready    control-plane,etcd,master   1m    v1.28.x+k3s1
k3s-node3   Ready    control-plane,etcd,master   1m    v1.28.x+k3s1
```

#### Step 5: Configure Local kubectl

```bash
# Copy kubeconfig
ssh max@192.168.178.201 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/k3s-config

# Update server address
sed -i '' 's/127.0.0.1/192.168.178.201/g' ~/.kube/k3s-config

# Use the cluster
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

Your k3s cluster is ready!

### Updating the Cluster

**Rebuild nodes** (e.g., after config changes):

```bash
# 1. Rebuild template on Proxmox (if base config changed)
ssh root@192.168.178.2
cd setup && git pull
./scripts/build-k3s-image.sh

# 2. Recreate VMs with Pulumi
cd pulumi/proxmox
pulumi destroy --target 'urn:pulumi:default::proxmox::proxmoxve:vm/virtualMachine:VirtualMachine::k3s-k3s-node2'
pulumi up
```

**Update template only** (preserves existing VMs):

```bash
ssh root@192.168.178.2
cd setup && git pull
./scripts/build-k3s-image.sh
# Existing VMs continue running, new clones use updated template
```

### Alternative: Manual Installation

If you prefer not to use the template approach:

For each node (201, 202, 203), follow these steps:

**Start the VM and open console:**
```bash
# In Proxmox web UI, select the VM and click "Start"
# Then click "Console" to access the terminal
```

**Or via CLI:**
```bash
qm start 201  # Start k3s-node1
qm console 201
```

**In the NixOS installer:**

```bash
# 1. Partition the disk
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart primary 512MiB 100%

# 2. Format partitions
sudo mkfs.fat -F 32 -n boot /dev/sda1
sudo mkfs.ext4 -L nixos /dev/sda2

# 3. Mount filesystems
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot

# 4. Clone your configuration
sudo nixos-generate-config --root /mnt

# 5. Replace with your actual configuration
# Option A: If you have network access, fetch from Git
sudo nix-shell -p git
cd /mnt/etc/nixos
sudo git clone https://github.com/YOUR_USERNAME/setup.git tmp
sudo cp tmp/hosts/nixos/k3s-node1/* .  # Adjust node number
sudo rm -rf tmp

# Option B: Manually copy the configuration files
# Copy the contents of hosts/nixos/k3s-node1/configuration.nix
# and modules/nixos/k3s-base.nix to /mnt/etc/nixos/

# 6. Update the configuration
# IMPORTANT: Update these values in configuration.nix:
# - networking.hostName (k3s-node1, k3s-node2, or k3s-node3)
# - networking.hostId (generate unique: head -c 8 /dev/urandom | od -A n -t x8 | tr -d ' \n')
# - services.k3s.token (use a strong shared secret)
# - services.k3s.clusterInit (only true for node1, false for others)
# - SSH authorized keys (add your public key)

# 7. Install NixOS
sudo nixos-install

# 8. Set root password when prompted

# 9. Reboot
sudo reboot
```

**After reboot:**
- The VM should boot from disk (not the ISO)
- If it boots to ISO again, change boot order in Proxmox:
  ```bash
  qm set 201 --boot order=scsi0
  ```

#### 3. Verify K3S Installation

After all nodes are installed and running:

```bash
# SSH to the first node (k3s-node1)
ssh max@k3s-node1  # or use IP address

# Check K3S status
sudo systemctl status k3s

# Get kubeconfig
sudo cat /etc/rancher/k3s/k3s.yaml

# Verify cluster
sudo kubectl get nodes
```

Expected output:
```
NAME        STATUS   ROLES                       AGE   VERSION
k3s-node1   Ready    control-plane,etcd,master   5m    v1.28.x+k3s1
k3s-node2   Ready    control-plane,etcd,master   3m    v1.28.x+k3s1
k3s-node3   Ready    control-plane,etcd,master   2m    v1.28.x+k3s1
```

#### 4. Configure kubectl on Your Local Machine

```bash
# Copy the kubeconfig from k3s-node1
ssh max@k3s-node1 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/k3s-config

# Update the server address in the config
sed -i 's/127.0.0.1/k3s-node1/g' ~/.kube/k3s-config

# Set KUBECONFIG environment variable
export KUBECONFIG=~/.kube/k3s-config

# Verify
kubectl get nodes
```

### Customizing K3S Nodes

You can customize the VM specifications by editing `vms/k3s.ts`:

```typescript
export const k3sNodeConfigs: K3sNodeConfig[] = [
    {
        vmId: 201,
        vmName: "k3s-node1",
        cpuCores: 6,      // Increase CPU
        memoryMB: 16384,  // Increase RAM to 16GB
        diskSizeGB: 64,   // Increase disk space
        role: "server",
    },
    // ... other nodes
];
```

### Managing the Cluster

**Add a worker node:**

1. Add configuration to `vms/k3s.ts`
2. Run `pulumi up`
3. Install NixOS with `role: "agent"` in the configuration
4. Point to the first node using `serverAddr` in k3s configuration

**Remove a node:**

```bash
# Drain the node
kubectl drain k3s-node3 --ignore-daemonsets --delete-emptydir-data

# Remove from cluster
kubectl delete node k3s-node3

# Destroy the VM
pulumi destroy --target urn:pulumi:default::proxmox::proxmoxve:vm/virtualMachine:VirtualMachine::k3s-k3s-node3
```

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