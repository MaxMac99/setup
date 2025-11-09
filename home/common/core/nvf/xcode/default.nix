{pkgs, ...}: let
  xcode-build-server = pkgs.stdenv.mkDerivation {
    pname = "xcode-build-server";
    version = "1.2.0";

    src = pkgs.fetchFromGitHub {
      owner = "SolaWing";
      repo = "xcode-build-server";
      rev = "v1.2.0";
      sha256 = "sha256-jjTdfWKg2faNeMVn7Fl15vlsfmluDugE56YqkHMotik=";
    };

    buildInputs = [pkgs.python3];

    installPhase = ''
      mkdir -p $out/bin
      cp -r . $out/xcode-build-server
      mv $out/xcode-build-server/xcode-build-server $out/xcode-build-server/cli.py
      cat > $out/bin/xcode-build-server <<EOF
      #!${pkgs.python3}/bin/python3
      import sys
      sys.path.insert(0, "$out/xcode-build-server")
      import cli
      cli.main()
      EOF
      chmod +x $out/bin/xcode-build-server
    '';
  };

  xcode-project-cli = pkgs.stdenv.mkDerivation {
    pname = "xcode-project-cli";
    version = "0.9.4";

    src = pkgs.fetchFromGitHub {
      owner = "wojciech-kulik";
      repo = "XcodeProjectCLI";
      rev = "v0.9.4";
      sha256 = "sha256-Y52gYCBXDA1BHPJWBsm/fSqvSAl3K2ACIlrdou9TukI=";
    };

    nativeBuildInputs = with pkgs; [
      swift
      swiftpm
      cacert
    ];

    # Disable sandbox to allow network access for Swift Package Manager
    __noChroot = true;

    # Set up SSL certificates for Swift Package Manager
    preBuild = ''
      export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

      # Create cache directory for SPM
      export HOME=$TMPDIR
      mkdir -p $HOME/Library/Caches/org.swift.swiftpm
    '';

    buildPhase = ''
      swift build -c release
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp .build/release/XcodeProjectCLI $out/bin/
    '';

    meta = with pkgs.lib; {
      description = "A lightweight command-line tool for managing Xcode projects";
      homepage = "https://github.com/wojciech-kulik/XcodeProjectCLI";
      platforms = platforms.darwin;
    };
  };
  xcodebuild = pkgs.vimUtils.buildVimPlugin {
    name = "xcodebuild.nvim";
    src = pkgs.fetchFromGitHub {
      owner = "wojciech-kulik";
      repo = "xcodebuild.nvim";
      rev = "v7.0.0";
      hash = "sha256-9VSj5vKKUIUEHsh8MrLjqCAOtf+0a10pDikzOSNTtbs=";
    };
    nvimSkipModules = [
      "xcodebuild.ui.pickers"
      "xcodebuild.actions"
      "xcodebuild.project.manager"
      "xcodebuild.project.assets"
      "xcodebuild.integrations.xcode-build-server"
      "xcodebuild.integrations.dap"
      "xcodebuild.code_coverage.report"
      "xcodebuild.dap"
    ];
  };
in {
  imports = [
    ./pymobiledevice.nix
  ];
  programs.nvf.settings.vim.extraPlugins = {
    xcodebuild = {
      package = xcodebuild;
      setup = ''
        require('xcodebuild').setup({
        })
      '';
    };
  };
  home.packages = with pkgs; [
    xcbeautify
    ruby
    rubyPackages.xcodeproj
    openssl
    libusb1
    jq
    ripgrep
    coreutils
    xcode-build-server
    xcode-project-cli
  ];
}
