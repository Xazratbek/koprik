# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ko'prik is a free, open-source alternative to CrossOver: a SwiftUI macOS app (Apple silicon, macOS 26+) that runs Windows programs and games through Wine. All logic lives in the `KoprikKit` Swift package; the `Koprik` app target is a thin UI layer over it, and `koprik` is a CLI built from the same package. The app ships no Wine: engines are downloaded on first run (the default is `frankea/winecx-gptk`, Wine 11.19 with CrossOver 26.3's open patches plus DXMT, DXVK and MoltenVK), so everything runs x86_64 under Rosetta.

Project docs in `docs/` are in Uzbek: `REJA.md` is the phased plan, `SINOV.md` the test log with measurements and every bug found so far (B1-B31), `KOMPONENTLAR.md` the component research, `RELIZ.md` the release process. `CROSSOVER.md` is research on CrossOver itself. Read `SINOV.md` before changing launching, graphics or Steam handling: most of the non-obvious rules in the code exist because of a bug recorded there.

## Commands

```sh
# Library and CLI (no Xcode project needed)
cd KoprikKit
swift build
swift test                                   # all tests (Swift Testing)
swift test --filter GraphicsTests            # one suite
swift test --filter "StoreTests/parsesLegendaryLibrary"   # one test
.build/debug/koprik --help                   # doctor, engine, bottle, run, stop, programs, ps, kill, env, links
.build/debug/koprik run <bottle> <exe> --metal-hud --detach   # try a program; --backend, --language, --env K=V

# App (project.yml is the source of truth; Koprik.xcodeproj is generated and git-ignored)
xcodegen generate
xcodebuild build -project Koprik.xcodeproj -scheme Koprik -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build/DerivedData
scripts/install.sh                           # Release build into /Applications/Koprik.app
scripts/release.sh <version> <build> [download-url-base]   # .dmg, Sparkle signature, appcast.xml entry

# Strings: edit scripts/translations.tsv (English key, Uzbek, Russian), then
python3 scripts/build-strings.py [keys.txt]  # regenerates Koprik/Resources/Localizable.xcstrings

# Own engine build (about 1.5 h on GitHub's macos-15-intel runner; publishes release engine-v<version>)
gh workflow run build-engine.yml --repo Xazratbek/koprik -f version=<x.y.z> -f winecx_commit=<sha> -f runner=macos-15-intel
scripts/build-engine.sh build/engine         # same build locally
koprik engine install koprik                 # installs the newest engine-v* release
```

Tests use a fake engine (`Tests/KoprikKitTests/Support.swift`: a shell-script `wine64` that logs its calls) and need neither Wine nor Rosetta. One test reads a real `notepad.exe` only if an engine is installed. Real behaviour is checked by hand with the CLI against bottles in `~/Library/Application Support/Koprik` (override the root with `KOPRIK_HOME`).

## Architecture

**Data on disk** (`AppPaths`): `Engines/<id>/` (Wine tree + `engine.json`), `Bottles/<uuid>/` (`bottle.json`, `prefix/` = WINEPREFIX, `programs/<id>.json`, `snapshots/`, `logs/`), `Templates/<engine>-<winver>/prefix` (a ready prefix cloned to create bottles in under a second), `Components/` (store tools), `Stores/` (legendary config, GOG auth), `Cache/`. Everything is JSON via `JSONFile`; there is no database. Stores are actors (`EngineStore`, `BottleStore`, `ProgramStore`, `EpicStore`, `GOGStore`).

