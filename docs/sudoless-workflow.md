# Arbeits-Mac ohne sudo – `hm-switch`

Wie man auf `kopf3-NB-26` (admin-by-request) Konfiguration ändert, Tools
hinzufügt und Updates holt, **ohne** `sudo darwin-rebuild`. Funktioniert
genauso auf dem privaten Mac. Hintergrund zu den Update-Spuren:
[update-runbook.md](update-runbook.md).

## Das Prinzip

Home-Manager (HM) ist in die `darwinConfigurations` eingebettet. Alles, was
unter `home-manager.users.maxvissing.*` steht, gehört dem User und lässt sich
als User aktivieren. `hm-switch` baut genau das HM-Aktivierungspaket, das auch
`darwin-rebuild` aktivieren würde, und startet es ohne sudo
(`modules/system/darwin-hm-switch.nix`).

```
Repo ändern ──► hm-switch ──► ~/.config, ~/Library/LaunchAgents, Nix-User-Profil
                 (kein sudo)
```

`hm-switch` und der echte Rebuild sind austauschbar und lassen sich in
beliebiger Reihenfolge abwechseln. Der Rebuild macht den HM-Teil einfach mit.

## Einmalig: ein Admin-Rebuild

`hm-switch` kommt selbst über die Konfiguration und existiert erst nach einem
Rebuild, der es enthält. Beim nächsten admin-by-request-Fenster also:

```bash
cd ~/projects/private/setup
git pull
sudo darwin-rebuild switch --flake .#kopf3-NB-26
```

Das zieht außerdem die `brew-autoupdate`-Agents von `/Library/LaunchAgents`
(root) nach `~/Library/LaunchAgents` um. Bis dahin können beide Versionen
existieren; der gemeinsame Lock verhindert parallele Läufe.

Bis zu diesem Rebuild geht derselbe Ablauf von Hand:

```bash
$(nix build --no-link --print-out-paths \
  .#darwinConfigurations.kopf3-NB-26.config.home-manager.users.maxvissing.home.activationPackage)/activate \
  --driver-version 1
```

## Der Grundablauf

```bash
cd ~/projects/private/setup     # oder ein Worktree, dann: hm-switch --flake .
# … Datei ändern …
hm-switch --dry-run             # optional: zeigt, was passieren würde
hm-switch
```

- Baut `kopf3-NB-26` aus `~/projects/private/setup`. Anderen Pfad mit
  `--flake <pfad>` oder `HM_SWITCH_FLAKE`, anderen Host mit `--host`.
- Ohne neue Pakete dauert es etwa 15–20 Sekunden, fast nur Auswertung.
- ⚠️ **Flakes sehen nur Dateien, die Git kennt.** Eine neue Datei vorher mit
  `git add -N <datei>` anmelden, sonst meldet `nix` sie als fehlend.
- Committen ist für `hm-switch` nicht nötig, ein dirty tree reicht. Damit die
  Änderung beim nächsten Rebuild nicht verschwindet, gehört sie trotzdem
  irgendwann committet.
- `--dry-run` ist nicht vollständig nebenwirkungsfrei: Einige Aktivierungs-
  schritte (bat-Cache, RustRover-Stdlib-Cache) laufen trotzdem. Sie schreiben
  nur Caches.

**Zurückrollen:** Es gibt keine eigenen HM-Generationen (die hängen an den
System-Generationen). Stattdessen die Änderung im Repo zurücknehmen
(`git revert` / `git checkout <commit> -- <datei>`) und erneut `hm-switch`.

## Rezepte

### zsh-Konfiguration ändern

| Was | Wo |
|---|---|
| Aliase, Optionen, Funktionen, oh-my-zsh (beide Macs) | `modules/profiles/core-user/zsh.nix` |
| Nur Arbeits-Mac (z. B. Env-Variablen aus sops) | `modules/profiles/work.nix` |
| Nur dieser Host | `hosts/darwin/kopf3-NB-26/default.nix`, z. B. `home-manager.users.maxvissing.programs.zsh.initContent = lib.mkAfter ''…'';` |

