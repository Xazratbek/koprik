# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ko'prik is a free, open-source alternative to CrossOver: a SwiftUI macOS app (Apple silicon, macOS 26+) that runs Windows programs and games through Wine. All logic lives in the `KoprikKit` Swift package; the `Koprik` app target is a thin UI layer over it, and `koprik` is a CLI built from the same package. The app ships no Wine: engines are downloaded on first run (the default is `frankea/winecx-gptk`, Wine 11.19 with CrossOver 26.3's open patches plus DXMT, DXVK and MoltenVK), so everything runs x86_64 under Rosetta.

Project docs in `docs/` are in Uzbek: `REJA.md` is the phased plan, `SINOV.md` the test log with measurements and every bug found so far (B1-B18), `KOMPONENTLAR.md` the component research, `RELIZ.md` the release process. `CROSSOVER.md` is research on CrossOver itself. Read `SINOV.md` before changing launching, graphics or Steam handling: most of the non-obvious rules in the code exist because of a bug recorded there.

## Commands

```sh
# Library and CLI (no Xcode project needed)
cd KoprikKit
swift build
swift test                                   # all tests (Swift Testing)
swift test --filter GraphicsTests            # one suite
swift test --filter "StoreTests/parsesLegendaryLibrary"   # one test
.build/debug/koprik --help                   # doctor, engine, bottle, run, stop, programs, ps, kill, env

# App (project.yml is the source of truth; Koprik.xcodeproj is generated and git-ignored)
xcodegen generate
xcodebuild build -project Koprik.xcodeproj -scheme Koprik -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build/DerivedData
scripts/install.sh                           # Release build into /Applications/Koprik.app
scripts/release.sh <version> <build> [download-url-base]   # .dmg, Sparkle signature, appcast.xml entry

# Strings: edit scripts/translations.tsv (English key, Uzbek, Russian), then
python3 scripts/build-strings.py [keys.txt]  # regenerates Koprik/Resources/Localizable.xcstrings

# Own engine build (hours; normally run by .github/workflows/build-engine.yml)
scripts/build-engine.sh build/engine
```

Tests use a fake engine (`Tests/KoprikKitTests/Support.swift`: a shell-script `wine64` that logs its calls) and need neither Wine nor Rosetta. One test reads a real `notepad.exe` only if an engine is installed. Real behaviour is checked by hand with the CLI against bottles in `~/Library/Application Support/Koprik` (override the root with `KOPRIK_HOME`).

## Architecture

**Data on disk** (`AppPaths`): `Engines/<id>/` (Wine tree + `engine.json`), `Bottles/<uuid>/` (`bottle.json`, `prefix/` = WINEPREFIX, `programs/<id>.json`, `snapshots/`, `logs/`), `Templates/<engine>-<winver>/prefix` (a ready prefix cloned to create bottles in under a second), `Components/` (store tools), `Stores/` (legendary config, GOG auth), `Cache/`. Everything is JSON via `JSONFile`; there is no database. Stores are actors (`EngineStore`, `BottleStore`, `ProgramStore`, `EpicStore`, `GOGStore`).

