{
  inputs,
  config,
  ...
}: {
  users.users.${config.hostSpec.username} = {
    home = "/Users/${config.hostSpec.username}";
  };

  networking = {
    localHostName = config.hostSpec.hostName;
    wakeOnLan.enable = true;
  };

  nix-homebrew = {
    user = config.hostSpec.username;
    enable = true;
    enableRosetta = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };
    mutableTaps = false;
    autoMigrate = false;
  };

  homebrew = {
    enable = true;
    casks = [
      "ghostty"
      "arc"
      "zen"
      "docker-desktop"
      "displaylink"
      "elgato-stream-deck"
      "focusrite-control"
      "macfuse"
      "logi-options+"
      "logitune"
      "skim"
    ];
    taps = builtins.attrNames config.nix-homebrew.taps;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
      upgrade = true;
    };
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
        ApplePressAndHoldEnabled = false; # Repeat key instead of showing menu for special characters
        AppleShowAllFiles = true; # Show dotfiles
        AppleShowScrollBars = "WhenScrolling"; # Small bars in finder
        AppleWindowTabbingMode = "always";
        InitialKeyRepeat = 15; # After what time start repeating (fastest in GUI is 15)
        KeyRepeat = 2; # How fast to repeat (fastest in GUI is 2)
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
