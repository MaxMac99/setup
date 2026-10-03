# Update-Strategie – Problemanalyse & Lösungsansätze

## Problemliste

1. **Anwendungen in nixpkgs sind oft nicht aktuell** – Pakete landen erst nach PR-Review in nixpkgs; am schnellsten ist man über die Eigen-Updater der Apps selbst.
2. **Auto-Updates der Anwendungen funktionieren nicht** – in-App-Updater sind unter Nix by design wirkungslos (read-only Store).
3. **Häufig Admin-Rechte für Updates nötig** – vermutlich `nixos-rebuild` mit `sudo` bzw. alte Multi-User-Nix-Setup-Reste (Details siehe unten).
4. **Bei `nix flake update` kommt es häufiger zu Problemen** – nixpkgs-Input und alle flake-Dependencies werden in einem Rutsch neu evaluiert, ohne dass ein getesteter Stand dazwischen liegt.
5. **Gefixte Probleme verschwinden beim nächsten `nix flake update` nicht zuverlässig aus dem Repo** – d.h. lokale Workarounds landen nie als Commit; der nächste Update-Commit „wäscht“ sie weg.
6. **Updates sind gigantisch und dauern teilweise ewig** – jeder flake update zieht alle Inputs gleichzeitig nach; Fixes/Workarounds gehen dadurch verloren (Punkt 5).

## Update-Trigger: Wann wird was aktualisiert?

Grundprinzip: **Jede „Schicht“ hat einen eigenen, bewusst gewählten Update-Mechanismus.** Nicht alles über Nix, nicht alles automatisch – sondern pro Schicht entscheiden, wer der kanonische Updater ist.

### Schichten und ihre Updater

| Schicht | Wo leben die Pakete | Update-Mechanismus | Trigger | Rechte | Frequenz |
|---|---|---|---|---|---|
| **GUI-Apps mit gutem Eigen-Updater** | Homebrew cask → `/Applications` | In-App-Updater (Sparkle o. ä.) | Die App selbst, automatisch im Hintergrund | Keine (user-schreibbar) | Kontinuierlich, von der App bestimmt |
| **Homebrew (Rest: formulae + casks ohne guten Eigen-Updater)** | `/opt/homebrew` | `brew upgrade` | LaunchAgent/Timer oder manuell in der Update-Session | Keine (brew-Verzeichnis gehört dem User) | Wöchentlich |
| **Home-Manager-Pakete** | User-Nix-Profile | `home-manager switch` nach flake update | Renovate-PR mergen + lokale Rebuild-Session | Keine | Mit jedem gemergten flake-PR |
| **System-Pakete (NixOS/nix-darwin)** | System-Profile | `nixos-rebuild switch` / `darwin-rebuild switch` bzw. `system.autoUpgrade` | Renovate-PR (flake.lock) mergen → Auto-Upgrade-Timer zieht den neuen Stand | Root – aber delegiert (Timer/sudoers, siehe unten) | Täglich/wöchentlich, automatisiert |
| **nixpkgs-Input selbst** | `flake.lock` | `nix flake lock --update-input nixpkgs` | Renovate-PR (auf neues nixpkgs-Release/Channel-Head) | Keine | Release-Sprünge bewusst, sonst wöchentlich minor |
| **Andere flake-Inputs** | `flake.lock` | Pro-Input-Updates statt alles-auf-einmal | Renovate, jeweils ein PR pro Input | Keine | Nach Upstream-Release |

### Wer triggert wann – konkret

1. **Renovate (PR-Workflow, Punkt 6 der Maßnahmenliste):**
   - Läuft im Hintergrund auf dem Repo und öffnet **einen PR pro flake-Input** (`nixpkgs`, `home-manager`, einzelne/flaky Deps).
   - Der PR enthält ausschließlich die `flake.lock`-Änderung – kein Handgemenge im Code. Damit ist ein Update immer ein reviewbarer, revertierbarer Commit.
   - Schedule: nixpkgs wöchentlich, single-Deps on-release. Kein „Update, wenn mir danach ist“ mehr.
