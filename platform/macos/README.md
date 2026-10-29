# Native Apple Silicon MVP

This port builds the current game with Free Pascal and LCL's Cocoa widget library. It does not require the Lazarus IDE, Wine or Rosetta. The deployment target is macOS Sequoia 15.0; runtime validation uses an Apple M4 on Sequoia 15.8.1.

See [validation results](VALIDATION.md) for the tested build, campaign coverage and remaining limits.

## Build

Install Xcode command-line tools (or select a full Xcode installation), Python 3, native Free Pascal **3.2.2** (`brew install fpc`) and `innoextract` (`brew install innoextract`). Run from the repository root:

```sh
platform/macos/bootstrap.sh
platform/macos/build.sh
platform/macos/package.sh
```

The app is written to `assets.local/build/macos/KaM Remake.app`. `bootstrap.sh` builds the compiler and Cocoa libraries from pinned sources, downloads and checks BASS, and initializes the pinned PascalScript submodule. Logs are in `assets.local/toolchain/logs/`. The first bootstrap takes several minutes.

| Dependency | Tested revision |
| --- | --- |
| Free Pascal 3.3.1 development source | `363f31341dd584f2ab897423457717b463f702b5` |
| Lazarus 4.8 / Cocoa LCL | `62c14a4d18c81f222127d42ce9b89b922c63fcbf` |
| PascalScript | `ce8590dd7b9cf48fd0e446731989603e09e239b8` |
| BASS 2.4.18.3 macOS archive SHA-256 | `dfadd6238896b02b144b2870655fb9ee2445fc84d5c00f7e1c56faf9343ce59c` |

Free Pascal 3.3.1 is needed for function references used by the current game. PascalScript patches are applied to a generated build copy; the submodule remains unchanged. The compiler uses the selected macOS SDK explicitly and disables chained fixups for compatibility with current Apple linkers. The main build cleans game unit outputs because this compiler revision is unreliable when incrementally rebuilding circular unit dependencies.

## Locally owned game assets

