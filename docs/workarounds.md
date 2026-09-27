# Fix-Registry – temporäre Workarounds

Konvention (docs/update-strategy.md, Maßnahme 7): Jeder Workaround im Code
trägt einen Tag im Format

```
# TEMP-FIX(<datum>): <kurzer grund> - siehe docs/workarounds.md
```

und einen Eintrag in der Tabelle unten mit **Ursache** und **Ablaufkriterium**.
Fixes gehören nie nur lokal in den Tree: committen oder löschen.

**Quartalsweiser Review** (fester Punkt der Update-Session):

```bash
grep -rn "TEMP-FIX" modules/ hosts/ lib/
```

Jeden Eintrag gegen den aktuellen nixpkgs-Stand abgleichen: Ist das
Ablaufkriterium erfüllt → Fix entfernen, Eintrag archivieren (Datum + Version).
Nicht erfüllt → stehen lassen.

## Offene Fixes

| Seit | Stelle | Ursache | Ablaufkriterium | Status |
|---|---|---|---|---|
| 2026-09-27 | `modules/system/base.nix` (extra-substituters, nix-community.cachix.org) | `sops-install-secrets` kommt aus dem sops-nix-Flake, nie über cache.nixos.org gebaut → jeder Host kompiliert es sonst aus Quelle (~20 min auf ionos, 2026-08-06) | sops-nix liefert das Tool über nixpkgs (dann baut cache.nixos.org es); prüfen bei jedem nixpkgs-Release-Sprung | offen |
| 2026-09-27 | `modules/profiles/development.nix` (`statix.overrideAttrs doCheck=false`) | statix-eigene Check-Phase schlägt auf diesem nixpkgs-Stand fehl | Check-Phase ohne Override erneut probieren beim nächsten nixpkgs-Release-Sprung | offen |
| 2026-09-27 | `modules/apps/rust-rover.nix` (`rustToolchain` postBuild, sysroot-Pin) | Wrapped `pkgs.rustc` meldet einen quelllosen Store-Pfad als Sysroot → IDEs finden keine stdlib („corrupted" copy) | Wrapper meldet brauchbaren Sysroot, oder IDE verlässt sich nicht mehr auf `rustc --print sysroot`; bei jedem rustc-Bump prüfen | offen |
| 2026-09-27 | `modules/apps/rust-rover.nix` (`rustStdlibCacheFix`) | JetBrains kopiert stdlib-Caches mit Verzeichnisattributen → Kopie des read-only Store-Baums bleibt read-only (AccessDeniedException) | JetBrains behält Attribute nicht mehr bei, oder nixpkgs liefert keine read-only Bäume; bei jedem rustc-/RustRover-Bump neu bewerten | offen |

## Archiv (abgelaufene Fixes)

| Seit | Bis | Stelle | Ursache | Wie behoben |
|---|---|---|---|---|
| 2026-09-27 | 2026-09-27 | `modules/apps/zed.nix` | `CLAUDE_CODE_EXECUTABLE` zeigte auf `pkgs.claude-code`, das nach Brew migriert wurde | Pfad zeigt auf `/opt/homebrew/bin/claude` (Migration, kein temporärer Fix mehr) |