2. **Mergen eines PRs ≠ Installation:** erst mit dem **nächsten Rebuild** auf der Maschine wird der neue Lock-Wirklichkeit. Das ist der zweite, getrennte Trigger:
   - NixOS-Hosts: `system.autoUpgrade` (oder eigener Timer), flake-basiert, mit `--flake github:…/setup#<host>` – holt sich nach dem Merge selbsttätig den neuen Stand.
   - darwin/Home-Manager: kurze manuelle/automatisierte Rebuild-Session (LaunchAgent oder tagesschaltend) – im Idealfall dasselbe Auto-Upgrade-Pattern.
3. **Apps mit Eigen-Updater:** triggern sich selbst – im Repo ist dafür **nichts zu tun**. Die Brewfile ist nur eine „App-Liste“ für Replication, kein Versionspinning.
4. **Homebrew-Rest (`brew upgrade`):** wöchentlicher LaunchAgent-Timer. Anders als bei Nix aktualisiert brew die App-Liste in `/Applications` **in-place** – es gibt kein Store-Konzept, das man „switchen“ müsste.

### Regel: Eine App, genau ein Updater

- Eine App, die über Brewfile mit gutem Eigen-Updater verteilt wird, darf **nicht** zusätzlich von `brew upgrade` „versorgt“ werden (z. B. cask mit `auto_updates true` aus dem Upgrade-Lauf ausschließen): sonst kämpfen zwei Updater gegeneinander – die App hat sich via Sparkle auf 2.1 geupdatet, brew sieht noch cask-Version 2.0 und reinstalliert/downgradet beim nächsten `brew upgrade` gnadenlos zurück.
- Umgekehrt: Apps im Nix-Store bekommen ihre Updates **nur** über flake/Rebuild – und ihre in-App-Update-Checks werden abgeschaltet (siehe nächster Abschnitt).

## Auto-Updates & Admin-Rechte

### Warum die Apps keine Updates installieren können

Grundproblem: Apps im Nix-Store sind read-only – ihre in-App-Updater können nicht schreiben und melden dann genau die nervigen „Update verfügbar, konnte aber nicht installiert werden“-Meldungen.

**Lösung – Aufteilung nach Updater-Fähigkeit:**

1. **Apps mit gutem Eigen-Updater → bewusst NICHT aus nixpkgs installieren, sondern Homebrew (cask) – der Eigen-Updater der App ist der PRIMÄRE Update-Mechanismus:**
   - Cask-Apps landen in `/Applications` (user-schreibbar) → Sparkle-ähnliche Updater funktionieren dort nativ, ohne Admin-Rechte.
   - Für die Replication/Re-Setup-Fähigkeit führen wir die Brewfile mit (`brew bundle`), aber die Version kommt vom App-Updater, nicht aus dem Repo.
   - Wichtig: die casks mit Eigen-Updater (`auto_updates`-Flag) aus dem `brew upgrade`-Lauf ausnehmen (siehe Regel oben – sonst kämpfen zwei Updater gegeneinander).
   - `brew bundle check` / Setup-Replication betrachtet die Brewfile dann als „App-Liste“, nicht als „Versions-Pinning“ – bei einem frischen Re-Setup wird halt die aktuellste Version der App installiert (einmalig von Hand gemeldet, danach übernimmt wieder der App-Updater).
2. **Apps, die im Nix-Store bleiben (systemnah, CLI, libs): in-App-Nags gezielt abschalten** – pro App das Update-Check-Feature deaktivieren (z. B. Firefox `appupdate.disable`, VS Code `update.mode: "none"`), damit keine toten „Update verfügbar“-Meldungen mehr kommen.
3. **Updates für diese Nix-Store-Apps laufen über flake/Rebuild** – d. h. das Update-Problem wird an die System-/User-Update-Mechanik (siehe Trigger-Matrix) delegiert, nicht an die App.

### Wann genau Admin-Rechte (root/sudo) benötigt werden – und wann nicht

Unterscheide **drei Rechte-Bedarfe**, die bisher vermischt werden:

