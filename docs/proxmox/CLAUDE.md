# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## System Overview

This is a declarative NixOS flake configuration for running **Proxmox VE with advanced ZFS storage** in a homelab environment. The configuration includes:

- **Main Host (maxdata)**: Proxmox VE hypervisor with ZFS storage pools
- **Raspberry Pi (pi-network)**: Network services (DHCP/DNS) + K3S worker node (ARM64)
- **K3S Cluster**: 4-node Kubernetes (1 control plane + 2 x86 workers + 1 ARM worker on Pi)
- **Advanced ZFS**: Multi-tiered storage with special device, SLOG, and L2ARC caching

**Important**: This uses [SaumonNet/proxmox-nixos](https://github.com/SaumonNet/proxmox-nixos), an experimental community project to run Proxmox VE on NixOS. It is not officially supported.

### Network Architecture

The Raspberry Pi serves as the network anchor (boots first, always available):

```
Power On → Pi boots → DHCP/DNS available → Proxmox woken via WoL → K3S cluster ready
```

- **Pi (PoE+ powered)**: dnsmasq (DHCP) + DNS forwarding + WoL service + K3S agent
- **Proxmox Host**: VMs, ZFS storage, K3S control plane
- **AdGuard Home**: Runs in K3S on Pi (ad-blocking DNS)

## Repository Structure

```
.
├── flake.nix                    # Main flake definition for all systems
├── hosts/
│   ├── maxdata/                 # Main Proxmox host
│   │   ├── configuration.nix    # System configuration
│   │   └── hardware-configuration.nix
│   ├── pi/                      # Raspberry Pi (network services + K3S)
│   │   ├── configuration.nix    # Pi configuration (dnsmasq, WoL, K3S)
│   │   └── hardware-configuration.nix
│   ├── k3s-node1/               # K3S control plane (VM)
│   ├── k3s-node2/               # K3S worker node (VM)
│   └── k3s-node3/               # K3S worker node (VM)
├── modules/
│   ├── networking.nix           # Network bridge, firewall, DHCP
│   ├── zfs.nix                  # ZFS pools, snapshots, Sanoid/Syncoid
│   ├── proxmox.nix              # Proxmox-specific configuration
│   └── k3s-base.nix             # Base K3S configuration
├── home/
│   └── max.nix                  # Home-manager user configuration
├── scripts/
│   ├── rebuild.sh               # System rebuild helper script
│   └── zfs-health.sh            # ZFS health monitoring script
├── pulumi/                      # Infrastructure as Code
│   ├── vms/                     # Proxmox VM definitions (TypeScript/Python)
│   └── k8s/                     # Kubernetes resources
└── [documentation files]
```

## Essential Commands

### System Rebuilds

```bash
# Rebuild and activate system (most common)
sudo nixos-rebuild switch --flake /etc/nixos#maxdata

# Test changes without persistence
sudo nixos-rebuild test --flake /etc/nixos#maxdata

# Build only (no activation)
sudo nixos-rebuild build --flake /etc/nixos#maxdata

# Update flake inputs (nixpkgs, proxmox-nixos, etc.)
nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#maxdata

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Using the helper script
sudo /etc/nixos/scripts/rebuild.sh switch
sudo /etc/nixos/scripts/rebuild.sh update
sudo /etc/nixos/scripts/rebuild.sh rollback
```

### ZFS Management

```bash
# Check pool health (critical daily check)
zpool status -v

# List all datasets and snapshots
zfs list -t all

# Monitor I/O in real-time
zpool iostat -v 2

# Check special device usage (must stay under 80%)
zpool list -v tank | grep special -A1

# Manual scrub
sudo zpool scrub tank

# Check compression ratio
zfs get compressratio tank

# Run ZFS health check script
sudo /etc/nixos/scripts/zfs-health.sh
```

### Proxmox Commands

```bash
# List VMs
qm list

# Start/stop VM
qm start <vmid>
qm stop <vmid>
qm shutdown <vmid>  # Graceful shutdown

# VM configuration
qm config <vmid>

# Backup VM
vzdump <vmid> --storage tank --mode snapshot

# Restore VM
qmrestore /path/to/backup.vma.zst <vmid>

# Access Proxmox UI
# https://<server-ip>:8006
# Username: root@pam
```

### K3S/Kubernetes Commands

```bash
# SSH to control plane
ssh max@k3s-node1

# Get cluster status
kubectl get nodes
kubectl get pods -A

# Interactive cluster management
k9s

# Get kubeconfig (run on k3s-node1)
sudo cat /etc/rancher/k3s/k3s.yaml
```

### Raspberry Pi Commands

```bash
# SSH to Pi
ssh max@192.168.178.10

# Rebuild Pi configuration
sudo nixos-rebuild switch --flake /etc/nixos#pi-network

# Check dnsmasq (DHCP/DNS)
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -f

# Check DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Test DNS forwarding
dig @127.0.0.1 google.com        # Via dnsmasq
dig @127.0.0.1 -p 5353 google.com  # Direct to AdGuard

# Check WoL service
sudo systemctl status wake-proxmox
sudo journalctl -u wake-proxmox

# Wake Proxmox manually
wol dc:a6:32:XX:XX:XX
```

### Pulumi Commands (VM & K8s Management)

```bash
# Navigate to Pulumi projects
cd /etc/nixos/pulumi/vms    # For VM management
cd /etc/nixos/pulumi/k8s    # For K8s resources

# Preview changes
pulumi preview

# Apply changes
pulumi up

# Destroy resources
pulumi destroy

# View current stack state
pulumi stack

# Export stack outputs
pulumi stack output

# Check resource status
pulumi refresh
```

## Storage Architecture

This system uses a sophisticated multi-tiered ZFS storage setup:

### Tank Pool (Main Storage)
- **Base**: 4× 4TB HDDs in RAIDZ1 (~12TB usable)
- **Special Device**: 400GB mirrored (metadata + files <32K) - MUST stay under 80%
- **SLOG**: 100GB mirrored (synchronous write cache) - critical for NFS/databases
- **L2ARC**: 1TB total (500GB per SSD, not mirrored) - read cache

### Fast Pool (Performance Storage)
- **Base**: 1TB NVMe for system root, /nix, and high-performance VMs
- **Replication**: Automated snapshots to tank pool via Syncoid

### Critical Understanding
1. **Special Device & SLOG are MIRRORED**: Failure of either device = data loss/corruption
2. **L2ARC is NOT mirrored**: Failure only affects cache performance, no data loss
3. **Special device usage**: MUST monitor and keep under 80% to avoid performance degradation
4. **SLOG**: Only helps with synchronous writes (NFS, databases, VMs with sync=always)

## Network Services Architecture (DNS/DHCP)

The Raspberry Pi serves as the network anchor, providing critical services that bootstrap the rest of the infrastructure.

### Component Roles

**Raspberry Pi (pi-network) - NixOS:**
- **dnsmasq (systemd service)**:
  - DHCP server on port 67 (assigns IPs to all devices)
  - DNS server on port 53 (receives client DNS queries)
  - Forwards DNS to AdGuard on localhost:5353
  - Local domain resolution (`.local`)
  - Static DHCP leases for infrastructure

- **AdGuard Home (K8S pod, hostPort)**:
  - DNS filtering and ad-blocking
  - Runs on port 5353 (via hostPort)
  - Receives forwarded queries from dnsmasq
  - Queries upstream DNS (1.1.1.1, 8.8.8.8)

- **Wake-on-LAN service**:
  - Automatically wakes Proxmox after Pi boots
  - Monitors Proxmox health

- **K3S agent**:
  - Joins K3S cluster as ARM64 worker node
  - Hosts AdGuard pod

### DNS Query Flow

```
Client device (e.g., phone at 192.168.178.150)
  ↓ DHCP request
Pi:67 (dnsmasq DHCP) → assigns IP + DNS=192.168.178.10

Client device
  ↓ DNS query: "what is google.com?"
  ↓ To: 192.168.178.10:53

Pi:53 (dnsmasq DNS)
  ↓ Forwards to 127.0.0.1:5353 (internal, localhost)

Pi:5353 (AdGuard pod via hostPort)
  ↓ Filters ads, checks blocklists
  ↓ Queries upstream: 1.1.1.1

Internet DNS
  ↓ Response: google.com = 142.250.X.X

AdGuard → dnsmasq → Client device
```

### Key Design Decisions

1. **Why dnsmasq on Pi bare metal?**
   - DHCP doesn't depend on K8S being up
   - Network bootstraps before VMs start
   - Lightweight and reliable

2. **Why AdGuard in K8S?**
   - Declarative management via Pulumi
   - Easy backups and updates
   - Benefits from K8S monitoring/logging
   - Can be managed alongside other cluster resources

3. **Why hostPort instead of NodePort?**
   - AdGuard runs on same machine as dnsmasq
   - Localhost forwarding (127.0.0.1:5353) is most efficient
   - No network stack overhead
   - AdGuard pinned to Pi (intentional design)

4. **Why Pi boots first?**
   - PoE+ powered (always available)
   - Provides DHCP/DNS immediately
   - Wakes Proxmox via WoL
   - Network works even if Proxmox is off

### Static DHCP Leases

Infrastructure nodes have static leases in dnsmasq:

```
Proxmox:   192.168.178.97  (maxdata.local)
Pi:        192.168.178.10  (pi-network.local)
k3s-node1: 192.168.178.101 (k3s-node1.local)
k3s-node2: 192.168.178.102 (k3s-node2.local)
k3s-node3: 192.168.178.103 (k3s-node3.local)
```

Dynamic devices get IPs from range: `192.168.178.50-200`

## VM Management with Pulumi

VMs are managed **declaratively via Pulumi**, not in NixOS configuration. This provides:
- Infrastructure as Code for VM definitions
- Version control for VM configurations
- Consistent workflow with K8s management
- Proxmox UI still available for monitoring/console access

### VM Workflow

**Three-layer architecture:**

1. **NixOS (Infrastructure)**: Manages Proxmox, ZFS, networking, system services
2. **Pulumi (VMs & K8s)**: Declaratively defines VMs and Kubernetes resources
3. **Proxmox UI (Monitoring)**: View status, access console, monitor resources

**Standard workflow:**
```bash
# 1. Infrastructure changes (ZFS, networking, etc.)
sudo nixos-rebuild switch --flake /etc/nixos#maxdata

# 2. VM changes
cd /etc/nixos/pulumi/vms
pulumi up

# 3. K8s changes
cd /etc/nixos/pulumi/k8s
pulumi up

# 4. Monitor via Proxmox UI
# https://192.168.178.97:8006
```

### Example Pulumi VM Definition

```typescript
// pulumi/vms/index.ts
import * as proxmox from "@muhlba91/pulumi-proxmoxve";

const windows11 = new proxmox.vm.VirtualMachine("windows11", {
    vmId: 100,
    nodeName: "maxdata",
    name: "windows11",

    cpu: { cores: 4, type: "host" },
    memory: { dedicated: 8192 },

    disks: [{
        interface: "scsi0",
        size: 100,
        storage: "tank",      // Use ZFS pool
        fileFormat: "raw",
    }],

    networkDevices: [{
        bridge: "vmbr0",      // Bridge from networking.nix
        model: "virtio",
    }],

    bios: "ovmf",             // UEFI
    tpmState: { storage: "tank" },  // TPM for Windows 11

    started: true,
    onBoot: true,
});
```

### Pulumi Setup

**Provider configuration** (`pulumi/vms/Pulumi.yaml`):
```yaml
name: proxmox-vms
runtime: nodejs
description: Proxmox VM definitions

config:
  proxmox:endpoint:
    value: https://192.168.178.97:8006
  proxmox:insecure:
    value: true
  proxmox:username:
    value: root@pam
```

**Set credentials:**
```bash
cd /etc/nixos/pulumi/vms
pulumi config set proxmox:apiToken <token> --secret
# Or use password (less secure)
pulumi config set proxmox:password <password> --secret
```

### Creating Proxmox API Token

For secure Pulumi access:
```bash
# Via Proxmox UI: Datacenter → Permissions → API Tokens
# Or via CLI:
pveum user token add root@pam pulumi -privsep 0
# Save the token for Pulumi
```

### Important Notes on VM Management

- **VM definitions are NOT in flake.nix**: They live in `pulumi/vms/`
- **VMs persist in Proxmox**: Pulumi manages state, Proxmox stores VMs
- **Use Proxmox CLI for one-off tasks**: `qm start`, `qm stop`, etc.
- **Use Pulumi for declarative changes**: Adding VMs, changing specs, etc.
- **State is tracked by Pulumi**: Changes outside Pulumi (UI/CLI) will cause drift

## Configuration Patterns

### Adding a New Dataset to ZFS Pool

ZFS datasets are managed declaratively but pools are created manually during installation. To add snapshots/replication for new datasets:

Edit `modules/zfs.nix`:
```nix
services.sanoid.datasets = {
  "tank/new-dataset" = {
    useTemplate = [ "production" ];
    recursive = true;
  };
};
```

Then rebuild: `sudo nixos-rebuild switch --flake /etc/nixos#maxdata`

### Modifying Network Configuration

Edit `modules/networking.nix` for:
- Bridge interface (vmbr0) settings
- Firewall rules
- Static IP vs DHCP
- IPv6 configuration

**Important**: Network changes may require a reboot or manual `systemctl restart systemd-networkd`

### Adding System Packages

For system-wide packages, edit `hosts/maxdata/configuration.nix`:
```nix
environment.systemPackages = with pkgs; [
  # Add packages here
];
```

For user-specific packages, edit `home/max.nix` (home-manager configuration)

### Adjusting ZFS Tuning Parameters

Edit `modules/zfs.nix` for:
- ARC size limits (currently 16GB max, 4GB min for 32GB RAM)
- L2ARC write performance
- Compression settings
- Snapshot retention policies

**Warning**: Incorrect ZFS tuning can cause severe performance issues or system instability.

## Critical Configuration Values

### Before Installation (MUST CHANGE)

1. **hostId** (in `hosts/maxdata/configuration.nix`):
   - Generate: `head -c 8 /dev/urandom | od -A n -t x8 | tr -d ' '`
   - Must be unique per ZFS host

2. **SSH Keys** (in all configuration.nix files):
   - Replace placeholder SSH keys with actual authorized keys
   - Located in `users.users.max.openssh.authorizedKeys.keys`

3. **K3S Token** (in all `hosts/k3s-node*/configuration.nix`):
   - Generate: `openssl rand -base64 32`
   - Must be identical across all K3S nodes

4. **Disk IDs** (during installation):
   - Always use `/dev/disk/by-id/` paths (not `/dev/sdX`)
   - Get IDs with: `ls -l /dev/disk/by-id/`

## Automated Maintenance

The system includes automated maintenance tasks:

- **Sanoid**: Hourly, daily, monthly snapshots (configured per-dataset)
- **Syncoid**: Fast pool → Tank replication
- **Auto-scrub**: Monthly on all pools
- **Auto-trim**: Weekly for SSD health
- **Garbage Collection**: Weekly Nix store cleanup (keeps 30 days)

These are all defined in `modules/zfs.nix` and run via systemd timers.

## Troubleshooting

### System Won't Boot

Boot from NixOS ISO and import pools manually:
```bash
sudo zpool import -f tank
sudo zpool import -f fast
sudo mount -t zfs fast/root /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter
sudo nixos-rebuild switch --rollback
```

### Proxmox Service Issues

```bash
# Check service status
sudo systemctl status proxmox-ve

# View logs
sudo journalctl -u proxmox-ve -f

# Restart service
sudo systemctl restart proxmox-ve
```

### ZFS Pool Degraded

```bash
# Check pool status
sudo zpool status -v

# Clear errors after fixing issue
sudo zpool clear tank

# Replace failed disk
sudo zpool replace tank /dev/old-disk /dev/new-disk
```

### Special Device Full (>80%)

This is CRITICAL. Options:
1. Delete unnecessary datasets/snapshots
2. Prune old snapshots: `sudo sanoid --prune-snapshots`
3. Move large files to regular storage (files >32K don't use special device)

Do NOT let special device reach 100% - can cause severe performance degradation.

## Development Workflow

### Infrastructure Changes (NixOS)

1. **Make changes** to configuration files (e.g., `modules/zfs.nix`)
2. **Test changes** first: `sudo nixos-rebuild test --flake /etc/nixos#maxdata`
3. **If working**, make persistent: `sudo nixos-rebuild switch --flake /etc/nixos#maxdata`
4. **If broken**, rollback: `sudo nixos-rebuild switch --rollback`

NixOS's declarative nature means you can always rollback to a previous working state.

### VM/K8s Changes (Pulumi)

1. **Make changes** to Pulumi code (e.g., `pulumi/vms/index.ts`)
2. **Preview changes**: `pulumi preview` (shows what will be created/updated/deleted)
3. **Apply changes**: `pulumi up` (prompts for confirmation)
4. **If broken**, rollback: `pulumi stack history` → `pulumi stack select` previous version

### Combined Workflow Example

**Scenario**: Add a new ZFS dataset for VM storage and create a VM on it

```bash
# 1. Add dataset to NixOS config
# Edit modules/zfs.nix to add "tank/vms/databases" dataset

# 2. Apply infrastructure change
sudo nixos-rebuild switch --flake /etc/nixos#maxdata

# 3. Create the dataset manually (ZFS datasets must be created, not just declared)
sudo zfs create tank/vms
sudo zfs create tank/vms/databases

# 4. Define VM in Pulumi using new storage
cd /etc/nixos/pulumi/vms
# Edit index.ts to add VM with storage: "tank/vms/databases"

# 5. Preview and apply VM changes
pulumi preview
pulumi up

# 6. Monitor via Proxmox UI
# Visit https://192.168.178.97:8006
```

## Important Notes

- **RAID is NOT a backup**: Always maintain off-site backups (Hetzner Storage Box configured with rclone)
- **Test restores regularly**: Backups are useless if you can't restore
- **Monitor special device**: Check usage weekly with `zpool list -v tank`
- **Proxmox is experimental on NixOS**: Not all features may work; updates may break things
- **No interactive commands**: Never use `git rebase -i` or `git add -i` - they won't work in this environment
- **VM management via Pulumi**: Don't manually create VMs in Proxmox UI if using Pulumi (causes state drift)
- **Pulumi state is critical**: Store Pulumi state securely (consider Pulumi Cloud or S3 backend)

## Architecture Layers

This system uses a clear separation of concerns:

| Layer | Tool | Manages | Declarative | Version Controlled |
|-------|------|---------|-------------|-------------------|
| **Infrastructure** | NixOS | Proxmox, ZFS, networking, services | ✅ Yes | ✅ Yes (flake.nix) |
| **VMs** | Pulumi | VM definitions, specs, storage | ✅ Yes | ✅ Yes (pulumi/vms/) |
| **K8s Resources** | Pulumi | Deployments, services, ingress | ✅ Yes | ✅ Yes (pulumi/k8s/) |
| **Monitoring** | Proxmox UI | VM status, console, metrics | ❌ No | ❌ No |

**Key principle**: NixOS provides the platform, Pulumi manages the workloads, Proxmox UI provides visibility.

## Documentation Files

- **README.md**: Complete project overview and features
- **MIGRATION.md**: Step-by-step installation guide from scratch
- **QUICK_REFERENCE.md**: Daily command reference
- **OVERVIEW.md**: Architecture and design decisions
- **START_HERE.md**: Navigation guide for new users
- **CHECKLIST.md**: Installation progress tracking

## Access Points

After installation:
- **Proxmox UI**: https://<server-ip>:8006 (username: root@pam)
- **Cockpit**: http://<server-ip>:9090 (system management)
- **SSH**: ssh max@<server-ip> (key-based only, root login disabled)
- **Prometheus**: http://<server-ip>:9090 (metrics, if monitoring enabled)
- **Grafana**: http://<server-ip>:3000 (dashboards, if monitoring enabled)
- **Loki**: http://<server-ip>:3100 (logs, if monitoring enabled)

## Pulumi Integration

### Pulumi Providers Used

- **@muhlba91/pulumi-proxmoxve**: Proxmox provider for VM management
- **@pulumi/kubernetes**: Kubernetes resources (if managing K8s via Pulumi)

### Pulumi State Management

By default, Pulumi stores state locally in `~/.pulumi/`. For production:

**Option 1: Pulumi Cloud (Recommended)**
```bash
pulumi login
# State stored in Pulumi Cloud (free tier available)
```

**Option 2: S3 Backend**
```bash
pulumi login s3://<bucket-name>
# State stored in S3
```

**Option 3: Self-hosted Backend**
```bash
pulumi login file://~/.pulumi-state
# Store state in git or network drive
```

### Importing Existing VMs

If you have existing VMs in Proxmox and want to manage them with Pulumi:

```bash
cd /etc/nixos/pulumi/vms

# Import existing VM (get VM ID from Proxmox)
pulumi import proxmox:vm/VirtualMachine:VirtualMachine windows11 maxdata/qemu/100

# This adds the VM to Pulumi state without recreating it
```

### Multi-Stack Setup

You can manage different environments with Pulumi stacks:

```bash
# Create stacks for different purposes
pulumi stack init prod      # Production VMs
pulumi stack init dev       # Development VMs
pulumi stack init staging   # Staging VMs

# Switch between stacks
pulumi stack select prod
pulumi up

pulumi stack select dev
pulumi up
```

## Common Patterns

### Pattern: VM with Dedicated ZFS Dataset

```typescript
// 1. Create ZFS dataset (via NixOS or manually)
// sudo zfs create tank/vms/my-app

// 2. Define VM in Pulumi
const myAppVm = new proxmox.vm.VirtualMachine("my-app", {
    vmId: 101,
    nodeName: "maxdata",
    name: "my-app-vm",

    disks: [{
        interface: "scsi0",
        size: 50,
        storage: "tank",  // Maps to tank/vms/my-app
        fileFormat: "raw",
    }],

    // Ensure snapshots via Sanoid
    // Add "tank/vms/my-app" to modules/zfs.nix
});
```

### Pattern: VM Template for Similar VMs

```typescript
// Helper function for standard VM configuration
function createStandardVm(name: string, vmId: number, cores: number = 2) {
    return new proxmox.vm.VirtualMachine(name, {
        vmId,
        nodeName: "maxdata",
        name,

        cpu: { cores, type: "host" },
        memory: { dedicated: 4096 },

        disks: [{
            interface: "scsi0",
            size: 32,
            storage: "fast",  // All on fast NVMe
            fileFormat: "raw",
        }],

        networkDevices: [{
            bridge: "vmbr0",
            model: "virtio",
        }],

        started: true,
        onBoot: true,
    });
}

// Create multiple similar VMs
const web1 = createStandardVm("web-1", 110, 4);
const web2 = createStandardVm("web-2", 111, 4);
const db = createStandardVm("db", 120, 8);
```
