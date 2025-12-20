# ZFS Disk Replacement Guide

This guide covers the complete procedure for replacing a failed disk in a ZFS pool on maxdata.

## Understanding the Risk

### RAIDZ1 Configuration
- **Tolerance**: Can lose 1 disk without data loss
- **Vulnerable State**: Once a disk fails, if ANY other disk fails before replacement completes, ALL data in that vdev is lost
- **Action Required**: Replace failed disks IMMEDIATELY

### RAIDZ2 Configuration
- **Tolerance**: Can lose 2 disks without data loss
- **Safer**: More time to replace disks, but still replace promptly

## Pre-Replacement Checklist

### 1. Identify the Failed Disk

```bash
# Check pool status
zpool status tank
zpool status fast

# Look for FAULTED or DEGRADED disks
# Example output:
#   ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P  FAULTED  179  0  46  too many errors
```

### 2. Check SMART Status

```bash
# Find the device path
ls -l /dev/disk/by-id/ | grep WD-WCC7K3LHL53P

# Check SMART health
smartctl -a /dev/sdX

# Look for:
# - Current_Pending_Sector > 0 (CRITICAL)
# - Reallocated_Sector_Ct increasing
# - Failed SMART self-tests
```

### 3. Check Other Disks

**CRITICAL**: Before replacing, verify other disks are healthy:

```bash
# Check SMART status of all disks
for disk in /dev/sd?; do
  echo "=== $disk ==="
  smartctl -H $disk
  smartctl -a $disk | grep -E "Reallocated|Pending|Uncorrectable"
done
```

If multiple disks show errors, **STOP** and prioritize data backup.

### 4. Order Replacement Disk

- **Size**: Same or larger capacity
- **Recommended**: WD Red Plus, Seagate IronWolf, or similar NAS-rated drives
- **Don't wait**: Order immediately upon detecting failure

## Replacement Procedure

### Step 1: Pre-Shutdown Preparation

```bash
# 1. Note the exact disk identifier
zpool status <pool_name> | grep FAULTED

# Example:
#   ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P

# 2. Find which /dev/sdX it corresponds to
ls -l /dev/disk/by-id/ | grep WD-WCC7K3LHL53P

# 3. Identify the physical location (SATA port)
udevadm info --query=all --name=/dev/sdX | grep ID_PATH

# 4. Take a full snapshot of pool status
zpool status -v > ~/zpool-status-before-replacement.txt
```

### Step 2: Physically Identify the Disk

**CRITICAL**: Pull the wrong disk = immediate data loss!

```bash
# Verify serial number on physical disk matches
# Serial: WD-WCC7K3LHL53P (printed on disk label)
```

- Mark the disk with a sticky note or tape
- Double-check serial number before pulling
- Note which bay/position it's in

### Step 3: Offline the Disk

```bash
# If not already offline, mark it offline
zpool offline <pool_name> ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P

# Verify offline status
zpool status <pool_name>
# Should show: OFFLINE or FAULTED
```

### Step 4: Shutdown (Non-Hot-Swap Systems)

For systems **without** hot-swap bays:

```bash
# Graceful shutdown
shutdown -h now
```

Wait 30 seconds after power LED goes off (capacitor discharge).

### Step 5: Physical Replacement

1. **Unplug power cord** from system
2. **Ground yourself** (touch metal case)
3. **Remove failed disk**:
   - Disconnect SATA data cable
   - Disconnect SATA power cable
   - Remove from bay/cage
4. **Install new disk**:
   - Mount in same bay (easier cable routing)
   - Connect SATA data cable
   - Connect SATA power cable
5. **Verify connections** are secure
6. **Power on system**

### Step 6: Verify New Disk Detection

```bash
# After boot, check new disk is detected
ls -l /dev/disk/by-id/ | grep ata-

# You should see a new entry like:
# ata-WDC_WD40EFZX-68AWUN0_WD-WX12345678

# Save the new disk ID
NEW_DISK_ID="ata-WDC_WD40EFZX-68AWUN0_WD-WX12345678"
```

### Step 7: Replace in ZFS

```bash
# Replace the failed disk with the new one
zpool replace <pool_name> \
  ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P \
  $NEW_DISK_ID

# This immediately starts the resilver process
# Output: "Make sure to wait until resilver is done before rebooting."
```

### Step 8: Monitor Resilver

```bash
# Watch resilver progress
watch -n 30 'zpool status -v'

# Output will show:
#   scan: resilver in progress since ...
#   5.2% resilvered, 0h23m to go
#   XX.XG scanned at XXG/s, XX.XG issued at XXG/s

# Or use:
zpool status -v | grep resilver
```

**Resilver Time Estimates**:
- **4TB drive**: 6-12 hours (depends on data amount)
- **8TB drive**: 12-24 hours
- **Larger drives**: Proportionally longer

## During Resilver (CRITICAL PERIOD)

