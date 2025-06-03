{
  description = "Home Manager configuration of maxvissing";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mac-app-util.url = "github:hraban/mac-app-util";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, mac-app-util, ... }:
    let
      username = "maxvissing";
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          mac-app-util.homeManagerModules.default
          ({ pkgs, ... }: {
            home = {
              inherit username;
              homeDirectory = "/Users/${username}";
              # This is where you would install any programs as usual:
              packages = with pkgs; [
                ripgrep
                oauth2c
              ];
              stateVersion = "24.05";
            };
          })
          ./home.nix
          ./git.nix
          ./alacritty.nix
          ./nvim.nix
          ./tmux.nix
          # ./zed.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