```bash
hm-switch && exec zsh
```

`exec zsh` lädt die neue `.zshrc` in der laufenden Shell. **Neue
`home.sessionVariables`** greifen erst in einem *neuen Terminal-Fenster*: HM
setzt ein Guard-Flag, damit die Variablen pro Session nur einmal geladen
werden, und `exec zsh` erbt dieses Flag.

Zum schnellen Ausprobieren erst direkt in der Shell testen (`alias x=…`,
Funktion einfügen) und das Ergebnis dann nach Nix übertragen. Die Dateien
unter `~/.config/zsh` sind schreibgeschützte Symlinks in den Store; dort
editieren geht nicht.

### opencode-Konfiguration ändern

Alles in `modules/apps/opencode/`:

| Was | Wo |
|---|---|
| `opencode.json`-Einstellungen, Permissions, LSP | `default.nix` → `programs.opencode.settings` |
| Agents, Commands, Skills (beide Profile) | `global/agents/`, `global/commands/`, `global/skills/<name>/SKILL.md` |
| Nur Arbeits- bzw. Privat-Repos | `profiles/work/…`, `profiles/personal/…` |
| Globale Regeln (`AGENTS.md`) | `global/context.md` |

Dann `hm-switch` und die opencode-Session neu starten. Neue Dateien, z. B.
ein neuer Skill, brauchen vorher `git add -N`.

`profiles/*` werden direkt aus dem Store referenziert (`OPENCODE_CONFIG_DIR`).
Auch dort wirkt eine Änderung erst nach `hm-switch`.

Zum Experimentieren ohne Switch das **Projekt-Verzeichnis `.opencode/`** im
jeweiligen Repo nutzen (`.opencode/opencode.json`, `.opencode/agent/`,
`.opencode/command/`). Es hat Vorrang vor der globalen Konfiguration. Was
sich bewährt, wandert danach nach `modules/apps/opencode/`. `OPENCODE_CONFIG`
von Hand zu setzen bringt nichts: Der Wrapper überschreibt es pro
Verzeichnis.

### Neues CLI-Tool

**Nur mal kurz benutzen** – keine Konfiguration, kein Switch:

```bash
nix shell nixpkgs#httpie      # Tool in einer temporären Shell
nix run nixpkgs#cowsay -- hi  # einmal ausführen
```

**Dauerhaft:** in `home.packages` eintragen, dann `hm-switch`.

| Für | Wo |
|---|---|
| beide Macs | passendes Profil, z. B. `modules/profiles/development.nix` |
| nur Arbeits-Mac | `hosts/darwin/kopf3-NB-26/default.nix` → `home-manager.users.maxvissing.home.packages` |

Paketnamen findet `nix search nixpkgs <name>`. Danach liegt das Tool sofort
im `PATH` des User-Profils, auch in der laufenden Shell (ggf. `rehash`).

⚠️ **Nicht** `environment.systemPackages` benutzen: Das ist System-Ebene und
braucht den Rebuild.

### Neue GUI-App

Die Reihenfolge ist zugleich die Empfehlung:

1. **Gibt es die App in nixpkgs mit macOS-Build?** Dann wie ein CLI-Tool in
   `home.packages` (Beispiel: `modules/apps/zoom.nix`), Muster: eigene Datei
   `modules/apps/<app>.nix`, im Host importiert. Nach `hm-switch` liegt sie
   unter `~/Applications/Home Manager Apps/`, komplett ohne sudo. Updates
   kommen über Renovate (nixpkgs-Bump) + `hm-switch`.

