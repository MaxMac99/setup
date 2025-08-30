# Max Nix Setup

## Setup

1. Download
   [Nix Installer from Determinate Systems](https://github.com/DeterminateSystems/nix-installer?tab=readme-ov-file#determinate-nix-installer):
   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   ```
2. Select `No` to use the vanilla Nix upstream instead of the determinate.
3. Initial install
   ```sh
   sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#<YOUR_HOSTNAME>
   ```
4. Every other install just needs
   ```sh
   sudo darwin-rebuild switch --flake .#<YOUR_HOSTNAME>
   ```

## Updates

```sh
nix flake update
```

