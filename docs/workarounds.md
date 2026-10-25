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

Spalte **Upstream**: das Issue/der PR, dessen Merge den Fix ablaufen lässt.
Beim Review dort den Status prüfen, nicht nur den eigenen Build.

| Seit | Stelle | Ursache | Ablaufkriterium | Upstream | Status |
|---|---|---|---|---|---|
| 2026-09-27 | `modules/system/base.nix` (extra-substituters, nix-community.cachix.org) | `sops-install-secrets` kommt aus dem sops-nix-Flake, nie über cache.nixos.org gebaut → jeder Host kompiliert es sonst aus Quelle (~20 min auf ionos, 2026-08-06) | sops-nix liefert das Tool über nixpkgs (dann baut cache.nixos.org es); prüfen bei jedem nixpkgs-Release-Sprung | [Mic92/sops-nix#835](https://github.com/Mic92/sops-nix/issues/835) „Package in nixpkgs?" (offen; Mic92 nennt vorkompilierte Binaries als Grund dafür). Verwandt: [#908](https://github.com/Mic92/sops-nix/issues/908) (Tests abschaltbar) | offen – geprüft 2026-10-25 (nixpkgs `3ec6363`): noch nicht in nixpkgs |
| 2026-10-15 | `modules/profiles/development.nix` (`pulumi-bun`, eigener `vendorHash`) | pulumi 3.268.0 hat `pulumi-language-bun` eine externe `tool`-Abhängigkeit (go-ruleguard/dsl) gegeben; nixpkgs baut es weiter mit `vendorHash = null` → „inconsistent vendoring“ | nixpkgs setzt einen `vendorHash` für `pulumi-bun` (Override entfernen, Build ohne prüfen); spätestens beim nächsten pulumi-Bump | Kein eigenes Issue. Sichtbar in [NixOS/nixpkgs#577415](https://github.com/NixOS/nixpkgs/pull/577415) (pulumi 3.268 → 3.271, offen): nixpkgs-review vom 2026-10-25 meldet `pulumiPackages.pulumi-bun` ❌; der PR fasst `pulumi-bun` nicht an | offen – geprüft 2026-10-25: pulumi 3.268.0, `vendorHash` weiter `null`, auch auf master |
| 2026-09-27 | `modules/apps/rust-rover.nix` (`rustToolchain` postBuild, sysroot-Pin) | Wrapped `pkgs.rustc` meldet einen quelllosen Store-Pfad als Sysroot → IDEs finden keine stdlib („corrupted" copy) | Wrapper meldet brauchbaren Sysroot, oder IDE verlässt sich nicht mehr auf `rustc --print sysroot`; bei jedem rustc-Bump prüfen | [NixOS/nixpkgs#393680](https://github.com/NixOS/nixpkgs/issues/393680) „rustc: add opt-in argument to include `rust-src` component in `pkgs.rustc`" (offen seit 2025-03). Verwandt: [#70238](https://github.com/NixOS/nixpkgs/issues/70238) | offen – geprüft 2026-10-25 (rustc 1.99.0): Sysroot ohne `lib/rustlib/src/rust` |
| 2026-09-27 | `modules/apps/rust-rover.nix` (`rustStdlibCacheFix`) | JetBrains kopiert stdlib-Caches mit Verzeichnisattributen → Kopie des read-only Store-Baums bleibt read-only (AccessDeniedException) | JetBrains behält Attribute nicht mehr bei, oder nixpkgs liefert keine read-only Bäume; bei jedem rustc-/RustRover-Bump neu bewerten | [RUST-16842](https://youtrack.jetbrains.com/issue/RUST-16842) „Plugin fails to work with readonly rust stdlib tree" (offen seit 2025-01, exakt unser Fehlerbild). Verwandt: [RUST-7912](https://youtrack.jetbrains.com/issue/RUST-7912) (Nix store, offen) | offen – YouTrack-Status bei jedem RustRover-Bump prüfen |
| 2026-10-25 | `modules/profiles/development.nix` (`nixpkgs.overlays`, `fabric` aus unreleased Commit) | nixpkgs hat `invoke` auf 3.x gehoben, kein fabric-Release unterstützt das → `fabric` als broken markiert, `azure-cli` evaluiert nicht. Nur `broken` zu erlauben reicht nicht (Runtime-Deps-Check: `invoke<3.0`) | [NixOS/nixpkgs#576874](https://github.com/NixOS/nixpkgs/pull/576874) (oder ein anderer fabric-Fix) ist in unserem nixpkgs. ⚠️ Issue [#575989](https://github.com/NixOS/nixpkgs/issues/575989) ist versehentlich geschlossen, nicht behoben | [PR #576874](https://github.com/NixOS/nixpkgs/pull/576874) (offen) | offen |

## Archiv (abgelaufene Fixes)

| Seit | Bis | Stelle | Ursache | Wie behoben |
|---|---|---|---|---|
| 2026-09-27 | 2026-09-27 | `modules/apps/zed.nix` | `CLAUDE_CODE_EXECUTABLE` zeigte auf `pkgs.claude-code`, das nach Brew migriert wurde | Pfad zeigt auf `/opt/homebrew/bin/claude` (Migration, kein temporärer Fix mehr) |
| 2026-09-27 | 2026-10-25 | `modules/profiles/development.nix` (`statix.overrideAttrs doCheck=false`) | statix-eigene Check-Phase schlug auf damaligem nixpkgs-Stand fehl | nixpkgs `3ec6363` (statix 0.5.8-unstable-2026-07-17): ungepatchtes statix liegt auf cache.nixos.org, Hydra-Check also grün |
| ? | 2026-10-25 | `modules/apps/opencode/default.nix` (meridian `preBunNodeModulesInstallPhase`, war ohne TEMP-FIX-Tag) | bun2nix füllte den Offline-Cache mit `cp -r` → Symlinks in den read-only Store → `bun install --linker=hoisted` scheiterte mit `AccessDenied` | meridian `9d94a35` (1.85.0) baut ohne Override |
| 2026-10-25 | 2026-10-25 | `modules/profiles/core-user/nvf/languages.nix` (`jls` mit eigenem `mvnHash`) | nvf folgte per `inputs.nixpkgs.follows` unserem nixpkgs; maven 3.9.16 → 3.10.0 → nvfs gepinnter `mvnHash` für jls passte nicht mehr. Upstream: überschriebenes nixpkgs ist bei nvf „unsupported" ([NotAShelf/nvf#1844](https://github.com/NotAShelf/nvf/issues/1844)) | Kein Fix, sondern Konfig: `follows` für nvf in `flake.nix` entfernt. nvf nutzt sein eigenes gepinntes nixpkgs; `nix flake update nvf` übernimmt nvfs Pin (geprüft: `6774f7bc`). ⚠️ Beim Entfernen von `follows` löst `nix flake lock` frisch auf – danach einmal `nix flake update nvf` |
