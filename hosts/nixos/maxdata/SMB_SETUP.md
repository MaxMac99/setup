# SMB/Samba Setup for maxdata

This guide covers setting up SMB shares with Time Machine support and multi-user access on your NixOS server.

## Overview

The SMB configuration provides:
- Time Machine backup support for Max and Michael
- Personal data shares for Max, Michael, and Anna
- Family shared data accessible to all family members
- Service discovery via Avahi (automatic discovery on macOS/Windows)
- Performance-optimized settings for NAS usage

## Users

The following users are configured:
- **max** - Primary user with full access
- **michael** - Family member with own Time Machine and personal data
- **anna** - Family member with own personal data

## Quick Start

After deploying the NixOS configuration:

```bash
# 1. Rebuild your system
sudo nixos-rebuild switch

# 2. Create ZFS datasets
sudo bash /etc/nixos/hosts/nixos/maxdata/setup-smb-datasets.sh

# 3. Set SMB passwords for all users
sudo smbpasswd -a max && sudo smbpasswd -e max
sudo smbpasswd -a michael && sudo smbpasswd -e michael
sudo smbpasswd -a anna && sudo smbpasswd -e anna

# 4. Verify Samba is running
sudo systemctl status smbd
```

## Share Overview

### Time Machine Shares

| Share | Path | User | Quota | Purpose |
|-------|------|------|-------|---------|
| timemachine-max | /tank/timemachine-max | max | 800GB | Time Machine backups for Max |
| timemachine-michael | /tank/timemachine-michael | michael | 600GB | Time Machine backups for Michael |

### Personal Data Shares

| Share | Path | User | Purpose |
|-------|------|------|---------|
| Daten Max | /tank/daten-max | max | Personal files for Max |
| Daten Michael | /tank/daten-michael | michael | Personal files for Michael |
| Daten Anna | /tank/daten-anna | anna | Personal files for Anna |

### Family Shared Data

| Share | Path | Users | Purpose |
|-------|------|-------|---------|
| Daten Familie | /tank/daten-familie | max, michael, anna (all RW) | Shared family files |

## Detailed Setup Steps

### Step 1: Create ZFS Datasets

The setup script creates all necessary datasets with appropriate permissions:

```bash
sudo bash setup-smb-datasets.sh
```

This creates:
- Time Machine datasets with quotas (800GB for Max, 600GB for Michael)
- Personal data datasets for each user
- Family shared dataset
- All datasets use LZ4 compression

### Step 2: Configure SMB Passwords

After system rebuild, set SMB passwords for each user:

```bash
# Set SMB password for max
sudo smbpasswd -a max
sudo smbpasswd -e max

# Set SMB password for michael
sudo smbpasswd -a michael
sudo smbpasswd -e michael

# Set SMB password for anna
sudo smbpasswd -a anna
sudo smbpasswd -e anna
```

**Note:** SMB passwords are separate from Linux user passwords.

### Step 3: Verify Services

Check that all services are running:

```bash
# Check Samba
sudo systemctl status smbd
sudo systemctl status nmbd
sudo systemctl status samba-wsdd

# Check Avahi (for macOS discovery)
sudo systemctl status avahi-daemon

# List available shares
sudo smbclient -L localhost -U max
```

## Connecting from macOS

### Time Machine Setup

1. Open **System Settings** > **General** > **Time Machine**
2. Click **+** to add a backup disk
3. Your server should appear as "maxdata" in the list
4. Select your Time Machine share:
   - Max: "timemachine-max"
   - Michael: "timemachine-michael"
5. Enter your username and SMB password
6. Time Machine will format and begin backing up

### Connecting to Data Shares

#### Via Finder:
1. Open Finder
2. Press **⌘K** (Go > Connect to Server)
3. Enter: `smb://maxdata.local` or `smb://192.168.178.2`
4. Click **Connect**
5. Enter username and SMB password
6. Select which shares to mount

#### Mount at Login:
1. Open **System Settings** > **General** > **Login Items**
2. Click **+** under "Open at Login"
3. Add the mounted network shares

### Troubleshooting macOS Connection

If the server doesn't appear:
```bash
# From macOS terminal, test connection:
smbutil view //maxdata.local

# Or use IP directly:
smbutil view //192.168.178.2

# Check if mDNS is working:
dns-sd -B _smb._tcp

# Check Time Machine discovery:
dns-sd -B _adisk._tcp
```

## Connecting from Windows

1. Open **File Explorer**
2. In address bar: `\\maxdata` or `\\192.168.178.2`
3. Enter credentials when prompted
4. Right-click share > **Map network drive** to make it permanent

## Customization

### Adding a New User

1. Edit `smb.nix` and add to `users.users`:

```nix
newuser = {
  isNormalUser = true;
  description = "New User";
  home = "/home/newuser";
  extraGroups = [ "users" ];
};
```

2. Add shares for the new user following the existing pattern

3. Create ZFS dataset:
```bash
sudo zfs create tank/daten-newuser
sudo zfs set compression=lz4 tank/daten-newuser
sudo chown newuser:users /tank/daten-newuser
sudo chmod 755 /tank/daten-newuser
```

4. Rebuild and set SMB password:
```bash
sudo nixos-rebuild switch
sudo smbpasswd -a newuser
sudo smbpasswd -e newuser
```

### Adding a Time Machine Share for Anna

If Anna also needs Time Machine backups, add to `smb.nix`:

```nix
"timemachine-anna" = {
  path = "/tank/timemachine-anna";
  "valid users" = "anna";
  "read only" = "no";
  "create mask" = "0600";
  "directory mask" = "0700";
  "fruit:time machine" = "yes";
  "fruit:time machine max size" = "500G";
  "vfs objects" = "catia fruit streams_xattr";
  comment = "Time Machine - Anna";
};
```

