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

### SSH keys

On the Macs the SSH private keys live in **1Password**, not on disk, and ssh
reaches them through the 1Password SSH agent (Settings → Developer → *Use the
SSH agent*). `modules/profiles/projects.nix` sets `IdentityAgent` for `Host *`
and deploys the *public* halves to `~/.ssh/1password/`, because `IdentitiesOnly`
still needs a file on disk to decide which agent-resident key to offer.

Keys are separated by trust domain, not by destination host:

| 1Password item | Used for |
|---|---|
| `id_max_admin` | every NixOS host in this flake — this is `modules/data/keys/max-admin.pub`, installed into `authorized_keys` everywhere by `modules/system/base.nix` |
| `id_github` | GitHub, personal account |
| `id_kopf3_github` | GitHub, Kopf3 account — selected automatically inside `~/projects/kopf3/` |
| `id_hetzner` | Hetzner Storage Box (backup target) |

Rotating `id_max_admin` means replacing that `.pub` and rebuilding every host —
keep the old key authorised until the new one is proven, or you lock yourself
out of all of them at once.

**Vault keys belong to a person, device keys belong to a machine.** Anything in
1Password follows you to every device the vault syncs to, so it is named for
who it is and what it grants, never for the laptop it was generated on.
Headless hosts cannot talk to a vault agent, so their keys stay on disk and keep
their hostname — `modules/data/keys/maxdata.pub` is maxdata's own key, used for
machine-to-machine access, and is deliberately *not* in 1Password.

### Secrets

For secret management we are using sops-nix.

> **`~/.ssh/id_sops_age` is not an SSH key.** It exists only to derive this
> device's age identity, it authenticates to nothing, and it must **not** be
> moved into the 1Password SSH agent — the agent never exposes private key
> material, and `ssh-to-age` needs exactly that. Keep it as a plain file.

1. Create a device key named `id_sops_age` (`ssh-keygen -t ed25519`).
2. Create age-key
   ```sh
   mkdir -p ~/.config/sops/age
   ssh-to-age -private-key -i ~/.ssh/id_sops_age > ~/.config/sops/age/keys.txt
   ```
3. Add permissions
   ```sh
   ssh-to-age < ~/.ssh/id_sops_age.pub
   ```
   Copy the output in the [.sops.yaml]() to the specific group.
4. Edit secrets
   ```sh
   sops secrets/common.yaml
   ```

#### Add device

1. Add permissions to [.sops.yaml]().
2. Re-encrypt secrets
   ```sh
   sops updatekeys secrets/common.yaml
   ```

## Updates

```sh
nix flake update
```
