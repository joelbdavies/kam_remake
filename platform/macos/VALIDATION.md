# Native macOS upstream-branch validation

Tested on 30 October 2026 on an Apple M4 running macOS Sequoia 15.8.1. This branch is `codex/macos-upstream`, based on the native port at `57a91a1788eb743c0ebd6e4bf2b0d99bac17ed2c` and upstream `11cd5fd0e10ae6e8cfce27493564e49cd8ee11d5` (r16421).

## Save policy

This branch uses upstream's build-specific save policy. The old native r16406 allowlist, retained legacy save/replay headers, per-game simulation version and legacy animal-steering path have been removed. `KM_GameInfo`, `KM_GameParams` and `KM_UnitActionSteer` match upstream exactly. Save/replay headers must match `GAME_REVISION`; saves and replay commands always write the current revision. The normal unsupported-save debug override remains disabled in tests. Early header validation is retained so mismatched revisions fail before gameplay or replay commands are read.

Campaign progress remains version-independent. The `codex/macos-fpc-mvp` branch retains support for the player's older native saves.

## Build identity

- The full game and all nine probes used for this branch's tests compile with the pinned Free Pascal toolchain and Cocoa LCL library. No Lazarus IDE was used.
- Tested executable: `assets.local/build/macos/bin/KaM_Remake`.
- Executable SHA-256: `a844296deae9910a23acb87d185d299fc8067fe4125993178345089ad6ed7ae3`.
- This branch was tested directly, without replacing the packaged player app. The existing six-file `assets.local/build/macos/KaM Remake.app` still matches its compatibility-enabled build manifest, with executable SHA-256 `191d30ff2bed0df4424344b50fcde8999f4ddbdd0e25d9cc04e2e85af140d9c7`.

## Automated checks

All runs use freshly staged disposable data under `assets.local/upstream-no-compat/data`. No original player saves are used as fixtures or modified. Evidence is under `assets.local/upstream-no-compat/`.

| Area | Result and evidence |
| --- | --- |
| Revision policy and upstream regressions | Six checks pass: settings XML replacement, a soldier passing a pacing animal, a no-AI replay, current-revision save/replay output, and rejection of both r16406 and an unknown revision. `regressions/upstream.log`. |
| Current save/resume | TSK2 and TPR3 each run to tick 6,000, comparing uninterrupted play with a save at tick 1,500 and fresh-process reload. All 1,008 component snapshots match, with identical subsequent commands. `regressions/results.json`. |
| Save collections | All 13 equipment-order, scripted-sound-removal and checkpoint-boundary cases pass. `regressions/collections.log`. |
| Keyboard input | Callback checks and both native Cocoa responder paths pass, including editing, printable text, navigation, repeats and focus changes. `regressions/keyboard.log` and `regressions/cocoa-events.log`. |
| Mouse input | All four monitor-edge, remote-event and scrolling-gate groups pass. `regressions/mouse.log`. |
| Cursor images | All 28 actual native cursor images match source colors, dimensions and opacity. Transparent pixels are fully clear. The player previously confirmed that the gray square is gone on the compatibility-enabled build containing the same cursor fix. `regressions/cursor.log`. |
| Retail campaigns | All 34 TSK/TPR missions pass startup, rendering, 600 simulated ticks, save/reload/resume, and forced-victory unlock/progress checks using seed 4. These are smoke tests, not complete mission playthroughs. `campaigns/results.json`. |
| Fresh tutorial saves and autosaves | One simulated hour plus one scheduling-boundary tick passes. All 60 minute autosaves are confirmed in the game log. Four checkpoints survive repeated named saves and overwrite; all five rotated slots reload at ticks 36,000, 35,400, 34,800, 34,200 and 33,600 and resume. `autosave-final.log` and `autosave-results.json`. |

The fresh tutorial probe processes tick 36,001 because the game schedules each autosave before incrementing the tick. This lets it verify the save for minute 60 and assert the exact tick in every rotated slot.

## Scope and previous validation

The port targets native Apple Silicon single-player campaigns on macOS 15 or newer. Tahoe, Intel Macs, multiplayer, Windows save/replay interoperability, map editing and legacy video playback have not been validated. The existing Windows/Delphi code paths are retained, but no Windows compiler is available here. The development build uses `DBG_SKIP_SECURE_AUTH`.

Graphics, BASS/OpenAL audio, scripting, data staging, earlier campaign tests and manual playtesting are documented in the [player branch's validation record](https://github.com/joelbdavies/kam_remake/blob/57a91a1788eb743c0ebd6e4bf2b0d99bac17ed2c/platform/macos/VALIDATION.md). Its cross-revision save compatibility results do not apply to this branch. Proprietary assets, test saves, generated binaries and local evidence are excluded from Git.
