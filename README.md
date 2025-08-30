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

### GitHub

In order to check out this repo create a new SSH-Key named `id_github` and
register it at GitHub.

For Kopf3 you need to create a separate SSH-Key named `id_kopf3_github`. You can
register it later with `gh auth login`.

## Updates

```sh
nix flake update
```
