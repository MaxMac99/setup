{
  config,
  lib,
  pkgs,
  ...
}: {
  # Samba/SMB configuration for multi-user file sharing

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

  # Enable Samba service for data shares
  services.samba = {
    enable = true;
    package = pkgs.samba4Full;
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
        "server role" = "standalone server";
        "netbios name" = "maxdata";

        # Security settings
        security = "user";

        # Protocol settings - critical for macOS compatibility
        "server min protocol" = "SMB2";

        "access based share enum" = "no";
        "hide unreadable" = "no";
        "inherit permissions" = "no";
        "load printers" = "no";
        "ntlm auth" = "no";

        # VFS modules - order is important
        # Removed acl_xattr globally - it causes POSIX ACLs that break Time Machine
        "vfs objects" = "fruit streams_xattr";

        # Apple compatibility settings
        "fruit:aapl" = "yes";  # Enable Apple extensions
        "fruit:nfs_aces" = "yes";  # Enable Apple extensions
        "fruit:model" = "TimeCapsule8,119";
        "fruit:metadata" = "stream";
        "fruit:veto_appledouble" = "no";
        "fruit:posix_rename" = "yes";
        "fruit:zero_file_id" = "yes";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";

        # Logging
        "log level" = 1;
      };


      # Personal data shares
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

  # Enable Avahi for SMB service discovery
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