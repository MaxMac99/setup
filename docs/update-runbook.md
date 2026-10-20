# Update-Runbook – wann was wie aktualisiert wird

Kurzreferenz für den Alltag. Die Begründungen und Entscheidungen stehen in
[update-strategy.md](update-strategy.md), offene Workarounds in
[workarounds.md](workarounds.md). gilt für die beiden Macs; die NixOS-Hosts
laufen über Renovate + manuelles/natives Rebuild wie in update-strategy.md
beschrieben.

## Die drei Update-Spuren

| Spur | Was hängt dran | Wer triggert | Rechte |
|---|---|---|---|
| **1. App-Eigen-Updater** | alle Casks mit `auto_updates` (oder `version :latest`) | die Apps selbst, im Hintergrund | keine |
| **2. Brew-Lauf (LaunchAgent)** | restliche Casks + Formulas | launchd, automatisch | keine |
| **3. Flake/Rebuild** | Nix-Pakete, Taps, flake inputs | Renovate-PR + dein `darwin-rebuild` | sudo beim `switch` (privat: Touch ID) |

Eine App liegt immer in genau **einer** Spur („eine App, ein Updater“).

## Wann was passiert

| Rhythmus | Ereignis |
|---|---|
| laufend | Spur 1: Discord, Chrome, Insomnia, OpenCode, t3-code, Zed, RustRover aktualisieren sich selbst |
| Di + Do 10:00 (+ Catch-up) | **kopf3-NB-26**: LaunchAgent `brew-autoupdate` (`brew upgrade` + `cleanup`) |
| beim Login, wenn > 3 Tage her | beide Macs: Catch-up-Lauf, Random-Delay 5–15 Min, Notification nur bei Updates/Fehlern |
| Freitag früh | Renovate: lockFileMaintenance-PR (automerge) |
| bei Bedarf / nach PR-merge | Spur 3: `git pull && sudo darwin-rebuild switch --flake .#<host>` |

Der LaunchAgent installiert nur, was der **aktuelle Tap-Stand** kennt. Neue
Versionen für Spur 2 kommen über Renovate (bumped die Tap-Inputs) + Rebuild —
der Agent ist der Apply-Schritt, nicht der Supply-Schritt.

## Welche Apps werden womit aktualisiert

| App | Spur | Wie |
|---|---|---|
| Discord, Google Chrome, Insomnia, OpenCode desktop, t3-code, Zed, RustRover, intellij-idea, tailscale-app, 1password, arc, docker-desktop, tunnelblick, ghostty, affinity, macfuse, logi-options+, logitune, stream-deck | 1 | In-App-Updater (`auto_updates`); der LaunchAgent lässt sie aus |
| autodesk-fusion | 1 | `version :latest`, der LaunchAgent lässt sie aus (kein `--greedy`) |
| claude-code, bambu-studio, Formulas | 2 | `brew upgrade` im LaunchAgent-Lauf |
| displaylink, focusrite-control | 2* | `.pkg` ohne `auto_updates`: steht in `brewAutoupdate.skip`, kommt via brew bundle beim Rebuild |
| Nix-Pakete (CLI-Tools, neovim, zoom, …) | 3 | `darwin-rebuild switch` nach Renovate-Merge |
| macOS selbst | – | Systemeinstellungen, bewusst manuell |

\* Hardware-Casks mit sudo-Pflichtigem .pkg-Installer: der User-Lauf würde
beim Upgrade am Admin-Prompt hängen, deshalb bewusst dem Root-Kontext des
Rebuilds überlassen. Ein neuer `.pkg`-Cask ohne `auto_updates` gehört in
`brewAutoupdate.skip` (`modules/system/darwin-brew-update.nix`).

⚠️ **Homebrew ≥ 7 upgradet `auto_updates`-Casks standardmäßig mit.** Der
LaunchAgent setzt deshalb `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1`; ohne
das hat er am 2026-10-20 docker-desktop und tunnelblick angefasst und ist an
sudo bzw. App-Management gescheitert. Ein manuelles `brew upgrade` im
Terminal hat die Variable nicht und tut das weiterhin.

⚠️ **Arbeits-Mac:** 1password, docker-desktop und tunnelblick liegen bewusst
in `/Applications` (root:admin). Ihre eigenen Updater fragen dort ohne
Admin-Rechte nach einem Passwort – das ist erwartet, nicht der Agent.

## Sudo-Kalender: wann mit, wann ohne

**Nie sudo nötig:**

