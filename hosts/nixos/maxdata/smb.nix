{
  config,
  lib,
  pkgs,
  ...
}: {
  # Samba/SMB configuration for Time Machine and multi-user file sharing

  # Create users for SMB access
  users.users = {
    michael = {
      isNormalUser = true;
      description = "Michael";
      home = "/home/michael";
      extraGroups = [ "users" ];
    };

    anna = {
      isNormalUser = true;
      description = "Anna";
      home = "/home/anna";
      extraGroups = [ "users" ];
    };
  };

  # Enable Samba service for Time Machine and data shares
  services.samba = {
    enable = true;
    openFirewall = true;

    # Disable Windows-specific services (we only need smbd for macOS)
    nmbd.enable = false; # NetBIOS name service
    winbindd.enable = false; # Windows domain integration

    # Global Samba configuration
    settings = {
      global = {
        # Server identification
        workgroup = "WORKGROUP";
        "server string" = "maxdata";
        "netbios name" = "maxdata";

        # Security settings
        security = "user";

        # SMB protocol settings - MINIMAL
        "server min protocol" = "SMB2";

        # MINIMAL VFS for Time Machine on ZFS
        "vfs objects" = "fruit streams_xattr";

        # ESSENTIAL Apple settings only
        "fruit:aapl" = "yes";
        "fruit:metadata" = "stream";
        "fruit:resource" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";

        # Extended attributes required
        "ea support" = "yes";

        # Logging
        "log level" = 1;
      };

      # Time Machine backup shares - MINIMAL
      "timemachine-max" = {
        path = "/tank/timemachine-max";
        "valid users" = "max";
        "public" = "no";
        "writeable" = "yes";
        "force user" = user;
        # Below are the most imporant for macOS compatibility
        # Change the above to suit your needs
        "fruit:aapl" = "yes";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };

      "timemachine-michael" = {
        path = "/tank/timemachine-michael";
        "valid users" = "michael";
        "public" = "no";
        "writeable" = "yes";
        "force user" = user;
        # Below are the most imporant for macOS compatibility
        # Change the above to suit your needs
        "fruit:aapl" = "yes";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };

      # Personal data shares (no fruit - not Time Machine targets)
      "Daten Max" = {
        path = "/tank/daten-max";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "max";
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Daten Max";
      };

      "Daten Michael" = {
        path = "/tank/daten-michael";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "michael";
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Daten Michael";
      };

      "Daten Anna" = {
        path = "/tank/daten-anna";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "anna";
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Daten Anna";
      };

      # Family shared data
      "Daten Familie" = {
        path = "/tank/daten-familie";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "max michael anna";
        "create mask" = "0664";
        "directory mask" = "0775";
        comment = "Daten Familie";
      };
    };
  };

  # Enable Avahi for service discovery (makes shares visible on macOS)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
    extraServiceFiles = {
      timemachine = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
          <service>
            <type>_device-info._tcp</type>
            <port>0</port>
            <txt-record>model=TimeCapsule8,119</txt-record>
          </service>
          <service>
            <type>_adisk._tcp</type>
            <txt-record>dk0=adVN=timemachine-max,adVF=0x82</txt-record>
            <txt-record>dk1=adVN=timemachine-michael,adVF=0x82</txt-record>
            <txt-record>sys=waMA=0,adVF=0x100</txt-record>
          </service>
        </service-group>
      '';
    };
  };

  # Firewall rules for SMB and mDNS
  networking.firewall = {
    allowedTCPPorts = [
      445 # SMB
      5353 # mDNS
    ];
    allowedUDPPorts = [
      5353 # mDNS
    ];
  };
}