#!/usr/bin/env bash
# Script to create ZFS datasets for SMB shares
# Run this on the NixOS server after deploying the SMB configuration

set -e

echo "Creating ZFS datasets for SMB shares on tank pool..."
echo ""

# Time Machine backup datasets
echo "Creating Time Machine datasets..."
echo "  - tank/timemachine-max (800GB quota)"
zfs create tank/timemachine-max
zfs set quota=800G tank/timemachine-max
zfs set compression=lz4 tank/timemachine-max
chown max:users /tank/timemachine-max
chmod 700 /tank/timemachine-max

echo "  - tank/timemachine-michael (600GB quota)"
zfs create tank/timemachine-michael
zfs set quota=600G tank/timemachine-michael
zfs set compression=lz4 tank/timemachine-michael
chown michael:users /tank/timemachine-michael
chmod 700 /tank/timemachine-michael

echo ""
echo "Creating personal data shares..."
echo "  - tank/daten-max"
zfs create tank/daten-max
zfs set compression=lz4 tank/daten-max
chown max:users /tank/daten-max
chmod 755 /tank/daten-max

echo "  - tank/daten-michael"
zfs create tank/daten-michael
zfs set compression=lz4 tank/daten-michael
chown michael:users /tank/daten-michael
chmod 755 /tank/daten-michael

echo "  - tank/daten-anna"
zfs create tank/daten-anna
zfs set compression=lz4 tank/daten-anna
chown anna:users /tank/daten-anna
chmod 755 /tank/daten-anna

echo ""
echo "Creating family shared data..."
echo "  - tank/daten-familie"
zfs create tank/daten-familie
zfs set compression=lz4 tank/daten-familie
chown max:users /tank/daten-familie
chmod 775 /tank/daten-familie

echo ""
echo "================================================================"
echo "ZFS datasets created successfully!"
echo "================================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Set SMB passwords for all users:"
echo "   sudo smbpasswd -a max && sudo smbpasswd -e max"
echo "   sudo smbpasswd -a michael && sudo smbpasswd -e michael"
echo "   sudo smbpasswd -a anna && sudo smbpasswd -e anna"
echo ""
echo "2. Check Samba status:"
echo "   sudo systemctl status smbd"
echo "   sudo systemctl status avahi-daemon"
echo ""
echo "3. List available shares:"
echo "   sudo smbclient -L localhost -U max"
echo ""
echo "4. View created datasets:"
echo ""
zfs list -t filesystem | grep tank