Update Avahi service:
```nix
<txt-record>dk2=adVN=timemachine-anna,adVF=0x82</txt-record>
```

Create dataset:
```bash
sudo zfs create tank/timemachine-anna
sudo zfs set quota=500G tank/timemachine-anna
sudo zfs set compression=lz4 tank/timemachine-anna
sudo chown anna:users /tank/timemachine-anna
sudo chmod 700 /tank/timemachine-anna
```

### Adjusting Time Machine Quota

To change Time Machine backup size limits:

1. Edit `smb.nix`:
```nix
"fruit:time machine max size" = "1T";  # Change to desired size
```

2. Update ZFS quota:
```bash
sudo zfs set quota=1T tank/timemachine-max
```

3. Rebuild: `sudo nixos-rebuild switch`

### Adding Additional Shares

Example: Create a shared "Photos" directory:

1. Edit `smb.nix`:
```nix
"Fotos" = {
  path = "/tank/fotos";
  browseable = "yes";
  "read only" = "no";
  "valid users" = "max michael anna";
  "create mask" = "0664";
  "directory mask" = "0775";
  "vfs objects" = "catia fruit streams_xattr";
  comment = "Family Photos";
};
```

2. Create dataset:
```bash
sudo zfs create tank/fotos
sudo zfs set compression=lz4 tank/fotos
sudo chown max:users /tank/fotos
sudo chmod 775 /tank/fotos
```

3. Rebuild: `sudo nixos-rebuild switch`

## Security Considerations

1. **Firewall:** Ports are automatically opened by `openFirewall = true`
2. **User Authentication:** All shares require valid credentials (no guest access)
3. **Permissions:**
   - Time Machine shares: 700 (owner only)
   - Personal data: 755 (owner write, others read)
   - Family data: 775 (all users can write)
4. **Network:** Consider using VPN for remote access instead of exposing SMB to the internet

## Monitoring

### Check Connected Users
```bash
sudo smbstatus
```

### View Share Usage
```bash
sudo zfs list -t filesystem | grep tank
```

### Check Dataset Quotas
```bash
sudo zfs get quota,used,available tank/timemachine-max
sudo zfs get quota,used,available tank/timemachine-michael
```

### Check Logs
```bash
sudo journalctl -u smbd -f
sudo journalctl -u nmbd -f
sudo journalctl -u avahi-daemon -f
```

## Backup and Snapshots

### Add Datasets to Sanoid

Edit `zfs.nix` to add snapshot management for SMB shares:

```nix
services.sanoid = {
  datasets = {
    # Time Machine backups - less frequent snapshots
    "tank/timemachine-max" = {
      useTemplate = ["backup"];
      recursive = false;
    };
    "tank/timemachine-michael" = {
      useTemplate = ["backup"];
      recursive = false;
    };

    # Personal and family data - production snapshots
    "tank/daten-max" = {
      useTemplate = ["production"];
      recursive = true;
    };
    "tank/daten-michael" = {
      useTemplate = ["production"];
      recursive = true;
    };
    "tank/daten-anna" = {
      useTemplate = ["production"];
      recursive = true;
    };
    "tank/daten-familie" = {
      useTemplate = ["production"];
      recursive = true;
    };
  };

  templates.backup = {
    frequently = 0;
    hourly = 24;
    daily = 7;
    monthly = 3;
    autosnap = true;
    autoprune = true;
  };
};
```

### Manual Snapshots

Create a manual snapshot:
```bash
sudo zfs snapshot tank/daten-familie@$(date +%Y%m%d-%H%M%S)
```

List snapshots:
```bash
sudo zfs list -t snapshot | grep tank
```

Restore from snapshot:
```bash
sudo zfs rollback tank/daten-familie@snapshot-name
```

## Performance Tuning

The configuration includes optimizations for:
- TCP socket buffer sizes for better network throughput
- macOS compatibility (fruit VFS module)
- ZFS compression (lz4 on all datasets)

### For Large Files

If you store large video files or ISOs:
```bash
sudo zfs set recordsize=1M tank/daten-familie
```

### For Small Files

If you have many small files (documents, code):
```bash
sudo zfs set recordsize=128K tank/daten-max
```

## Troubleshooting

### Shares Don't Appear on macOS

1. Check Avahi is running:
```bash
sudo systemctl status avahi-daemon
```

2. Test mDNS discovery:
```bash
# From macOS:
dns-sd -B _smb._tcp
dns-sd -B _adisk._tcp
```

3. Try direct IP connection instead of hostname

### Permission Denied

1. Verify SMB password is set:
```bash
sudo smbpasswd -a username
sudo smbpasswd -e username
```

2. Check dataset permissions:
```bash
ls -la /tank/
```

3. Verify user in share's "valid users" list

### Time Machine Not Discovered

1. Check Avahi service file includes Time Machine advertisement
2. Restart Avahi: `sudo systemctl restart avahi-daemon`
3. Check macOS console for Time Machine errors
4. Manually add: In Time Machine > Select Disk > choose "Add Other Backup Disk"

### Slow Performance

1. Check network connection (use `iperf3` between machines)
2. Monitor ZFS ARC usage: `arc_summary`
3. Check if compression is enabled: `zfs get compression tank`
4. Consider adjusting ZFS recordsize for your workload

## Additional Resources

- [Samba Documentation](https://www.samba.org/samba/docs/)
- [NixOS Samba Options](https://search.nixos.org/options?query=services.samba)
- [Apple Time Machine over SMB](https://wiki.samba.org/index.php/Configure_Samba_to_Work_Better_with_Mac_OS_X)
- [ZFS Best Practices](https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/index.html)