# Migrate Maxdata to NixOS with Proxmox

## Prepare

- [x] **Backup to Hetzner completed and verified**
    - [x] All important data backed up
    - [x] Backup integrity checked
    - [x] Test restoration of critical files

- [ ] **Installation media prepared**
    - [x] Downloaded NixOS ISO (latest unstable)
      ```shell
      wget https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso 
      ```
    - [x] Created bootable USB drive
      ```shell
      sudo dd if=latest-nixos-minimal-x86_64-linux.iso of=/dev/rdisk5 bs=1M status=progress  
      ```
      
---

## Phase 1: Boot and Prepare (30 minutes)

- [x] **Boot NixOS Live Environment**
    - [x] Inserted USB and booted from it
    - [x] Selected "NixOS Installer" from menu
    - 
- [x] **Network connectivity**
    - [x] Tested: `ping -c 3 1.1.1.1`
    - [x] Tested: `ping -c 3 google.com`
    - [x] Noted IP address: 192.168.178.97

- [x] **Remote access** (optional but recommended)
    - [x] Set password: `sudo passwd nixos`
    - [x] Started SSH: `sudo systemctl start sshd`
    - [x] Connected from workstation:
      ```shell
      ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no nixos@192.168.178.97
      ```
      
- [x] **Identified disk IDs**
    - [x] Ran: `ls -l /dev/disk/by-id/`
    - [x] Noted Disks:
      ```shell
      sudo loadkeys de
      HDD1="/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0LE673J"
      HDD2="/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P"
      HDD3="/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3ZX6HZU"
      HDD4="/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K6XXCSYZ"
      NVME="/dev/disk/by-id/nvme-CT1000P3SSD8_2237E665D487"
      SSD1="/dev/disk/by-id/ata-CT1000BX500SSD1_2216E6299C92"
      SSD2="/dev/disk/by-id/ata-Samsung_SSD_870_EVO_1TB_S75CNX0Y903459M"
      ```
      
---

## Phase 2: Partition Disks (30 minutes)

- [x] **Clear Disks**
    ```shell
    sudo wipefs --all $HDD1
    sudo wipefs --all $HDD2
    sudo wipefs --all $HDD3
    sudo wipefs --all $HDD4
    sudo wipefs --all $SSD1
    sudo wipefs --all $SSD2
    sudo wipefs --all $NVME
    ```

- [x] **Partition SSDs**
    ```shell
    # Partition SSD1
    sudo gdisk $SSD1

    # In gdisk:
    o         # Create new GPT partition table
    y         # Confirm

    n         # New partition 1
    (enter)   # Default partition number (1)
    (enter)   # Default start sector
    +400G     # Size: 400GB
    8300      # Linux filesystem

    n         # New partition 2
    (enter)   # Default partition number (2)
    (enter)   # Default start sector
    +100G     # Size: 100GB
    8300      # Linux filesystem

    n         # New partition 3
    (enter)   # Default partition number (3)
    (enter)   # Default start sector
    (enter)   # Default end sector (use remaining space)
    8300      # Linux filesystem

    p         # Print partition table to verify
    w         # Write changes
    y         # Confirm
    ```

- [x] **Partition NVMe**
    ```shell
    sudo gdisk $NVME

    o         # Create new GPT partition table
    y         # Confirm

    n         # New partition 1 - EFI boot
    (enter)   # Partition number (1)
    (enter)   # Default start
    +1G       # 1GB for EFI
    ef00      # EFI System

    n         # New partition 2 - Fast pool
    (enter)   # Partition number (2)
    (enter)   # Default start
    (enter)   # Use remaining space
    8300      # Linux filesystem

    p         # Verify
    w         # Write
    y         # Confirm
    ```

- [x] **Formatted boot partition**
    - [x] Ran: `sudo mkfs.vfat -F 32 -n BOOT ${NVME}-part1`

---

## Phase 3: Create ZFS Pools (45 minutes)

- [x] **Created tank pool (RAIDZ1)**
    ```shell
    # Create main tank pool with RAIDZ1
    sudo zpool create -f \
      -o ashift=12 \
      -o autotrim=on \
      -O compression=lz4 \
      -O atime=off \
      -O xattr=sa \
      -O acltype=posixacl \
      -O mountpoint=none \
      tank raidz1 \
      $HDD1 \
      $HDD2 \
      $HDD3 \
      $HDD4

    # Add mirrored special device (400GB partitions)
    sudo zpool add tank special mirror \
      ${SSD1}-part1 \
      ${SSD2}-part1

    # Add mirrored SLOG/write cache (100GB partitions)
    sudo zpool add tank log mirror \
      ${SSD1}-part2 \
      ${SSD2}-part2

    # Add L2ARC/read cache (500GB partitions - NOT mirrored)
    sudo zpool add tank cache \
      ${SSD1}-part3 \
      ${SSD2}-part3

    # Verify pool structure
    sudo zpool status -v tank
    ```

