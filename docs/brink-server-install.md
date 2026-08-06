# brink-server — bare-metal install

Runbook for migration Phase 5.1. Lenovo ThinkCentre M70q (i5-10500T, 32 GB,
single 1 TB NVMe) → NixOS on root-on-ZFS at Brink, static `192.168.1.2`.

**Why it is urgent:** Phase 3 depends on it. Moving the pi to Winkel left Brink
with no overlay-capable host, and the UDM SE cannot fill that role — there is no
first-party Tailscale app for UniFi OS, only an unsupported community package
(migration doc 3.1, 3.2).

**Scope.** This gets a *bootable, reachable, declaratively-managed* host. It
deliberately stops there. Not done here, and not to be helpfully added:

| Deferred to | What |
|---|---|
| Phase 3 | overlay client, subnet router for `192.168.1.0/24`, `net.ipv4.ip_forward`, the UDM SE static route |
| Phase 4 | AdGuard |
| Phase 7 | k3s server role, etcd, node labels |
| Phase 11 | ZFS replication to maxdata's `tank` |

---

## 0. State before starting

Already true:

- `hosts/nixos/brink-server/{default,hardware-configuration}.nix` are committed
  and **evaluate** — `nix eval …#nixosConfigurations.brink-server.…drvPath`
  succeeds. Rendered address is `192.168.1.2/24`, gateway `192.168.1.1`.
- The installer ISO is at `~/Downloads/nixos-minimal-26.05-x86_64.iso` on the
  Mac, SHA-256 verified against the published checksum
  (`7f5df09b…f870`).
- `192.168.1.2` is free (Phase 0, verified on the wire) and sits *below* the UDM
  SE's DHCP floor of `.6`, so no reservation or range change is needed to claim
  it.

Needed at Brink: the M70q and its **external power brick**, a ≥2 GB USB stick, a
monitor + DisplayPort/HDMI cable, a USB keyboard, and an ethernet run to the UDM
SE. brink-server must be wired — it takes a static address and becomes the
subnet router.

> **Unrelated open item, do not conflate.** The UDM SE's DHCP range still needs
> shrinking from auto (`.6–.254`) to `.6–.199`. That is a *Phase 8* prerequisite
> for the MetalLB pool at `.240–.250`, not a prerequisite for this install.

---

## 1. Write the ISO to the USB stick (on the Mac)

```sh
diskutil list external physical
```

⚠️ Read the size column and confirm it is the stick. The next command is
unrecoverable if it names the internal drive.

```sh
DISK=/dev/disk4                       # ← substitute the real one
diskutil unmountDisk "$DISK"
sudo dd if=~/Downloads/nixos-minimal-26.05-x86_64.iso \
        of="${DISK/disk/rdisk}" bs=4m status=progress
diskutil eject "$DISK"
```

`rdisk` rather than `disk` is the raw device — an order of magnitude faster.

---

## 2. Firmware

Power on, tap **F1** for BIOS setup (**F12** is the one-time boot menu).

- **Secure Boot → Disabled.** NixOS's bootloader is unsigned.
- **Boot mode → UEFI only.** The config uses systemd-boot, which is UEFI-only;
  a CSM/legacy boot produces a host that installs and then does not boot.
- **After Power Loss → Power On.** Not cosmetic: this box becomes Brink's subnet
  router and primary DNS, and the migration plan already flags Brink as
  single-node. It must come back by itself after an outage.

Save, then boot the USB stick via F12.

---

## 3. Boot the installer and get a shell you can paste into

At the console:

```sh
sudo -i
ip -4 -o addr show          # note the DHCP lease the UDM SE handed out
```

Strongly recommended — switch to SSH from the Mac rather than typing ZFS
commands at a console:

```sh
# on the installer
passwd nixos                # the live user has no password by default
systemctl start sshd
```

```sh
# on the Mac
ssh nixos@<lease-address>
sudo -i
```

---

## 4. Confirm ZFS is actually present

```sh
modprobe zfs && zpool version
```

If this fails, stop — everything below depends on it, and a mismatched
out-of-band `zfs` package will not help because the kernel module must match the
running kernel.

---

## 5. Identify the disk

```sh
lsblk -o NAME,SIZE,MODEL,SERIAL
ls -l /dev/disk/by-id/ | grep nvme | grep -v part
```

Pin it by stable id, never by `/dev/nvme0n1`:

```sh
DISK=/dev/disk/by-id/nvme-<model>_<serial>     # ← substitute
```

---

## 6. Partition

`sgdisk` lives in `gptfdisk`; if it is missing, `nix-shell -p gptfdisk`.

```sh
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:EF00 -c1:ESP "$DISK"      # 1 GiB ESP
sgdisk -n2:0:0   -t2:BF00 -c2:zfs "$DISK"      # remainder
partprobe "$DISK"; sleep 2; ls -l "$DISK"-part*
```

1 GiB rather than the usual 512 MiB because systemd-boot keeps a kernel and
initrd in the ESP **per generation**, and a full ESP breaks
`nixos-rebuild switch` in a way that is annoying to diagnose.

The filesystem label is load-bearing — `hardware-configuration.nix` mounts
`/boot` by `/dev/disk/by-label/BOOT`:

```sh
mkfs.vfat -F32 -n BOOT "${DISK}-part1"
```

---

## 7. Pool and datasets

```sh
zpool create -f \
  -o ashift=12 \
  -o autotrim=on \
  -O compression=zstd \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O mountpoint=none \
  fast "${DISK}-part2"
```

Two deliberate choices:

- **Pool name `fast`**, matching maxdata's NVMe pool, so that
  `/fast/k8s/local-path-provisioner` means the same thing on both k3s servers.
  Phases 6.2 and 8 both depend on that path.
- **`compression=zstd`**, where maxdata uses `lz4`. A conscious divergence: zstd
  gives materially better ratios at negligible CPU cost on a 10th-gen i5, and
  this box has a single unmirrored disk, so capacity is worth more than the last
  few percent of throughput. Replication in Phase 11 is unaffected — compression
  is per-dataset and re-applied on receive.

```sh
zfs create -o mountpoint=legacy fast/root
zfs create -o mountpoint=legacy fast/nix
zfs create -o mountpoint=legacy fast/home
zfs create -o mountpoint=legacy fast/k8s
zfs list
```

`mountpoint=legacy` throughout, so NixOS's `fileSystems` is the single source of
truth rather than ZFS's own mountpoint property — matching maxdata.

---

## 8. Mount

Order matters: `/mnt` first, then the directories inside it.

```sh
mount -t zfs fast/root /mnt
mkdir -p /mnt/boot /mnt/nix /mnt/home /mnt/fast/k8s
mount -t zfs fast/nix  /mnt/nix
mount -t zfs fast/home /mnt/home
mount -t zfs fast/k8s  /mnt/fast/k8s
mount /dev/disk/by-label/BOOT /mnt/boot
findmnt -R /mnt
```

---

## 9. Reconcile the hardware config

The committed `hardware-configuration.nix` has a hand-written `fileSystems`
block (correct by construction — step 7 created exactly that layout) and
**guessed** kernel-module lists. Check the guess:

```sh
nixos-generate-config --root /mnt --no-filesystems --show-hardware-config
```

`--no-filesystems` matters: without it the generated output replaces the layout
above with `by-uuid` paths and the pool-name intent is lost.

Compare `boot.initrd.availableKernelModules` and `boot.kernelModules` with the
committed file and edit it if they differ. Also record the NIC's real name:

```sh
ip -o link show
```

The config matches `en*` because the name was unknown when it was written. If
the real name is e.g. `eno1`, narrow `matchConfig.Name` in
`hosts/nixos/brink-server/default.nix` — `en*` would also claim a USB NIC.

---

## 10. Put the flake on the box

Commit first — **flakes only see git-tracked files**, so an uncommitted edit is
invisible to `nixos-install` and you will silently install the previous state.

```sh
# on the Mac
cd ~/projects/private/setup/multi-site
git status --short          # must be clean, or at least the edits committed
rsync -a --info=progress2 ./ nixos@<lease-address>:/tmp/setup/
```

`.git` is included on purpose: it makes `/etc/nixos` a real clone, which is what
the self-update path in step 13 needs.

```sh
# on the installer
mkdir -p /mnt/etc
cp -a /tmp/setup /mnt/etc/nixos
```

---

## 11. Install

```sh
nixos-install --flake /mnt/etc/nixos#brink-server
```

This builds the whole closure on the box — expect a while. It cannot be built on
the Mac: both Macs are aarch64-darwin and this is x86_64-linux.