**Launching** always goes through `Launcher.launch` (app and CLI alike). It:
1. Resolves `LaunchSettings` layers: engine defaults → bottle → program → one-off overrides. Every field is optional; a layer only overrides what it sets.
2. Decides the graphics backend (`Graphics.decide`, plus launcher rules): store launchers and Chromium/Electron apps go to DXVK (they draw blank on DXMT and wined3d); otherwise "Auto" reads the PE import table (`PEFile`).
3. Places backend DLLs. `system32` serves the whole bottle, so while a bottle is running (Steam needs DXVK) a program with a different backend gets its DLLs copied next to its executable instead (`Graphics.prepareLocal`, tracked by a `.koprik-graphics` marker so the game's own DLLs are never touched).
4. For Steam games, starts the client if needed (`-silent`, DXVK, overlay disabled), waits for "Logged On" in Steam's `connection_log.txt`, then runs the game's own executable with `SteamAppId` rather than `steam.exe -applaunch` (which would give the game Steam's environment). Epic and GOG games are started from what legendary / the `goggame-<id>.info` file report.
5. Builds the environment in `WineEnvironment.build`, a pure function (unit-tested). Notable defaults: MSync on CrossOver-derived engines, `powershell.exe=d` (Wine's stub exits 0 and breaks electron-builder installers), Steam/CEF sandbox variables, frame cap and MetalFX through `DXMT_CONFIG` / a generated `dxvk.conf`.

**Processes.** `WineRunner` and `ProcessRunner` use `posix_spawn` + `waitpid` on dedicated threads, never Foundation's `Process` (its `waitUntilExit` hung inside the CLI). Wine is spawned with `POSIX_SPAWN_SETSID` so closing a terminal does not kill the bottle. Output goes to log files, not pipes, because `wineserver` inherits descriptors. `BottleActivity.isRunning` connects to the wineserver socket (the socket file outlives a dead server). `Launcher.stopAll` also kills orphaned Wine processes by their working directory. Helper processes (`taskkill`, `reg`, winetricks) must use `Launcher.baseSettings` so their sync mode matches the running server.

**Isolation** (`Isolation.swift`): a bottle with `isolation` set runs every Wine process under `sandbox-exec` with a Seatbelt profile built per bottle (home folder denied except the bottle, engine and a few Library folders; process-exec only inside the engine; no Apple Events; optionally no network). `WineRunner.forBottle` decides; always create runners through it for a bottle. Paths in the profile go through `realpath` because Seatbelt matches `/private/var/...`. Files opened from outside are copied into the bottle first. Untrusted files opened in the app default to the isolated "Sandbox" bottle.

**Links** (`LinkBridge`): URL schemes Windows programs register are read from `user.reg`/`system.reg`; per bottle an AppleScript applet in `~/Applications/Koprik/Links` claims them and forwards to `koprik://open-url/<bottle>/<link>`. The handler command is resolved from the registry and run directly, because Wine's `start` ignores per-user (HKCU) classes.

**Game Mode bundle** (`GameBundle`): each engine gets `Libraries/Wine/Koprik Game.app`, whose `Contents/MacOS` is an APFS clone of `lib/wine/x86_64-unix` with symlinks so Wine's relative paths still resolve. `Engine.wineBinary` prefers its loader, so every Windows process belongs to a bundle declaring `LSSupportsGameMode`. Rebuild it whenever the unix directory changes (GPTK import/removal does this).

**Programs** are discovered on every listing (Start Menu `.lnk` files via `ShellLink`, Steam `appmanifest_*.acf` via `VDF`, legendary's `installed.json`, GOG info files) and merged with the user's saved records; only programs the user changed get a file.

**App** (`Koprik/`): one window only (the user does not want secondary windows; settings are a sidebar page, not a separate window). `AppModel` (`@MainActor @Observable`, `AppModel.shared`) holds all state and actions; it polls running bottles every 2 s to show "Running" and book play time. Sheets are fine; new windows are not. Sparkle runs only in Release builds with `SUPublicEDKey` set (`UpdaterManager.isConfigured`); releases are signed with the Keychain key account `koprik`.

## Things that bite

- XcodeGen rewrites `.entitlements` files from `project.yml`: put entitlement keys under `entitlements.properties` there, or the file is emptied.
- Do not `codesign --deep` the app: it strips the Quick Look extension's sandbox entitlement and macOS then refuses to load it. Sign the `.appex` with its entitlements first, then the app.
- Build products left in DerivedData get registered with Launch Services and can answer `open -a Koprik` or `koprik://` links (a half-built copy without Sparkle dies silently). `scripts/install.sh` and `release.sh` unregister them.
- macOS shows Windows windows under the owner name "Ko'prik Game" (the bundle), not "wine".
- Kernel-level anti-cheat cannot work under Wine; the app warns from AreWeAntiCheatYet data instead of trying.