2. **Nur als Homebrew-Cask?** Deklarieren *und* direkt installieren:

   ```nix
   # modules/apps/<app>.nix
   {homebrew.casks = ["<app>"];}
   ```

   ```bash
   brew install --cask <app>     # jetzt, als User, kein sudo
   ```

   Die Deklaration wird erst beim nächsten Admin-Rebuild wirksam; bis dahin
   ist die App einfach schon da, und der Rebuild findet nichts mehr zu tun.
   ⚠️ **Beides ist nötig:** `homebrew.onActivation.cleanup = "uninstall"`
   entfernt beim Rebuild jeden Cask, der *nicht* deklariert ist. Eine nur
   per `brew install` installierte App ist danach weg.

   Grenzen:
   - Casks mit `.pkg`-Installer (Treiber, Systemerweiterungen) verlangen
     immer ein Admin-Passwort. Die bleiben beim Rebuild.
   - Casks schreiben nach `/Applications`. Ob der User dort schreiben darf,
     zeigt `ls -ld /Applications` (Gruppe `admin`) zusammen mit `id -Gn`.

3. **Weder noch** (DMG, App Store): von Hand installieren. Das ist dann
   bewusst nicht deklarativ.

Formeln (`brew install <formula>`) funktionieren genauso wie Casks:
`homebrew.brews` deklarieren und direkt installieren.

### Updates holen

| Was | Ohne sudo | Braucht Rebuild |
|---|---|---|
| Nix-Pakete in `home.packages` | `git pull && hm-switch` nach dem Renovate-Merge | – |
| Brew-Casks/-Formeln, deren neue Version der Tap schon kennt | automatisch (LaunchAgent Di/Do) oder `brew upgrade` | – |
| Brew-Versionen, die erst ein neuer Tap-Stand bringt | – | ja: die Taps sind Store-gepinnt, nur der Rebuild biegt sie um |
| Apps mit eigenem Updater (Spur 1) | die App selbst | – |
| `environment.systemPackages` (git, vim, curl, rsync) | – | ja |

Für das Nix-Update ohne Renovate:

```bash
nix flake update nixpkgs && hm-switch   # danach flake.lock committen
```

### macOS-Einstellungen

Reine User-Einstellungen gehören in
`home-manager.users.maxvissing.targets.darwin.defaults.<domain>` und gehen
dann per `hm-switch`. Die Locale-/Format-Einstellungen in
`modules/system/darwin.nix` liegen bereits dort. Manche Einstellungen
greifen erst nach erneutem Anmelden.

Dock, Finder, Trackpad und die übrigen Einstellungen stehen noch in
`system.defaults` und brauchen den Rebuild.

## Was weiterhin den Admin-Rebuild braucht

- `system.defaults`, `power`, `networking`, `security.pam`
- `environment.systemPackages`, alles unter `/etc`, nix-daemon-Settings
  (`nix.settings`, Caches, `trusted-users`)
- nix-darwin `launchd.daemons` / `launchd.user.agents`
- Homebrew: Tap-Umbiegen (neue Versionen für Spur 2), `brew bundle` inkl.
  Cleanup, `.pkg`-Casks

**Faustregel:** Steht es unter `home-manager.users.…`, reicht `hm-switch`.
Steht es auf oberster Ebene eines Moduls, braucht es den Rebuild.

## Wenn etwas hakt

- **`Existing file '…' is in the way`**: Eine Datei, die HM verwalten will,
  existiert schon als echte Datei. Prüfen, sichern, löschen, dann erneut
  `hm-switch`.
- **`error: path '…' does not exist`** bzw. eine fehlende Datei: Die Datei
  ist Git noch nicht bekannt → `git add -N`.
- **`Oops, Nix failed to install your new Home Manager profile`**: Ein von
  Hand per `nix profile install` installiertes Paket kollidiert.
  `nix profile list`, das Paket entfernen, erneut `hm-switch`.
- **Änderung „wirkt nicht“**: neue Shell bzw. neues Terminal (Session-
  Variablen), App neu starten, oder es ist eine System-Option (siehe oben).
- **`hm-switch: command not found`**: Der einmalige Admin-Rebuild fehlt
  noch → Handbefehl aus „Einmalig“ verwenden.