It prompts for a **root** password at the end. Then give `max` one, for console
login, and hand `/etc/nixos` to `max` so `git pull` works as a normal user:

```sh
nixos-enter --root /mnt -c 'passwd max'
nixos-enter --root /mnt -c 'chown -R max:users /etc/nixos'
```

SSH as `max` already works without a password — `modules/system/base.nix`
installs the public keys from `modules/data/keys/`.

---

## 12. Reboot, then verify — after the reboot, not before

```sh
umount -R /mnt
zpool export fast
reboot
```

Pull the USB stick during POST.

⚠️ **Judge success only after a clean boot.** The migration doc's 6.5 lesson
applies to the verification even though the failure mode itself does not:
this host uses systemd-networkd, not scripted networking, precisely so a
rebuild cannot strip its addresses — but a first boot is still the only honest
proof the network unit is right.

From the Mac, on the Brink LAN:

```sh
ssh max@192.168.1.2 '
  hostname
  ip -4 -o addr show
  ip -4 route show default          # ← must be non-empty
  curl -sI https://cache.nixos.org | head -1   # ← outbound actually works
  zpool status
  systemctl --failed
'
```

The default route and the outbound request are checked **explicitly and
separately**. On the pi, a host once came up LAN-reachable with no default
route: it looked healthy from the same subnet while every outbound connection
failed with `Network is unreachable`, and a rebuild silently used a stale
commit.

Exit condition for this step: `hostname` is `brink-server`, the address is
`192.168.1.2/24`, the default route points at `192.168.1.1`, `curl` returns
`HTTP/2 200`, `zpool status` is clean, and `systemctl --failed` lists nothing.

---

## 13. Post-install enrolment

### a. Deploy key, so the box can update itself

```sh
# on brink-server
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_brink_server -C "brink-server deploy key"
cat ~/.ssh/id_brink_server.pub
```

On GitHub → `MaxMac99/setup` → Settings → Deploy keys → Add deploy key. Title
`brink-server`, **read-only** (leave "Allow write access" unchecked).

It must be a *distinct* key from the pi's `id_k3s_pi`: GitHub refuses to
register the same deploy key on a repository twice. Read-only scoping means a
compromised brink-server cannot rewrite the fleet's configuration.

```sh
# on brink-server — from here on this is the update cycle
cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#brink-server
```

### b. sops host key

The config already points `age.sshKeyPaths` at the **host** key
(`/etc/ssh/ssh_host_ed25519_key`) rather than a user key — unlike ionos and
maxdata, both of which still derive from `/home/max/.ssh/id_ed25519` and are
scheduled for correction in Phases 3 and 6.1.

Zero secrets are declared, which is what made it safe to commit the plumbing
before the host existed. Enrol the key now so Phase 3 can just add one:

```sh
# on the Mac
ssh max@192.168.1.2 'cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age
```

Add the resulting `age1…` to `.sops.yaml` as `&brink-server`, add it to the
`secrets/common.yaml` key group, then:

```sh
sops updatekeys secrets/common.yaml
git commit -am "feat(brink-server): enrol host age key"
```

Prove it decrypts **on the box** — matching on paper is not proof:

```sh
ssh max@192.168.1.2
cd /etc/nixos && git pull
sudo sh -c '
  nix run nixpkgs#ssh-to-age -- -private-key -i /etc/ssh/ssh_host_ed25519_key > /tmp/age.key
  SOPS_AGE_KEY_FILE=/tmp/age.key nix run nixpkgs#sops -- -d secrets/common.yaml > /dev/null \
    && echo "DECRYPT OK"
  rm -f /tmp/age.key
'
```

---

## 14. Exit criteria

- [ ] Boots unattended from the NVMe; USB stick removed
- [ ] `hostname` = `brink-server`, address `192.168.1.2/24`, default route
      present, outbound HTTPS works — all verified **after a reboot**
- [ ] `zpool status` clean; `/`, `/nix`, `/home`, `/fast/k8s` mounted from `fast`
- [ ] `systemctl --failed` empty
- [ ] `hardware-configuration.nix` reconciled against the real hardware and the
      NIC match narrowed from `en*` to the real name
- [ ] Deploy key registered read-only; `git pull && nixos-rebuild switch` works
      on the box
- [ ] Host age key enrolled in `.sops.yaml`; **decrypt proven on the box**
- [ ] "After Power Loss → Power On" set in firmware

Then Phase 3 is unblocked.
