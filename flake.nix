{
  description = "Configuration for all Nix managed devices";

  nixConfig = {
    extra-substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    extra-trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
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
    proxmox-nixos = {
      url = "github:SaumonNet/proxmox-nixos";
      inputs.nixpkgs-unstable.follows = "nixpkgs";
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
    ...
  } @ inputs: let
    inherit (self) outputs;

    # ========== Extend lib with lib.custom ==========
    # NOTE: This approach allows lib.custom to propagate into hm
    # see: https://github.com/nix-community/home-manager/pull/3454
    lib = nixpkgs.lib.extend (self: super: {custom = import ./lib {inherit (nixpkgs) lib;};});
  in {
    darwinConfigurations =
      builtins.listToAttrs
      (
        map
        (host: {
          name = host;
          value = darwin.lib.darwinSystem {
            specialArgs = {
              inherit inputs outputs lib;
              isDarwin = true;
            };
            modules = [
              home-manager.darwinModules.home-manager
              nix-homebrew.darwinModules.nix-homebrew
              (
                {config, lib, pkgs, ...}: {
                  nixpkgs.config.allowUnfree = true;
                }
              )
              ./hosts/darwin/${host}
            ];
          };
        })
        (builtins.attrNames (builtins.readDir ./hosts/darwin))
      );
    nixosConfigurations =
      builtins.listToAttrs
      (
        map
        (host: {
          name = host;
          value = nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit self inputs outputs lib;
              isDarwin = false;
            };
            modules = [
              home-manager.nixosModules.home-manager
              (
                {config, ...}: {
                  nixpkgs.config.allowUnfree = true;
                }
              )
              ./hosts/nixos/${host}
            ];
          };
        })
        (builtins.attrNames (builtins.readDir ./hosts/nixos))
      );
  };
}