| Aktion | Benötigt root? Warum? | Kann ohne Admin? |
|---|---|---|
| `nix build` / `nix flake update` (nur Evaluieren/Bauen in Store-Pfade) | Nein | Ja – der Store-Schreibzugriff läuft über den Nix-Daemon (nixbld-User) |
| Substituter/Cache hinzufügen (z. B. neuer binary cache) | Nur, wenn User nicht in `trusted-users` – sonst Daemon fragt nach root/sudo | Ja – siehe Trust-Settings unten |
| `home-manager switch` | Nein | Ja – schreibt nur ins User-Profil |
| `brew install/upgrade` incl. casks | Nein (Apple Silicon: `/opt/homebrew` gehört dem User) | Ja – Ausnahme: einzelne casks mit echten `pkg`-Installern fragen trotzdem nach Admin-Passwort; prüfen und nach Möglichkeit casks ohne `sudo_required` wählen |
| `nixos-rebuild switch` / `darwin-rebuild switch` | **Ja** – schreibt `/nix/var/nix/profiles/system`, wechselt `/run/current-system`, startet/stoppt systemd-/launchd-Services | Nur indirekt: either der User wird `trusted-user` + die *einmalige* Unit-Operation wird delegiert, oder die Operation läuft als Root-Timer |
| macOS-System-Updates (`softwareupdate`) | Ja | Separat behandeln (nicht Ziel dieses Plans – gehört zum OS, nicht zur Paketverwaltung) |

**Kern-Erkenntnis:** Der häufigste Grund für „Admin nötig“ ist nicht der Rebuild selbst, sondern ein **fehl- oder altkonfiguriertes Nix-Setup**: nicht-trustete User, die den Daemon für Store-Operationen um Erlaubnis (d. h. sudo) bitten müssen, bzw. der Rebuild-Workflow, der sich `sudo` in den Vordergrund holt, obwohl der eigentliche privilegierte Schritt (Units neu laden) delegiert werden kann.

### Konkrete Anpassung der Admin-Rechte

1. **Trust-Settings für Nix setzen (einmalig, flake-managed):**
   - NixOS: `nix.settings.trusted-users = [ "root" "@wheel" "<user>" ];`
   - nix-darwin: analog über `nix.settings` (bzw. `nix.extraOptions` als Fallback).
   - **Effekt:** `nix flake update`, `nix build`, `nix profile`, `home-manager` brauchen danach **kein sudo** und keine „Accept-Substituter“-Interaktion mehr – der User-Slot ist vom Daemon akzeptiert.
2. **Interaktiver Rebuild ohne Passwort-Eingabe (Option A – sudoers-Delegation):**
   - Die Einzige wirklich root-Bedürftige Operation ist der finale `switch`. Diese允许 wir dem User gezielt über einen sudoers-Drop-in:
     ```
     <user> ALL=(root) NOPASSWD: /run/current-system/sw/bin/nixos-rebuild, /run/current-system/sw/bin/darwin-rebuild
     ```
   - Dadurch: Rebuilds sind weiterhin manuell/interaktiv möglich, aber **ohne Passwort-Prompt** – der User gewinnt keine beliebige Root-Macht, nur das eine Update-Kommando.
3. **Auto-Upgrade als Root-Timer (Option B – bevorzugt für Server/Alltagsmaschinen):**
   - NixOS: `system.autoUpgrade` mit `flake = github:…/setup#<host>` + `dates`/`randomizedDelay`.
   - darwin: analog per LaunchAgent/LaunchDaemon, der `darwin-rebuild switch --flake …` ausführt (LaunchDaemon → läuft als root → kein User-sudo nötig; einmalig admin-privilegiert zu installieren, danach nie wieder).
   - **Effekt:** Der **tägliche Update-Lauf** braucht vom User gar nichts mehr – der Trigger „PR gemerged“ reicht, der Rest passiert nachts.
4. **Homebrew bewusst user-owned halten:**
   - Auf Apple Silicon ist `/opt/homebrew` eh user-owned → kein sudo. Prüfen, dass kein Legacy-/Intel-Setup oder alte Gruppe-Owner (admin) mehr existiert.
   - Casks, deren Installer root verlangen, bewusst identifizieren und – wenn möglich – durch cask-Varianten ohne Installer oder durch nix-Pakete ersetzen.
5. **Was NICHT delegiert wird:** macOS-System-Updates bleiben bewusst manuell (oder eigener Timer mit Admin-Blessing) – sie sind kein Nix-Problem und gehören nicht in den Auto-Update-Lauf der Paketverwaltung.

