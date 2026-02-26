# macOS system configuration - included on every darwin host via flake.nix
{
  config,
  ...
}: {
  system.primaryUser = config.hostSpec.username;

  users.users.${config.hostSpec.username} = {
    home = "/Users/${config.hostSpec.username}";
  };

  networking = {
    localHostName = config.hostSpec.hostName;
    wakeOnLan.enable = true;
  };

  nix.gc.interval = {
    Weekday = 0;
    Hour = 2;
    Minute = 0;
  };

  power = {
    sleep = {
      allowSleepByPowerButton = true;
      display = 20;
      harddisk = 10;
    };
  };

  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
    watchIdAuth = true;
  };

  system = {
    stateVersion = 6;

    defaults = {
      NSGlobalDomain = {
        AppleEnableMouseSwipeNavigateWithScrolls = true;
        AppleEnableSwipeNavigateWithScrolls = true;
        AppleInterfaceStyle = "Dark";
        AppleInterfaceStyleSwitchesAutomatically = false;
        ApplePressAndHoldEnabled = false;
        AppleShowAllFiles = true;
        AppleShowScrollBars = "WhenScrolling";
        AppleWindowTabbingMode = "always";
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        "com.apple.keyboard.fnState" = false;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 1.0;
        "com.apple.springing.delay" = 1.0;
        "com.apple.springing.enabled" = true;
        "com.apple.trackpad.forceClick" = true;
      };
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      WindowManager = {
        AppWindowGroupingBehavior = true;
        AutoHide = false;
        EnableStandardClickToShowDesktop = false;
        StandardHideDesktopIcons = false;
        StandardHideWidgets = false;
      };
      controlcenter = {
        BatteryShowPercentage = true;
        NowPlaying = true;
        Sound = true;
      };
      dock = {
        autohide = true;
        largesize = 128;
        magnification = true;
        tilesize = 45;
        wvous-br-corner = 1;
      };
      finder = {
        ShowHardDrivesOnDesktop = true;
      };
      loginwindow.GuestEnabled = false;
      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
      };
      CustomUserPreferences = {
        NSGlobalDomain = {
          NSStatusItemSpacing = 8;
        };
      };
    };
  };
}