- [ ] **Created fast pool (NVMe)**
    ```shell
    sudo zpool create -f \
      -o ashift=12 \
      -o autotrim=on \
      -O compression=lz4 \
      -O atime=off \
      -O xattr=sa \
      -O acltype=posixacl \
      -O mountpoint=none \
      fast ${NVME}-part2
    ```

- [ ] **Created tank datasets**
    ```shell
    # Main datasets - use legacy mounting for NixOS to manage
    sudo zfs create -o mountpoint=legacy tank/data
    sudo zfs create -o mountpoint=legacy tank/backups
    sudo zfs create -o mountpoint=legacy tank/pve
    sudo zfs create -o mountpoint=legacy tank/k8s
    sudo zfs create -o mountpoint=legacy tank/fast-backup

    # Sub-datasets for VMs (optimized)
    sudo zfs create -o recordsize=16K tank/pve/vms

    # Enable special_small_blocks for better performance with special device
    sudo zfs set special_small_blocks=32K tank/pve/vms
    sudo zfs set special_small_blocks=32K tank/data
    ```

- [ ] **Created fast datasets**
    ```shell
    sudo zfs create -o mountpoint=legacy fast/root       # System root
    sudo zfs create -o mountpoint=legacy fast/nix        # /nix store
    sudo zfs create -o mountpoint=legacy fast/pve        # Proxmox on fast storage

    # Sub-datasets for VMs (optimized)
    sudo zfs create -o recordsize=16K fast/pve/vms
    ```

- [ ] **Verified pool structure**
    - [ ] Ran: `zpool list -v`
    - [ ] Confirmed special device, SLOG, and L2ARC present
    - [ ] No errors shown

---

## Phase 4: Mount and Install (60 minutes)

- [ ] **Mounted filesystems**
    ```shell
    # Mount root
    sudo mount -t zfs fast/root /mnt

    # Create directories
    sudo mkdir -p /mnt/{boot,nix,fast/pve,tank}

    # Mount boot
    sudo mount ${NVME}-part1 /mnt/boot

    # Mount nix
    sudo mount -t zfs fast/nix /mnt/nix

    # Mount fast/pve
    sudo mount -t zfs fast/pve /mnt/fast/pve

    # Mount tank datasets
    sudo mkdir -p /mnt/tank/{data,backups,pve,k8s,fast-backup}
    sudo mount -t zfs tank/data /mnt/tank/data
    sudo mount -t zfs tank/backups /mnt/tank/backups
    sudo mount -t zfs tank/pve /mnt/tank/pve
    sudo mount -t zfs tank/k8s /mnt/tank/k8s
    sudo mount -t zfs tank/fast-backup /mnt/tank/fast-backup

    # Verify mounts
    mount | grep /mnt
    ```

- [ ] **Copied configuration**
    - [ ] Created: `/mnt/etc/nixos`
    - [ ] Copied all flake files to `/mnt/etc/nixos/`
    - [ ] Verified flake.nix is present

- [ ] **Updated configuration**
    - [ ] Verified hostId is correct and unique
    - [ ] Verified SSH keys are added
    - [ ] Verified timezone is correct
    - [ ] Updated any network settings if needed

- [ ] **Installed NixOS**
    - [ ] Ran: `sudo nixos-install --flake /mnt/etc/nixos#maxdata`
    - [ ] Set root password when prompted
    - [ ] Installation completed without errors
    - [ ] Noted any warnings or messages

- [ ] **First boot**
    - [ ] Rebooted: `sudo reboot`
    - [ ] Removed USB drive
    - [ ] System booted successfully
    - [ ] Can login as max via SSH

---

### Access Proxmox Web UI

```bash
# Open in browser:
https://192.168.178.2:8006

# Username: root@pam
# Password: (root password you set during installation)
```

### Configure ZFS Storage in Proxmox

1. In Proxmox web UI, go to: **Datacenter → Storage → Add → ZFS**

2. Add "tank" storage:
- **ID**: tank
- **ZFS Pool**: tank/pve/vms
- **Content**: Disk image, Container
- **Nodes**: maxdata

3. Add "fast" storage:
- **ID**: fast
- **ZFS Pool**: fast/pve/vms
- **Content**: Disk image, Container
- **Nodes**: maxdata

---