The executable requires both the original game data and Remake resources. Obtain the original game legally. Download Remake resources from the [official download page](https://www.kamremake.com/download/), following the upstream [compilation instructions](https://github.com/reyandme/kam_remake/wiki/ProjectCompilation). No Windows executable needs to run.

The tested installers are:

| Installer | SHA-256 |
| --- | --- |
| GOG TPR 1.60, build 67017 | `32cb26303b9585410f7567679963c6ae6ac919039063461ff7e110a83e40289a` |
| KaM Remake beta r16397 | `9980a414f4adbe3806c322de5a74068861857968b3b5ddd4ec1d84987208cd9e` |

Extract the installers, then overlay original data, Remake resources, and checkout resources in that order:

```sh
innoextract --extract --exclude-temp --include data \
  --output-dir assets.local/gog-tpr-1.60 \
  "$HOME/Downloads/setup_knights_and_merchants_-_the_peasants_rebellion_1.60_(67017).exe"
innoextract --extract --exclude-temp \
  --output-dir assets.local/remake-r16397 \
  assets.local/downloads/KaM-Remake-Beta-r16397.exe
python3 platform/macos/stage-data.py \
  --gog-data assets.local/gog-tpr-1.60/data \
  --remake-data assets.local/remake-r16397/app \
  --output assets.local/runtime-data
platform/macos/install-data.sh assets.local/runtime-data
```

`stage-data.py` requires a new or empty output directory. It verifies all 34 retail mission maps, scripts, data and English narration files, normalizes the sprite directory name, and records file hashes. The tested extraction contains 10,621 asset files. Repeating the overlay into a fresh directory reproduced every recorded asset hash.

The player installation lives in `~/Library/Application Support/KaM Remake/`, including assets, settings, logs, saves and campaign progress. `install-data.sh` copies only missing assets and preserves existing files. Developers can use `KAM_DATA_DIR` to select an isolated data directory.

The app bundles its arm64 BASS library and uses system frameworks for Cocoa, OpenGL and OpenAL. Packaging also converts the upstream KaM Remake artwork into a macOS Dock/Finder icon. The app can be moved independently of the checkout. It is signed ad hoc for local use, not notarized for public distribution. Keep the proprietary assets local; they are neither committed nor bundled with the executable.

After installing the data, move `KaM Remake.app` to `~/Applications` and launch it normally. Select **Single Player → Campaigns** for the retail missions. Use the green window button for fullscreen and Command-Q to quit. Save names accept ordinary keyboard entry; in-game editing shortcuts retain the game's Control-key bindings.

## Existing native saves

The r16421 build accepts saves made by the original native r16406 MVP without enabling the unsupported-save debug option. Existing games retain their r16406 save, replay and checkpoint headers and original animal-movement timing. This keeps their recorded history deterministic and retains the original native save layout. Newly started games use r16421 and the upstream fix for animals blocking diagonal movement. The application version still reports r16421 when an older game is loaded.

Compatibility is restricted to these two audited native revisions. Other revisions and Windows saves are not covered. This is not a general save-format bypass, and future upstream updates must recheck both serialization and simulation compatibility.

## Verification

Build probes after the main game build:

```sh
for probe in Graphics Audio Script Data Campaign; do
  KAM_PASCAL_ENTRY="platform/macos/probes/KM_Mac${probe}Probe.lpr" \
    platform/macos/build.sh
done
```

The campaign runner needs a logged-in graphical session and a disposable staged data directory. It writes saves and advances campaign progress in that directory, so it rejects the default player installation:

```sh
python3 platform/macos/test-campaigns.py --data-dir assets.local/runtime-data
```

Each retail mission is started with its actual script, simulated for 600 ticks, rendered to PNG, saved, reloaded and resumed. The test compares script state byte for byte and checks player, unit and house counts. It then exercises the game's victory/exit path and reloads campaign progress into a fresh object to verify completion and next-mission unlocking. This is not a complete playthrough or a test of every mission's natural victory condition. Results, logs and screenshots are under `assets.local/campaign-tests/`.

For a longer simulation or a specific regression:

```sh
python3 platform/macos/test-campaigns.py --data-dir assets.local/runtime-data \
  --output assets.local/campaign-long-tests --missions TSK2 TPR3 --ticks 6000 --seed 4
```

`--seed` fixes the game's RNG seed for reproduction. Unattended battle missions can end in defeat before a long tick target; the probe reports the tick, game result and paused state in that case. This is a failed tick-target check, not necessarily a runtime fault.

For the save/resume, collection-boundary and input regressions, build these additional probes after the game and stage disposable data:

```sh
for probe in Trajectory Collection Keyboard CocoaEvent Mouse Compatibility; do
  KAM_PASCAL_ENTRY="platform/macos/probes/KM_Mac${probe}Probe.lpr" \
    platform/macos/build.sh
done
python3 platform/macos/stage-data.py \
  --gog-data assets.local/gog-tpr-1.60/data \
  --remake-data assets.local/remake-r16397/app \
  --output assets.local/regression-data
python3 platform/macos/test-regressions.py \
  --data-dir assets.local/regression-data \
  --output assets.local/regression-results
```

Use a fresh output directory for each run. The runner requires disposable data inside this checkout's `assets.local` directory and writes logs plus `results.json`. Use `--only trajectory`, `--only collections`, `--only keyboard`, `--only mouse` or `--only upstream` to select a suite.

- Save/resume: TSK2 and TPR3 each run continuously to tick 6,000, then repeat with a save at tick 1,500 and resume in a fresh process. Both runs receive the same road, recruitment and formation commands where applicable. The suite compares 504 binary snapshots per mission, covering RNG/IDs, terrain, all players' resources/units/jobs/orders/AI, pathfinding, projectiles, script state, scripted sounds and custom resources. UI timing and save headers are excluded.
- Collections: actual pending AI equipment orders and scripted sound-removal requests are saved and reloaded at counts 0, 1, 2 and 8. References and remaining acknowledgements must survive and complete. Live-game checkpoint scheduling is checked before, at and after limits 0, 1, 2, 30 and 60; large collections are prefilled just below the limit before crossing real scheduled boundaries.
- Keyboard: callback checks cover editing/navigation keys, all 95 printable ASCII characters, F1-F12, shortcut combinations and repeated keys. A second probe dispatches events through the actual Cocoa application with both the window's text-input responder and the OpenGL view focused. Test-only method observers verify that editing/navigation/function keys are consumed before native command processing; printable characters must still arrive exactly once. Native controls retain their input, and focus changes must release held camera keys. Modifier semantics are also checked through the form because synthetic events do not replace macOS's current hardware modifier state. A listener should still confirm that no warning bell is audible during ordinary play.

- Mouse: checks camera movement at all four monitor edges outside an inset game window, stale events rejected by the game, remote event coordinates inside the render area, right/bottom boundary exclusion, keyboard scrolling and inactive/disabled scrolling. The probe injects process-local Cocoa cursor queries and LCL activation messages; it restores the native method and never moves the user's real pointer.
- Upstream integration: exercises replacement of the settings XML before updating hotkeys, a soldier walking past a diagonally pacing animal, replaying a game with no AI, and rejection of unknown revisions or mismatched save/replay companions.

To test original native saves, copy their complete folders (including `.bas`, `.rpl` and any `.spt` files) into `Saves/` in disposable staged data. The compatibility runner checks normal Load-menu eligibility, resumed simulation, repeated serialization and checkpoint preservation. It can also replay an original save and its continued copy from their base state and restore an original checkpoint:

```sh
python3 platform/macos/test-compatibility.py \
  --data-dir assets.local/legacy-data --output assets.local/legacy-results \
  --saves 'Town Tutorial2' 'Town Tutorial4' \
  --replay 'Town Tutorial4' --replay-tick 36458
```

The save names and replay tick above refer to local test fixtures; substitute your own originals. No player saves are distributed in the repository.

If a previous r16406 trajectory run and its original save fixtures are available, compare the upgraded executable against those recorded component snapshots:

```sh
python3 platform/macos/test-regressions.py \
  --data-dir assets.local/legacy-data --output assets.local/legacy-trajectories \
  --only trajectory --legacy-baseline assets.local/previous-r16406-results
```

This mode only resumes the existing fixtures; it does not replace them with newly generated r16421 saves. The default cut/end ticks and missions must match the earlier run.

Other probes cover Cocoa/OpenGL drawing and pixel readback, BASS/OpenAL playback, PascalScript's ARM64 host-call ABI, and XML/Base64/PNG/file operations. The data probe also exercises replay checkpoint serialization with zero, one, two and four checkpoints. Their command-line arguments are documented in each probe's usage error. Audio playback progress proves the backend is running; it does not substitute for a listener checking the selected output device.

`KM_MacSaveInputProbe` reproduces the reported tutorial regression. It requires copies of `Town Tutorial2` and `Town Tutorial4` in the `Saves` folder of a disposable staged data directory under `assets.local`. It loads the former, runs the latter for another simulated hour, verifies repeated named saves and all five autosave slots, and checks the Cocoa arrow-key message path. It rejects the normal player data location. Build it after the game, then run:

```sh
KAM_PASCAL_ENTRY=platform/macos/probes/KM_MacSaveInputProbe.lpr platform/macos/build.sh
KAM_DATA_DIR="$PWD/assets.local/save-input-regression-data" \
  assets.local/build/macos/bin/KM_MacSaveInputProbe
```

For a fresh progression test, stage a new data directory before running the suite. Reusing test data with completed missions still tests simulation and save/load, but cannot independently prove that completion changed from false to true. Runtime startup regenerates `data/sfx/speech.eng/count.dat` when the cached game revision differs; this is expected and does not modify the source installers.

## Scope and limitations

The acceptance target is native single-player retail campaigns, including graphics, mouse/keyboard control, music, sound, scripting, progress and native save/load. Multiplayer authentication, network compatibility, Intel Macs, Windows save/replay compatibility, the map editor and legacy cutscene video playback are outside this MVP. The build uses `DBG_SKIP_SECURE_AUTH`; the existing online menu is not supported by this build.

OpenGL/OpenAL are deprecated macOS frameworks. They work on the tested Sequoia host; this port does not replace them with Metal, and Tahoe has not been tested. The existing Delphi/Windows branches are retained, but no Windows compiler is available for regression compilation here. Native saves should be kept separate from Windows saves.