### Kombiniertes Bild nach Anpassung

- **Kein Passwort-Prompt mehr** für: flake update, build, home-manager, brew, täglicher Auto-Upgrade.
- **Passwort-Prompt (einmalig/selten)** nur noch für: macOS-OS-Updates, Reparaturen am Store, einmalige Daemon-Konfigurationsänderungen (dann aber flake-managed und im Rebuild enthalten).
- **Problem 3 ist damit strukturell gelöst**, nicht nur umgangen.

## Maßnahmen (konkret)

1. **Inventur: Welche Apps brauchen den Eigen-Updater?** Liste der aus nixpkgs installierten GUI-Apps → Kategorien „Eigen-Updater-gut“ / „Nix-Store-bleibt“. Die „Eigen-Updater-gut“-Apps wandern in die Brewfile.
2. **Brewfile als App-Liste** ins Repo; `brew upgrade`-Lauf so konfigurieren, dass casks mit `auto_updates` ausgenommen werden.
3. **In-App-Update-Checks** für verbleibende Nix-Store-Apps pro App abschalten (Firefox, VS Code, …) – direkt in der jeweiligen home-manager/darwin-Config.
4. **Renovate einrichten** – ein PR pro Input, wöchentlich + on-release; Branch-Protection damit Updates nur über getestete PRs landen.
5. **Update-Session-Konvention:** `nix flake update` nie „im Vorbeigehen“ – eigene Update-Session mit `nix build` aller Hosts *vor* `switch`:
   ```
   nix flake lock --update-input nixpkgs
   nix build .#nixosConfigurations.<host>.config.system.build.toplevel
   nixos-rebuild test --flake .#<host>   # erst 'test', dann bewusst 'switch'
   ```
6. **PR-Workflow für `flake.lock`** als Standard; Updates kommen nur als Renovate-PR, der gegen den getesteten Stand läuft – lokale Hotfixes können nicht mehr versehentlich im nächsten Update-Commit untergehen.
7. **Fix-Konvention:** Fixes immer als Commit ins Repo, nie lokal lassen. Direkt nach dem Fix committen/pushen. Damit der Fix nicht „ewig“ mitschleppt:
   - Jeder Workaround-Eintrag in `docs/` bekommt ein Comment-Format mit **Ursache, Datum, betroffene Stelle (Datei/Zeile) und Ablaufkriterium** („kann entfernt werden, sobald nixpkgs > 24.05“ o. ä.).
   - Im Code selbst markieren wir die Stelle mit einem einheitlichen Kommentar-Tag, z. B. `# TEMP-FIX(<datum>): <grund> – siehe docs/workarounds.md` – so lässt sich per `grep` alle temporären Fixes finden.
   - Bei jedem nixpkgs-Release-Sprung (oder als eigener Punkt in der Update-Session) **explizit prüfen: ist der Grund für den Fix noch vorhanden?** Wenn nein → Fix entfernen, Docs-Eintrag als „erledigt“ archivieren (Datum + Version).
   - Regelmäßiger Review (z. B. quartalsweise): `grep TEMP-FIX` über das Repo, Liste gegen die aktuellen nixpkgs-Versionen abgleichen, abgelaufene Fixes rausschmeißen.
8. **Pro-Input-Updates statt Bulk-Update:** einen Input nach dem anderen (nixpkgs separat von home-manager, dieser separat von sonstigen Deps) – schränkt den Blast Radius ein und macht Reverts einfach.
9. **Release-Notes-Check als fester Bestandteil der Update-Session:** nach jedem nixpkgs-Sprung (23.11 → 24.05 …) die Release-Notes auf module-Breaking-Changes prüfen – das ist der häufigste Ursachenblock für „flake update kaputt“.
10. **Admin-Rechte-Anpassung umsetzen** (siehe Abschnitt oben): `nix.settings.trusted-users`, sudoers-Drop-in für Rebuild-Kommandos, `system.autoUpgrade`/LaunchDaemon als Root-Timer – Ziel: kein Passwort-Prompt im normalen Update-Fluss.

## Priorisierung

