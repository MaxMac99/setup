# Xcode (and with it xcodebuild/xcrun) plus xcodegen, on every Mac that
# builds the iOS apps (meals, photonic) — by hand or via the self-hosted
# GitHub runners.
#
# ⚠️ Xcode comes from the Mac App Store via mas, so the user must be signed
# into the App Store, or the whole `brew bundle` step of darwin-rebuild fails.
# mas installs into /Applications regardless of homebrew.caskArgs.appdir.
# Removing it here does not uninstall it (Homebrew Bundle limitation).
#
# The App Store install alone leaves xcodebuild unusable: xcode-select still
# points at the Command Line Tools ("requires Xcode"), the license is not
# accepted, and the first-launch packages are missing. All three need root,
# so they run in activation — which is also the only way they work on the
# work Mac, where the user is not in `admin`. Skipped until Xcode exists, so
# the first rebuild (which installs it) configures it too: homebrew runs
# before postActivation.
#
# Simulator runtimes are not installed here (several GB, would block every
# rebuild that finds one missing). One-time per Mac:
#   xcodebuild -downloadPlatform iOS
{
  config,
  lib,
  pkgs,
  ...
}: {
  homebrew.masApps.Xcode = 497799835;

  home-manager.users.${config.hostSpec.username}.home.packages = [pkgs.xcodegen];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    if [ -d /Applications/Xcode.app ]; then
      echo "configuring Xcode..." >&2
      /usr/bin/xcode-select --switch /Applications/Xcode.app/Contents/Developer
      /usr/bin/xcodebuild -license accept
      /usr/bin/xcodebuild -checkFirstLaunchStatus || /usr/bin/xcodebuild -runFirstLaunch
    fi
  '';
}