### DO NOT:
- ❌ Power off the system
- ❌ Remove any other disks
- ❌ Run intensive I/O operations
- ❌ Add/remove datasets
- ❌ Interrupt the resilver process

### DO:
- ✅ Monitor progress regularly
- ✅ Check system logs: `journalctl -f -u zfs-resilver`
- ✅ Verify no new errors appear: `zpool status -v`
- ✅ Keep system running 24/7 until complete
- ✅ Monitor other disk SMART status

### Monitoring Commands

```bash
# Check resilver progress
zpool status <pool_name>

# Check system load (resilver is I/O intensive)
htop

# Check for new errors
dmesg | tail -50

# Check ZFS event log
zpool events | tail -20
```

## Post-Replacement Verification

### Step 1: Verify Resilver Completed

```bash
# Check pool status
zpool status <pool_name>

# Should show:
#   state: ONLINE
#   scan: resilvered XX.XG in XXhXXm with 0 errors on ...
#   All disks should show ONLINE status
```

### Step 2: Verify Pool Health

```bash
# No errors should be present
zpool status -v

# Check scrub status
zpool scrub <pool_name>
# Wait for scrub to complete (can take hours)

# After scrub completes, verify:
zpool status -v
# Should show: "0 errors"
```

### Step 3: Run SMART Tests

```bash
# Run extended test on new disk
smartctl -t long /dev/sdX

# Check test results after completion (8-12 hours for 4TB)
smartctl -a /dev/sdX

# Verify:
# - SMART overall-health self-assessment test result: PASSED
# - No pending sectors
# - No reallocated sectors (for new disk)
```

### Step 4: Update Documentation

```bash
# Save current pool status
zpool status -v > ~/zpool-status-after-replacement-$(date +%Y%m%d).txt

# Note replacement in maintenance log:
# Date: YYYY-MM-DD
# Pool: tank/fast
# Old disk: ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P
# New disk: ata-WDC_WD40EFZX-68AWUN0_WD-WX12345678
# Resilver time: XX hours
# Status: Completed successfully
```

## Hot-Swap Procedure (If Supported)

For systems with hot-swap bays (no shutdown needed):

```bash
# 1. Offline the disk first
zpool offline <pool_name> ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3LHL53P

# 2. Wait a few seconds
sleep 10

# 3. Physically pull the disk (LED should be off or indicating offline)

# 4. Insert new disk in same bay

# 5. Wait for kernel to detect
sleep 5

# 6. Verify new disk detected
ls -l /dev/disk/by-id/ | grep ata-

# 7. Replace in ZFS
zpool replace <pool_name> old_disk_id new_disk_id
```

## Troubleshooting

### Resilver Not Starting

```bash
# Check if disk is properly detected
lsblk
fdisk -l

# Check ZFS can see the disk
zpool import

# Try manual replace command again
zpool replace <pool_name> old_disk_id new_disk_id
```

### Resilver Stuck or Very Slow

```bash
# Check system load
top
iotop

# Check for other I/O operations
iotop -a

# Verify disk isn't failing
smartctl -H /dev/sdX

# Check ZFS ARC statistics
cat /proc/spl/kstat/zfs/arcstats
```

### New Errors During Resilver

```bash
# Check which disk has new errors
zpool status -v

# Check SMART status of all disks
for disk in /dev/sd?; do
  smartctl -H $disk
done

# If another disk is failing:
# 1. Do NOT power off
# 2. Check if you have another spare
# 3. Consider emergency data backup
```

## Prevention and Best Practices

### Regular Monitoring

1. **Monthly scrubs**: Already automated in zfs.nix
   ```nix
   services.zfs.autoScrub.interval = "monthly";
   ```

2. **Weekly SMART tests**: Configured in monitoring.nix
   - Daily short tests at 2 AM
   - Weekly long tests on Saturdays at 3 AM

3. **Prometheus alerts**: Monitor via Grafana
   - Pool degraded status
   - Disk errors
   - Pending sectors

### Disk Age Management

- **Replace disks proactively** at 4-5 years
- **Don't mix very old and new disks** in same vdev
- **Keep spare disks** on hand for quick replacement

### Pool Configuration

- **Consider RAIDZ2** for better fault tolerance
- **Don't use RAIDZ1 for drives > 4TB** (resilver time too long)
- **Keep vdev sizes reasonable** (max 8-10 disks per vdev)

### Emergency Preparedness

Keep these items ready:
- **Spare disk** of equal or larger size
- **Live USB** with ZFS support for recovery
- **Pool configuration backup**: `zpool import` output
- **Current disk serial numbers** and positions

## References

- Current ZFS configuration: `hosts/nixos/maxdata/zfs.nix`
- Monitoring configuration: `hosts/nixos/maxdata/monitoring.nix`
- SMART dashboard: `grafana-dashboards/smart-disk-health.json`
- Prometheus scrape config: `pulumi/k8s/monitoring/prometheus.ts`