| # | Maßnahme | Aufwand | Nutzen |
|---|---|---|---|
| 1 | Admin-Rechte anpassen (trust-users, sudoers, autoUpgrade) | mittel | sofortiges Ende der Passwort-Frusts (Problem 3) |
| 2 | Renovate + PR-Workflow | gering–mittel | strukturiert Updates, verhindert Fix-Verlust (Probleme 4, 5) |

---

# Implementierungsplan (final, alle Entscheidungen geklärt)

Stand: 26.09.2026 · Status: bereit zur Implementierung

## Getroffene Entscheidungen

| Frage | Entscheidung |
|---|---|
| nixpkgs-Kanal | **Bleibt `nixos-unstable`** (Problem 1 wird über Brew-Eigen-Updater gelöst, nicht über Kanalwechsel) |
| CI/Renovate | **Läuft bereits** (`renovate.json`: lockFileMaintenance freitags, automerge). Flake-/Code-Updates laufen über Renovate + GitHub Actions |
| Cask-Migration | **Alle** GUI-Apps aus nixpkgs migrieren; Casks sind ok |
| claude-code | **Nach brew formula** migrieren (Terminal-Tool, kein GUI-Autoupdate, aber `brew upgrade` deckt es ab) |
| teleport | **Komplett entfernen** (unbenutzt; Cask-Varianten würden GUI + sudo-Pkg-Installer mitbringen) |
| zoom | **Bleibt in Nix** — der Cask ist ein .pkg-Installer mit Admin-Bedarf, genau was vermieden werden soll. Updates laufen weiter über flake/renovate |
| RustRover | **Cask `rustrover`** (auto_updates), nixpkgs-Paket raus, **JetBrains Toolbox wird deinstalliert** — IntelliJ IDEA + RustRover laufen danach rein über Cask |
| brew upgrade Trigger (Arbeits-Mac) | **Feste Zeiten Di + Do 10:00** + Catch-up beim Login, falls Mac zur Zeit x aus war |
| brew upgrade Trigger (privater Mac) | **Bei Login mit Mindestabstand 3 Tagen** (läuft nur, wenn letzter Lauf > 3 Tage her ist) |
| Verzögerung | **Login + Random-Delay 5–15 Min**, damit der Mac erst benutzbar ist |
| Benachrichtigung | **macOS-Notification**, nur bei Aktion (Updates installiert) oder Fehler (Exit-Code != 0) — Ruhe bei 0 Updates |
| Cleanup | `brew cleanup` läuft **mit** jedem Upgrade-Lauf |
| TEMP-FIX-Workflow | **Passt** wie geplant (Tag + `docs/workarounds.md` + quartalsweiser Review) |

## App-Migrationsliste (konkret)

| App | aktuell | Ziel | Grund |
|---|---|---|---|
| discord | `pkgs.discord` | Cask `discord` (auto_updates) | Eigenupdater übernimmt |
| google-chrome | `pkgs.google-chrome` | Cask `google-chrome` (auto_updates) | Chrome-Eigenupdate |
| insomnia | `pkgs.insomnia` | Cask `insomnia` (auto_updates) | hinkt in nixpkgs hinterher |
| opencode-desktop | `pkgs.opencode-desktop` | Cask `opencode-desktop` (auto_updates) | schnell-lebendig |
| t3-code | `pkgs.t3code` | Cask `t3-code` (auto_updates) | nixpkgs hinkt hinterher (0.0.40 vs 0.0.42) |
| zed-editor | `pkgs.zed-editor` | Cask `zed` (auto_updates) | Eigenupdater |
| rust-rover | `pkgs.jetbrains.rust-rover` | Cask `rustrover` (auto_updates) | Toolbox fliegt raus, Cask übernimmt |
| claude-code | `pkgs.claude-code` (Profil) | Brew formula `claude-code` | Updates via brew-Lauf statt flake |
| teleport | `pkgs.teleport` | **entfernen** | unbenutzt |
| zoom | `pkgs.zoom-us` | **bleibt** | Cask wäre .pkg mit sudo-Bedarf |
| intellij-idea | Cask (bereits) | bleibt | schon Cask |
| hardware-casks (displaylink, stream-deck, focusrite, macfuse, logi, logitune) | Cask | bleibt | unverändert |

## Implementierungsschritte (Reihenfolge)

