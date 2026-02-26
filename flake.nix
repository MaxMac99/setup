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
        specialArgs = {inherit self inputs outputs lib;};
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
  in {
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
      builtins.listToAttrs
      (
        map
        (host: {
          name = host;
          value = mkNixosHost host;
        })
        (builtins.attrNames (builtins.readDir ./hosts/nixos))
      );
  };
}