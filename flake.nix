{
  description = "Configuration for all Nix managed devices";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    zfs-exporter = {
      url = "github:MaxMac99/ZFS-Prometheus-Exporter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    home-manager,
    nix-homebrew,
    sops-nix,
    ...
  } @ inputs: let
    inherit (self) outputs;

    # ========== Extend lib with lib.custom ==========
    # NOTE: This approach allows lib.custom to propagate into hm
    # see: https://github.com/nix-community/home-manager/pull/3454
    lib = nixpkgs.lib.extend (self: super: {custom = import ./lib {inherit (nixpkgs) lib;};});

    mkDarwinHost = host:
      darwin.lib.darwinSystem {
        specialArgs = {inherit inputs outputs lib;};
        modules = [
          ./modules/data/host-spec.nix
          ./modules/data/network-config.nix
          ./modules/system/base.nix
          ./modules/system/darwin.nix
          ./modules/system/darwin-homebrew.nix
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew
          sops-nix.darwinModules.sops
          {nixpkgs.config.allowUnfree = true;}
          ./hosts/darwin/${host}
        ];
      };

    mkNixosHost = host:
      nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit self inputs outputs lib;
          inherit (inputs) nixos-raspberrypi;
        };
        modules = [
          ./modules/data/host-spec.nix
          ./modules/data/network-config.nix
          ./modules/system/base.nix
          ./modules/system/nixos.nix
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          {nixpkgs.config.allowUnfree = true;}
          ./hosts/nixos/${host}
        ];
      };
    mkRPiInstaller = nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit self inputs outputs lib;
        inherit (inputs) nixos-raspberrypi;
      };
      modules = [
        inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
        inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
        inputs.nixos-raspberrypi.lib.inject-overlays
        inputs.nixos-raspberrypi.nixosModules.sd-image
        ({
          modulesPath,
          lib,
          ...
        }: {
          imports = [
            (modulesPath + "/profiles/installation-device.nix")
          ];

          # nixos-raspberrypi: swraid breaks rpi boot
          boot.swraid.enable = lib.mkForce false;
          installer.cloneConfig = false;
          documentation.enable = lib.mkForce false;

          # Disable ZFS — the installer profile pulls it in, but the rpi kernel
          # cache only has the `out` output, not `-dev` (headers). Any external
          # kernel module forces a full kernel rebuild.
          boot.supportedFilesystems.zfs = lib.mkForce false;

          # ASM1153 USB-SATA bridge: disable UAS to avoid I/O stalls under load
          boot.kernelParams = ["usb-storage.quirks=174c:55aa:u"];

          nixpkgs.hostPlatform = "aarch64-linux";
          networking.hostName = "k3s-pi-installer";
          networking.useDHCP = lib.mkDefault true;

          system.stateVersion = "25.11";
        })
      ];
    };

    forAllSystems = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-linux" "aarch64-linux"];
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages.aarch64-linux.k3s-pi-installer = mkRPiInstaller.config.system.build.sdImage;

    darwinConfigurations =
      builtins.listToAttrs
      (
        map
        (host: {
          name = host;
          value = mkDarwinHost host;
        })
        (builtins.attrNames (builtins.readDir ./hosts/darwin))
      );
    nixosConfigurations =
      (builtins.listToAttrs
        (
          map
          (host: {
            name = host;
            value = mkNixosHost host;
          })
          (builtins.attrNames (builtins.readDir ./hosts/nixos))
        ))
      // {
        k3s-pi-installer = mkRPiInstaller;
      };
  };
}