### 1. Admin-Rechte (Problem 3, kleinster Aufwand, direkter Effekt)
- `modules/system/base.nix`: `trusted-users` prüfen — `@admin` + User sind bereits gesetzt; **Verifizieren, ob der macOS-Nix-Daemon das tatsächlich respektiert** (Determinate vs. Multi-User-Setup auf dem Dienst-Mac).
- Falls sudo beim Rebuild weiterhin promptet: sudoers-Drop-in via nix-darwin `environment.etc`/`launchd`-Mechanik für genau `darwin-rebuild`/`nixos-rebuild`.
- Ziel: kein Passwort-Prompt für flake update, build, home-manager, brew, Auto-Upgrade.

### 2. App-Migration (Probleme 1 + 2)
- `modules/apps/*.nix` umstellen: die 6 Migrations-Apps auf `homebrew.casks`, `rust-rover.nix` analog, `claude-code` aus `development.nix` in Brew-Formula-Liste (über `homebrew.brews`), `teleport.nix` löschen und aus `hosts/darwin/Maxs-MacBook-Pro/default.nix` entfernen.
- Einmalig manuell: `brew install` der neuen Casks, JetBrains Toolbox deinstallieren, `nix store gc` für die entfernten Store-Pfade.

### 3. Brew-Update-LaunchAgent (beide Macs, unterschiedlich)
- **Gemeinsames Modul** `modules/system/darwin-brew-update.nix` mit:
  - Script: `brew outdated` → `brew upgrade` → `brew cleanup`. ⚠️ Kein `brew update` und kein Extra-Flag nötig: die Taps sind store-gepinnt (`mutableTaps = false`), neue Versionen kommen über Renovate-Flake-Bumps + Rebuild, und ein natives `brew upgrade` schließt Casks mit `auto_updates` von selbst aus (`--greedy` darf niemals dazu).
  - `osascript`-Notification: nur wenn (a) > 0 Updates installiert oder (b) Exit != 0 (Nachricht „Update fehlgeschlagen“).
  - Lock-Dir gegen Doppelläufe, Log unter `~/Library/Logs/brew-autoupdate.log`, Timestamp unter `~/Library/Application Support/brew-autoupdate/last-run`.
- **Arbeits-Mac (`kopf3-NB-26`):** StartCalendarInterval Di + Do 10:00; zusätzlich bei Login ein Catch-up-Check (läuft nur, wenn letzter Lauf > 3 Tage her ist — gleiche Sperre wie beim privaten Mac, schützt vor Doppelläufen).
- **Privater Mac (`Maxs-MacBook-Pro`):** LaunchAgent RunAtLoad mit Mindestabstand 3 Tage (Timestamp-Datei), Random-Delay 5–15 Min.
- Umsetzung des Delays: `sleep $((RANDOM % 600 + 300))` im Script vor dem eigentlichen Lauf.

### 4. Flake-Update-Pipeline (Probleme 4 + 6) — läuft bereits, nur verifizieren
- Renovate lockFileMaintenance (Freitag früh, automerge) + `nix build`-CI pro Host bestätigen; bei Bedarf packageRules für single-Input-PRs ergänzen.

### 5. Fix-Registry (Problem 5)
- `docs/workarounds.md` anlegen (Tabelle: Datum, Stelle, Ursache, Ablaufkriterium, Status), Tag-Konvention `# TEMP-FIX(<datum>):` im Code, quartalsweiser `grep TEMP-FIX`-Review als Checkbox in der Update-Session.

## Offene Punkte für die Implementierung selbst

- Wie der Dienst-Mac mit Admin-Antrag und Nix-Daemon konkret interagiert (trusted-users wirkt nur, wenn der Daemon-User trustet — auf gesperrten Firmengeräten ggf. nicht deklarierbar). Status-Check: privater Mac verifiziert (2026-09-27, User in `admin`, `/opt/homebrew/*` user-owned); **kopf3-NB-26 manuell prüfen** (`id -Gn | grep -q admin`, `ls -ld /opt/homebrew/bin`, LaunchAgent nicht per MDM blockiert).
- Ob `darwin-rebuild` automatisiert (LaunchDaemon) oder bewusst manuell bleibt — laut Entscheidungen: manuell, nur Brew läuft automatisch.