- `nix build`, `nix eval`, flake-Auswertung — der User ist `trusted-user`
- `brew install/upgrade/cleanup/outdated`
- `hm-switch` bzw. jede HM-Aktivierung (schreibt nur ins User-Profil)
- der LaunchAgent-Lauf (läuft ohnehin im User-Kontext)

**Genau ein sudo pro Session:**

```bash
cd ~/projects/private/setup          # oder .work/setup-update-strategy
git pull
sudo darwin-rebuild switch --flake .#<host>
```

Das deckt alles in Spur 3 ab: Nix-Pakete, Tap-Re-Pointing (neue Cask-Versionen
werden dadurch erst für den LaunchAgent sichtbar), LaunchAgent-Definitionen,
sops-Secrets. Der Build selbst läuft schon sudo-frei durch (`nix build
.#darwinConfigurations.<host>.config.system.build.toplevel` vorweg schadet
nicht, spart Root-Build-Zeit). Auf dem privaten Mac authentifiziert sudo
lokal per Touch ID statt Passwort.

**⚠️ Arbeits-Mac (admin-by-request):** Ein sudoers-Drop-in für
`darwin-rebuild` (NOPASSWD) wäre dort die Lösung, ist aber vom IT-gemanagten
sudoers abhängig und nicht deklarativ erzwingbar. Ohne Admin-Rechte bleibt
der Switch dort passwortpflichtig — der promptlose Weg ist Spur 1 + 2
(LaunchAgents) und für alles unter `home-manager.users.*` `hm-switch`
(siehe unten und [sudoless-workflow.md](sudoless-workflow.md)).

**Bewusst mit Prompt im Alltag ausgeschlossen:**

- `homebrew.onActivation.upgrade` ist `false` — der Rebuild upgraded keine
  Brew-Pakete mehr, also kein sudo-Prompt mitten im Rebuild (das war der
  alte Zustand)
- macOS-Systemupdates bleiben manuell in den Systemeinstellungen

## Wenn etwas hakt

- **Notification „Update fehlgeschlagen“**: Log unter
  `~/Library/Logs/brew-autoupdate.log`, Ursache ist meist ein .pkg-Cask, der
  einen Admin-Prompt wollte → in `brewAutoupdate.skip` aufnehmen, dann
  nächsten Rebuild abwarten oder den Cask einmalig `brew upgrade`-en mit
  Passwort.
- **App ist alt geblieben, obwohl Release draußen ist**: Spur-1-App → App
  selbst updaten lassen; Spur-2-App → läuft mit dem nächsten Renovate-PR +
  Rebuild. Prüfen mit `brew outdated` bzw. `brew info <name>`.
- **Doppelläufe/verpasste Slots**: launchd holt verpasste Calendar-Slots beim
  nächsten Wake nach; der Catch-up-Lauf überspringt sich innerhalb der
  3-Tage-Frist selbst. Lock-Dir: `$TMPDIR/brew-autoupdate.lock` (stale nach
  2 h ignoriert).
- **Fix-Review**: quartalsweise `grep -rn TEMP-FIX modules/ hosts/ lib/`
  gegen [workarounds.md](workarounds.md).

## Home-Manager als sudoless-Ausweg für den Arbeits-Mac

Ein Teil von Spur 3 ist auch **ohne sudo** ziehbar — der Home-Manager-Anteil
derselben Flake-Konfiguration:

```bash
cd ~/projects/private/setup
git pull
hm-switch
```

`hm-switch` baut das `activationPackage` der eingebetteten HM-Konfiguration
und ruft es so auf wie das nix-darwin-Modul von Home-Manager beim Rebuild
(`activate --driver-version 1`, als User). Beide Wege sind deshalb beliebig
abwechselnd kompatibel. Ohne `--driver-version 1` liefe das Skript im
Legacy-Modus (Driver 0) und legte ein per-User-`home-manager`-Nix-Profil an,
Standalone-Zustand, den die embedded-Verdrahtung nie pflegt.

Das zieht: `home.packages`, nvim/direnv/zsh/opencode-Config, HM-LaunchAgents
(inkl. `brew-autoupdate`), User-Defaults, sops-Secrets. **Nicht** erfasst:
`/etc`, nix-daemon-Settings, `system.defaults`, `environment.systemPackages`,
nix-homebrew/Tap-Re-Pointing, brew bundle. Rhythmus: `hm-switch` für den
Alltag, echter Rebuild bei Admin-Gelegenheit (admin-by-request).

Alle Rezepte (zsh, opencode, neue Tools/Apps, Updates):
[sudoless-workflow.md](sudoless-workflow.md).