**Launching** always goes through `Launcher.launch` (app and CLI alike). It:
1. Resolves `LaunchSettings` layers: engine defaults → bottle → program → one-off overrides. Every field is optional; a layer only overrides what it sets.
2. Decides the graphics backend (`Graphics.decide`, plus launcher rules): store launchers and Chromium/Electron apps go to DXVK (they draw blank on DXMT and wined3d) and Chromium apps also get `--in-process-gpu` (`chromiumArguments`; GPU IPC through wineserver made input lag by up to a second); otherwise "Auto" reads the PE import table (`PEFile`). D3DMetal runs 64-bit programs only, so 32-bit ones fall back to DXMT even when D3DMetal is requested. With GPTK imported, other backends need `Graphics.overridesAvoidingD3DMetal` (d3d12 disabled, Wine's own dxgi), or Chromium's GPU process crashes.
3. Applies the bottle's display mode once per change (`applyDisplayMode`, marker `.display-mode`): exclusive full screen (`CaptureDisplaysForFullscreen`) and Retina. Retina is "Automatic": on for ordinary programs, off for Direct3D/OpenGL games, which otherwise pick the panel's pixel size and get a window twice the screen.
4. Places backend DLLs. `system32` serves the whole bottle, so while a bottle is running (Steam needs DXVK) a program with a different backend gets its DLLs copied next to its executable instead (`Graphics.prepareLocal`, tracked by a `.koprik-graphics` marker so the game's own DLLs are never touched).
5. For Steam games, starts the client if needed (`-silent`, DXVK, overlay disabled), waits for "Logged On" in Steam's `connection_log.txt`, then runs the game's own executable with `SteamAppId` rather than `steam.exe -applaunch` (which would give the game Steam's environment). Epic and GOG games are started from what legendary / the `goggame-<id>.info` file report.
6. Builds the environment in `WineEnvironment.build`, a pure function (unit-tested). `language` sets LANG/LC_ALL, which is how non-Unicode programs get the right ANSI code page. Notable defaults: MSync on CrossOver-derived engines, `powershell.exe=d` (Wine's stub exits 0 and breaks electron-builder installers), Steam/CEF sandbox variables, frame cap and MetalFX through `DXMT_CONFIG` / a generated `dxvk.conf`.

**Processes.** `WineRunner` and `ProcessRunner` use `posix_spawn` + `waitpid` on dedicated threads, never Foundation's `Process` (its `waitUntilExit` hung inside the CLI). Wine is spawned with `POSIX_SPAWN_SETSID` so closing a terminal does not kill the bottle. Output goes to log files, not pipes, because `wineserver` inherits descriptors. `BottleActivity.isRunning` connects to the wineserver socket (the socket file outlives a dead server). `Launcher.stopAll` also kills orphaned Wine processes by their working directory. Helper processes (`taskkill`, `reg`, winetricks) must use `Launcher.baseSettings` so their sync mode matches the running server.

**Isolation** (`Isolation.swift`): a bottle with `isolation` set runs every Wine process under `sandbox-exec` with a Seatbelt profile built per bottle (home folder denied except the bottle, engine and a few Library folders; process-exec only inside the engine; no Apple Events; optionally no network). `WineRunner.forBottle` decides; always create runners through it for a bottle. Paths in the profile go through `realpath` because Seatbelt matches `/private/var/...`. Files opened from outside are copied into the bottle first (`importIntoBottle`): the whole folder when the file sits in a folder of its own, so installers find their data archives, but never catch-all folders like Downloads; on APFS the copy is a clone. Untrusted files opened in the app default to the isolated "Sandbox" bottle.

**Links** (`LinkBridge`): URL schemes Windows programs register are read from `user.reg`/`system.reg`; per bottle an AppleScript applet in `~/Applications/Koprik/Links` claims them and forwards to `koprik://open-url/<bottle>/<link>`. The handler command is resolved from the registry and run directly, because Wine's `start` ignores per-user (HKCU) classes.

**Game Mode bundle** (`GameBundle`): each engine gets `Libraries/Wine/Koprik Game.app`, whose `Contents/MacOS` is an APFS clone of `lib/wine/x86_64-unix` with symlinks so Wine's relative paths still resolve. `Engine.wineBinary` prefers its loader, so every Windows process belongs to a bundle declaring `LSSupportsGameMode`. Rebuild it whenever the unix directory changes (GPTK import/removal does this).

**Programs** are discovered on every listing (Start Menu and Desktop `.lnk` files via `ShellLink`, names stripped of installer verbs like "Start game", Steam `appmanifest_*.acf` via `VDF`, legendary's `installed.json`, GOG info files) and merged with the user's saved records; only programs the user changed get a file.

**Engines.** The default is the prebuilt `frankea/winecx-gptk`, because Apple's D3DMetal (imported from the user's GPTK download, `GPTKImporter`) has only been imported there. Ko'prik's own build (`scripts/build-engine.sh`, `koprik-<version>`) is the same Wine source plus DXMT, DXVK, Wine Mono and Gecko; without Mono/Gecko every new bottle stops at a hidden "Wine Mono Installer" dialog.

**App** (`Koprik/`): one window only (the user does not want secondary windows; settings are a sidebar page, not a separate window). `AppModel` (`@MainActor @Observable`, `AppModel.shared`) holds all state and actions; it polls running bottles every 2 s to show "Running" and book play time. Sheets are fine; new windows are not. Sparkle runs only in Release builds with `SUPublicEDKey` set (`UpdaterManager.isConfigured`); releases are signed with the Keychain key account `koprik`.

## Things that bite

- XcodeGen rewrites `.entitlements` files from `project.yml`: put entitlement keys under `entitlements.properties` there, or the file is emptied.
- Do not `codesign --deep` the app: it strips the Quick Look extension's sandbox entitlement and macOS then refuses to load it. Sign the `.appex` with its entitlements first, then the app.
- Build products left in DerivedData get registered with Launch Services and can answer `open -a Koprik` or `koprik://` links (a half-built copy without Sparkle dies silently). `scripts/install.sh` and `release.sh` unregister them.
- macOS shows Windows windows under the owner name "Ko'prik Game" (the bundle), not "wine".
- Kernel-level anti-cheat cannot work under Wine; the app warns from AreWeAntiCheatYet data instead of trying.
- Testing games by hand: DirectInput games ignore keys sent through System Events; post HID-level `CGEvent`s (held ~150 ms) instead. Read FPS from the Metal HUD (`--metal-hud`); "Composited" vs "Direct" and "Game Mode" there show whether full screen and Game Mode took effect (Game Mode is off whenever the game is not frontmost).
- A dialog Wine opens can land behind other windows or on another display; when a bottle seems stuck, list its windows (owner "Ko'prik Game") before assuming a hang.
