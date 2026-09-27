# Update-Runbook – wann was wie aktualisiert wird

Kurzreferenz für den Alltag. Die Begründungen und Entscheidungen stehen in
[update-strategy.md](update-strategy.md), offene Workarounds in
[workarounds.md](workarounds.md). gilt für die beiden Macs; die NixOS-Hosts
laufen über Renovate + manuelles/natives Rebuild wie in update-strategy.md
beschrieben.

## Die drei Update-Spuren

| Spur | Was hängt dran | Wer triggert | Rechte |
|---|---|---|---|
| **1. App-Eigen-Updater** | 7 GUI-Casks mit `auto_updates` | die Apps selbst, im Hintergrund | keine |
| **2. Brew-Lauf (LaunchAgent)** | restliche Casks + Formulas | launchd, automatisch | keine |
| **3. Flake/Rebuild** | Nix-Pakete, Taps, flake inputs | Renovate-PR + dein `darwin-rebuild` | sudo nur beim finalen `switch` |

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
| Discord, Google Chrome, Insomnia, OpenCode desktop, t3-code, Zed, RustRover | 1 | In-App-Updater (Sparkle o. ä.) |
| claude-code (Formula) | 2 | `brew upgrade` im LaunchAgent-Lauf |
| displaylink, macfuse, logi-options+, logitune, stream-deck, focusrite | 2* | LaunchAgent überspringt sie (kein `--greedy`); sie werden via brew bundle beim Rebuild aktualisiert – deren Installer brauchen ohnehin mal einen Reboot |
| intellij-idea, tailscale-app, 1password, arc, docker-desktop, ghostty, affinity, bambu-studio, autodesk-fusion | 2 | LaunchAgent-Lauf (ohne auto_updates-Flag) bzw. Rebuild |
| Nix-Pakete (CLI-Tools, neovim, zoom, …) | 3 | `darwin-rebuild switch` nach Renovate-Merge |
| macOS selbst | – | Systemeinstellungen, bewusst manuell |

\* Hardware-Casks mit sudo-Pflichtigem .pkg-Installer: der User-Lauf würde
beim Upgrade am Admin-Prompt hängen, deshalb bewusst dem Root-Kontext des
Rebuilds überlassen.

## Sudo-Kalender: wann mit, wann ohne

**Nie sudo nötig:**

- `nix build`, `nix eval`, flake-Auswertung — der User ist `trusted-user`
- `brew install/upgrade/cleanup/outdated`
- `home-manager`-Aktionen (schreiben nur ins User-Profil)
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
nicht, spart Root-Build-Zeit).

**Bewusst mit Prompt im Alltag ausgeschlossen:**

- `homebrew.onActivation.upgrade` ist `false` — der Rebuild upgraded keine
  Brew-Pakete mehr, also kein sudo-Prompt mitten im Rebuild (das war der
  alte Zustand)
- macOS-Systemupdates bleiben manuell in den Systemeinstellungen

## Wenn etwas hakt

- **Notification „Update fehlgeschlagen“**: Log unter
  `~/Library/Logs/brew-autoupdate.log`, Ursache ist meist ein .pkg-Cask, der
  einen Admin-Prompt wollte → nächsten Rebuild abwarten oder den Cask
  einmalig `brew upgrade`-en mit Passwort.
- **App ist alt geblieben, obwohl Release draußen ist**: Spur-1-App → App
  selbst updaten lassen; Spur-2-App → läuft mit dem nächsten Renovate-PR +
  Rebuild. Prüfen mit `brew outdated` bzw. `brew info <name>`.
- **Doppelläufe/verpasste Slots**: launchd holt verpasste Calendar-Slots beim
  nächsten Wake nach; der Catch-up-Lauf überspringt sich innerhalb der
  3-Tage-Frist selbst. Lock-Dir: `$TMPDIR/brew-autoupdate.lock` (stale nach
  2 h ignoriert).
- **Fix-Review**: quartalsweise `grep -rn TEMP-FIX modules/ hosts/ lib/`
  gegen [workarounds.md](workarounds.md).
