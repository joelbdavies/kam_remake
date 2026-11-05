# Native macOS upstream-branch validation

## Mission-script callback fix (November 2026)

A TSK4 regression revealed that PascalScript's FPC ARM64 native method trampoline is empty: events were linked, but never executed. Earlier smoke tests checked for errors and consistent state without proving callback effects, so those tests did not establish working mission scripting.

FPC callbacks now enter the interpreter directly. This covers ordinary events, mutable group-split parameters and script console commands. The absent-float sentinel is explicitly `Single`, avoiding FPC's inferred `Double` comparison. The save layout is unchanged.

The fix was tested on Apple M4/macOS Sequoia 15.8.1 in both variants:

- Upstream branch (`b2d65f039`): eight event/TSK4 checks; all 34 retail mission smoke tests; 1,008 matching save/resume snapshots; collections, keyboard, mouse and cursor checks; one simulated hour with 60 autosaves and all five rotations reloaded.
- Player branch (`cb6c50544`): the same eight event/TSK4 checks; five version-policy checks; 1,008 matching save/resume snapshots; both original r16406 tutorial saves loaded, advanced 100 ticks and resaved/reloaded with identical state and retained headers.
- A TSK4 save from the previous build loaded and unlocked the woodcutter after completing the school and quarry. The unlock survived another save/reload.
- The rebuilt player app passed signature verification and launched through menu initialization against disposable data. The previous packaged app was retained locally.

Existing saves are not automatically reinitialized: replaying missed startup handlers can duplicate units or change mission state. Restart a mission for its full initialization. In TSK4, a newly completed quarry triggers the woodcutter unlock if a school exists. Old recordings may replay differently now that callbacks execute; prior cross-build replay results on the player branch describe the older executable.

Evidence: `assets.local/tsk4-woodcutter/`. The synthetic fixture in `probes/fixtures/mission-events.script` is distributable; retail assets and save fixtures remain excluded from Git.

## Upstream branch validation

Retested in November 2026 on an Apple M4 running macOS Sequoia 15.8.1. This branch is `codex/macos-upstream`, based on the native port at `57a91a1788eb743c0ebd6e4bf2b0d99bac17ed2c` and upstream `11cd5fd0e10ae6e8cfce27493564e49cd8ee11d5` (r16421).

## Save policy

This branch uses upstream's build-specific save policy. The old native r16406 allowlist, retained legacy save/replay headers, per-game simulation version and legacy animal-steering path have been removed. `KM_GameInfo`, `KM_GameParams` and `KM_UnitActionSteer` match upstream exactly. Save/replay headers must match `GAME_REVISION`; saves and replay commands always write the current revision. The normal unsupported-save debug override remains disabled in tests. Early header validation is retained so mismatched revisions fail before gameplay or replay commands are read.

Campaign progress remains version-independent. The `codex/macos-fpc-mvp` branch retains support for the player's older native saves.

## Build identity

- The full game and all ten probes used for this branch's tests compile with the pinned Free Pascal toolchain and Cocoa LCL library. No Lazarus IDE was used.
- Tested executable: `assets.local/tsk4-woodcutter/upstream-KaM_Remake` (archived before building the player variant).
- Executable SHA-256: `ab01f3232e4bdaf79d133bc43124d5f760b65c9463fdf383030b7f461ab9fe1f`.
- The player app is packaged separately from `codex/macos-fpc-mvp`; its manifest and startup evidence are under `assets.local/tsk4-woodcutter/`.

## Automated checks

Upstream tests used freshly staged disposable data under `assets.local/tsk4-woodcutter/data`. The later player-branch compatibility checks added copies of two original tutorial saves; original player files were not modified. Evidence is under `assets.local/tsk4-woodcutter/`.

| Area | Result and evidence |
| --- | --- |
| Revision policy and upstream regressions | Six checks pass: settings XML replacement, a soldier passing a pacing animal, a no-AI replay, current-revision save/replay output, and rejection of both r16406 and an unknown revision. `regressions/upstream.log`. |
| Current save/resume | TSK2 and TPR3 each run to tick 6,000, comparing uninterrupted play with a save at tick 1,500 and fresh-process reload. All 1,008 component snapshots match, with identical subsequent commands. `regressions/results.json`. |
| Save collections | All 13 equipment-order, scripted-sound-removal and checkpoint-boundary cases pass. `regressions/collections.log`. |
| Keyboard input | Callback checks and both native Cocoa responder paths pass, including editing, printable text, navigation, repeats and focus changes. `regressions/keyboard.log` and `regressions/cocoa-events.log`. |
| Mouse input | All four monitor-edge, remote-event and scrolling-gate groups pass. `regressions/mouse.log`. |
| Cursor images | All 28 actual native cursor images match source colors, dimensions and opacity. Transparent pixels are fully clear. The player previously confirmed that the gray square is gone on the compatibility-enabled build containing the same cursor fix. `regressions/cursor.log`. |
| Retail campaigns | All 34 TSK/TPR missions pass startup, rendering, 600 simulated ticks, save/reload/resume, and forced-victory unlock/progress checks using seed 4. These are smoke tests, not complete mission playthroughs. `campaigns/results.json`. |
| Fresh tutorial saves and autosaves | One simulated hour plus one scheduling-boundary tick passes. All 60 minute autosaves are confirmed in the game log. Four checkpoints survive repeated named saves and overwrite; all five rotated slots reload at ticks 36,000, 35,400, 34,800, 34,200 and 33,600 and resume. `autosave.log` and `autosave-results.json`. |

The fresh tutorial probe processes tick 36,001 because the game schedules each autosave before incrementing the tick. This lets it verify the save for minute 60 and assert the exact tick in every rotated slot.

## Scope and previous validation

The port targets native Apple Silicon single-player campaigns on macOS 15 or newer. Tahoe, Intel Macs, multiplayer, Windows save/replay interoperability, map editing and legacy video playback have not been validated. The existing Windows/Delphi code paths are retained, but no Windows compiler is available here. The development build uses `DBG_SKIP_SECURE_AUTH`.

Graphics, BASS/OpenAL audio, scripting, data staging, earlier campaign tests and manual playtesting are documented in the [player branch's validation record](https://github.com/joelbdavies/kam_remake/blob/57a91a1788eb743c0ebd6e4bf2b0d99bac17ed2c/platform/macos/VALIDATION.md). Its cross-revision save compatibility results do not apply to this branch. Proprietary assets, test saves, generated binaries and local evidence are excluded from Git.
