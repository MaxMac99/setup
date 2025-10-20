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
        "server string" = "maxdata NAS";
        "netbios name" = "maxdata";

        # Security settings
        security = "user";
        "map to guest" = "Bad User";
        "guest account" = "nobody";

        # Performance tuning
        "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
        "read raw" = "yes";
        "write raw" = "yes";
        "max xmit" = 65535;
        "dead time" = 15;
        "getwd cache" = "yes";

        # macOS optimization
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";

        # Enable Time Machine discovery
        "fruit:advertise_fullsync" = "true";

        # Logging
        "log level" = 1;
        "max log size" = 100;
      };

      # Time Machine backup shares
      "timemachine-max" = {
        path = "/tank/timemachine-max";
        "valid users" = "max";
        "read only" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "800G";
        "fruit:aapl" = "yes";
        "fruit:encoding" = "native";
        "vfs objects" = "catia fruit streams_xattr";
        browseable = "yes";
        comment = "Time Machine - Max";
      };

      "timemachine-michael" = {
        path = "/tank/timemachine-michael";
        "valid users" = "michael";
        "read only" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "600G";
        "fruit:aapl" = "yes";
        "fruit:encoding" = "native";
        "vfs objects" = "catia fruit streams_xattr";
        browseable = "yes";
        comment = "Time Machine - Michael";
      };

      # Personal data shares
      "Daten Max" = {
        path = "/tank/daten-max";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "max";
        "create mask" = "0644";
        "directory mask" = "0755";
        "vfs objects" = "catia fruit streams_xattr";
        comment = "Daten Max";
      };

      "Daten Michael" = {
        path = "/tank/daten-michael";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "michael";
        "create mask" = "0644";
        "directory mask" = "0755";
        "vfs objects" = "catia fruit streams_xattr";
        comment = "Daten Michael";
      };

      "Daten Anna" = {
        path = "/tank/daten-anna";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "anna";
        "create mask" = "0644";
        "directory mask" = "0755";
        "vfs objects" = "catia fruit streams_xattr";
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
        "vfs objects" = "catia fruit streams_xattr";
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
      smb = ''
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
            <port>9</port>
            <txt-record>model=MacSamba</txt-record>
          </service>
          <service>
            <type>_adisk._tcp</type>
            <port>9</port>
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