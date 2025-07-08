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
    mac-app-util = {
      url = "github:hraban/mac-app-util";
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
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    home-manager,
    nix-homebrew,
    homebrew-bundle,
    homebrew-core,
    homebrew-cask,
    mac-app-util,
    ...
  } @ inputs: let
    inherit (self) outputs;

    #
    # ========= Architectures =========
    #
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-darwin"
    ];

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
              mac-app-util.darwinModules.default
              nix-homebrew.darwinModules.nix-homebrew
              (
                {
                  pkgs,
                  config,
                  inputs,
                  ...
                }: {
                  # To enable it for all users:
                  home-manager.sharedModules = [
                    mac-app-util.homeManagerModules.default
                  ];
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
              inherit inputs outputs lib;
              isDarwin = true;
            };
            modules = [
              home-manager.nixosModules.home-manager
              ./hosts/nixos/${host}
            ];
          };
        })
        (builtins.attrNames (builtins.readDir ./hosts/nixos))
      );
  };
}
