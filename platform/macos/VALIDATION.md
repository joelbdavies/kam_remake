# Native macOS MVP validation

Tested on 29 October 2026 on an Apple M4 running macOS Sequoia 15.8.1. The deployment target is macOS 15.0. The executable and bundled BASS library are arm64 Mach-O binaries; neither Wine nor Rosetta is involved.

## Build identity

- Source base: `ddb0a6cccfdd031c4c4ec6358a70827aa1e4ad8c` (r16406), with the local changes on `codex/macos-fpc-mvp`.
- Current packaged executable SHA-256: `82de7e736cb2a40e9123e9a2ae4d9a25e6e682ac26d83811559606a50ddf8c76` (early handling of native editing commands; package includes Dock icon).
- Previous Dock-icon executable SHA-256: `cade881b466f89c11dbd658c0815fff4900cb60bc371011dcc4ba42bf1b82a24` (save collections and callback-level keyboard checks).
- Previous save/arrow-key executable SHA-256: `01a40c50c704d3afbff6b5e224fe6c4508201f5e71990e56f18a2a0c033c6479`.
- Original MVP executable SHA-256: `6359811c98406bcd960164d21f4fb9bc9b197fbd8d7c94d67b2ea1bcc047ab8f` (the full campaign acceptance suite below).
- Bundled arm64 BASS SHA-256: `c3ea762c11ad1ce92b197d40f33f7d9dfeed496a841a61d2d154803f2ff8be9a`.
- Free Pascal and Cocoa LCL were rebuilt from the revisions pinned in [README.md](README.md). No Lazarus IDE was used.
- The app passes `codesign --verify --deep --strict`. Its library search path is `@executable_path/../Frameworks`; other linked libraries are supplied by macOS.

The local app is installed at `~/Applications/KaM Remake.app`. All six installed bundle files, including the new icon, match the package byte for byte, and the installed signature verifies. Assets, settings, logs, saves and campaign progress live in `~/Library/Application Support/KaM Remake/`. Regression runs used disposable data directories, and all 39 player save files retained their SHA-256 hashes.

## Automated checks

| Area | Result and evidence |
| --- | --- |
| Retail missions | All 20 TSK and 14 TPR missions passed on the original MVP build. Each loaded its actual map and script, simulated 600 ticks, rendered a PNG, saved, reloaded and resumed for another 10 ticks. |
| Save fidelity | The game tick, player count, each player's unit and house counts, and serialized script state were preserved. Script state was compared byte for byte. |
| Campaign progress | The suite began without campaign progress. For each mission it invoked the game's victory/exit path, then loaded progress into a new object and verified completion and next-mission unlocking. |
| Graphics | Cocoa OpenGL context, legacy `GL_QUADS`, pixel readback and buffer swap passed. Driver: `OpenGL 2.1 Metal - 89.4`, renderer: `Apple M4`. Real mission screenshots were also visually inspected. |
| Audio | BASS played retail MP2 music and MP3 campaign narration, with playback positions advancing. An OpenAL sample entered playing and stopped states. An OGG sound decoded to 1,501,440 bytes of PCM at 44,100 Hz, stereo. |
| Scripting ABI | Nine host-call cases passed: signed integer, floating point, out parameters, Unicode return, record return, record argument, array return/ownership, array argument and empty array return. |
| Data operations | XML reload and escaping, Base64 and compressed stream round trips, PNG RGBA/alpha, Unicode file paths, copy, overwrite protection and rename passed. |
| Asset staging | Repeating the overlay into a fresh directory reproduced all 10,621 asset hashes. Game startup subsequently regenerated the expected revision-specific `data/sfx/speech.eng/count.dat` cache; all other recorded assets retained their hashes. |

The final 34-mission run completed in 157.94 seconds. Results are in `assets.local/campaign-acceptance-tests/results.json`, with a log and PNG for each mission. Backend evidence is in `assets.local/probe-{graphics,audio,script,data}-final.log`.

TSK2 also passed 6,000 ticks and the same save/load checks (`assets.local/campaign-long-tests/TSK2.log`). TSK20 passed a 6,001-tick run (`assets.local/campaign-long-diagnostic/TSK20.log`). An earlier unattended TSK20 attempt stopped short of the target; reproducing its seed, `530060440`, confirmed the normal `grDefeat` pause at tick 2,079, not a script or native crash (`assets.local/campaign-seed-diagnostic/TSK20.log`). The runner now accepts `--seed` and includes the paused/result state in tick-target failures.

TPR3 and TPR14 each passed 6,000 ticks, rendering, save/load, resumed simulation and victory/progress persistence with seed `4`. Evidence is in `assets.local/campaign-long-tpr-tests/`.

These tests exercise native game code and real retail resources. They do not constitute complete campaign playthroughs or prove every mission's natural victory condition. The progression test deliberately triggers victory after checking simulation and save/load.

## Save and arrow-key regression fixes

The first player session exposed an access violation when saving the second replay checkpoint at tick 17,999 (30 minutes). Autosaves then failed every minute. The FPC serializers passed a dynamic-array variable to `SortCustom`, whose untyped argument expects the first element's address. Sorting two or more entries corrupted the array pointer. The `.sav` file had already been written when the `.spt` checkpoint serialization failed, explaining why a reported failed save could still load.

The checkpoint, AI equipment-order and script-sound removal serializers now pass `keyArray[0]`, guarded by `Length(keyArray) > 1`. The existing save format and Delphi branches are unchanged.

- The data probe reproduced `EAccessViolation` with two checkpoints before the fix. After the fix, zero, one, two and four checkpoints passed ordered serialization, disk save/load, cursor/payload preservation and byte-identical repeated serialization.
- A disposable copy of `Town Tutorial2` loaded at tick 35,591 and saved/reloaded with identical script state and entity counts. Its missing checkpoint file does not prevent continuing the game; the old replay checkpoints cannot be recovered from that file.
- A copy of `Town Tutorial4` ran another 36,000 ticks (one simulated hour), ending at tick 72,458 with five checkpoints. All 60 minute autosaves succeeded. Two named saves and an overwrite reloaded with identical script/checkpoint bytes and entity counts. All five rotated autosaves loaded at ticks 72,000 through 69,600 and resumed simulation.
- The Cocoa form now consumes arrow-key events after forwarding and recording them. The native message regression verifies that all four arrows, including repeats, return a handled result to Cocoa, set the camera scroll flags, clear on release and clear on deactivation. Printable keys remain available for text entry.
- All 39 original player save files retained their SHA-256 hashes. The updated app was installed and its five files match the tested package; its signature verifies. The previous app is retained locally as `assets.local/KaM Remake-before-save-input-fix.app`.

Evidence: `assets.local/save-regression-{before,after}.log`, `assets.local/save-input-probe.log`, and `assets.local/save-input-regression-data/Logs/KaM_2026-10-29_13-11-55-006.log`. The Mac was locked during the final packaged UI check, so absence of an audible beep still needs confirmation on an unlocked Mac. The event-handling regression passed; no new interactive keyboard result is claimed.

## Save/resume and full keyboard regressions

These checks first passed on the Dock-icon build, with evidence in `assets.local/regression-tests-release/results.json`. They also pass on the current build in `assets.local/regression-tests-native-command-verified/results.json`, which adds the native application-dispatch regression described below.

- TSK2 and TPR3 each ran to tick 6,000 with seed 4, compared against a save at tick 1,500 followed by a fresh-process reload. All 1,008 component snapshots matched byte for byte, including RNG state, resources, unit positions/tasks/orders, terrain, AI, pathfinding, projectiles and script state. Both paths received identical commands before and after the reload, including road construction; recruitment and formation commands were issued where available.
- Pending AI equipment orders at counts 0, 1, 2 and 8 retained their live warrior IDs through an actual game save/load and left the queue after resuming.
- Scripted sound-removal requests at counts 0, 1, 2 and 8 retained IDs and outstanding hand acknowledgements. Repeated loading exposed a duplicate-key exception because the old request dictionary was not cleared. Loading now replaces that state, and all four cases complete after the remaining acknowledgement.
- Live-game checkpoint limits 0, 1, 2, 30 and 60 hold across two scheduled boundaries and round-trip through disk. The suite exposed an off-by-one comparison that allowed one extra checkpoint, including when the configured limit was zero. The scheduler now requires the current count to be strictly below the limit. Large-limit fixtures prefill the collection just below the limit; they do not simulate hours of idle play.
- The Cocoa callback reproduced an unhandled Backspace before the fix. The game view now consumes remaining events after LCL delivers key-down and text input. Printable keys still reach the game exactly once. Checks cover deletion, cursor/selection movement, empty edits, all 95 printable ASCII characters with filename filtering, Enter/Tab/Escape, F1-F12, shortcuts and repeats. Native controls retain their own key/text input, and a key released after focus changes still clears the game's camera state.

The collection suite has 13 checks. Keyboard automation exercises the native callback and form dispatch; it does not replace a physical audible-beep check or test every macOS input method. The broader campaign acceptance results above remain associated with the original MVP binary.

The package uses the existing upstream icon artwork for its `KaMRemake.icns` resource and declares it in `CFBundleIconFile`. Earlier installed apps are retained as `assets.local/KaM Remake-before-keyboard-regressions.app` and `assets.local/KaM Remake-before-native-key-command-fix.app`.

## Backspace responder regression

The player confirmed that Backspace still produced a bell on the Dock-icon build. The earlier callback test skipped native processing between `KeyEvBefore` and `KeyEvAfterDown`. When the window's `TCocoaWindowContentDocument` owns focus, its text-input handler can process Backspace before the later callback consumes it.

The form now consumes editing, navigation, function keys and Control/Command shortcuts immediately after delivering key-down to the game. Printable keys remain available for the text-input event. Native controls retain their own input, and held-key tracking still receives key-up events.

`KM_MacCocoaEventProbe` dispatches through `NSApp.sendEvent` with the window document and OpenGL view separately focused. Test-only method observers preserve and call Cocoa's original implementations, and are restored before cleanup. The old build fails because Backspace reaches native command processing after the game edits the title (`assets.local/cocoa-events-before.log`). On the current build, both routes consume editing/navigation/F1-F12 keys before native processing, and all 95 printable ASCII characters reach the save field exactly once. Evidence is in `assets.local/regression-tests-native-command-verified/cocoa-events.log`.

The full regression runner passes: 13 collection checks, the existing keyboard checks, both native responder checks, and all 1,008 TSK2/TPR3 save/resume component comparisons. Audible confirmation still requires the player's manual check.

The one-hour tutorial soak was repeated on both the previous Dock-icon build and this final build. Each ran 36,000 additional ticks to tick 72,458, made all 60 consecutive minute autosaves, and retained five checkpoints. All five rotated autosaves loaded and resumed, and repeated named saves plus overwrite preserved script/checkpoint bytes and entity counts. Final evidence is in `assets.local/autosave-native-command-fix.log` and `assets.local/autosave-native-command-fix-results.json`; the earlier run is in `assets.local/autosave-latest-results.json`. All 39 player save files remained unchanged. The final installed app's six files match the package, and its signature verifies.

## Interactive checks

The packaged application was operated through its actual Cocoa window:

- Main menu, campaign selection, English briefings and mission startup for TSK and TPR.
- Unit selection and right-click movement in windowed TSK gameplay and fullscreen TPR gameplay, with visible walking units and movement status.
- Minimap navigation, keyboard camera movement, mouse-wheel zoom and pause.
- Road placement and dragging in TSK2; workers accepted orders and completed paving. A storehouse plan entered construction and a worker prepared its site.
- Save-name keyboard entry, saving through the menu, quitting, relaunching and loading that save through the menu.
- Window resizing/fullscreen and Command-Q with the unsaved-game confirmation.

The port synchronizes terrain hit-testing on mouse-down, tracks held keys and mouse buttons through Cocoa events, clears held state on deactivation, and keeps restored windows within the display work area. This also makes remote mouse input work when it does not update macOS's global hardware cursor or button state.

Interactive tests used the packaged app in the build directory. The Mac locked again before a fresh GUI launch from `~/Applications` could be inspected; the installed copy was verified against that tested package instead.

Audio backend checks passed. Physical speaker output has not been independently confirmed by a listener.

## Remaining scope

This is a local single-player MVP. Tahoe, Intel Macs, multiplayer/authentication, Windows save/replay interoperability, the map editor and legacy cutscene video playback are not validated or supported by this build. The online menu remains visible, but the build uses `DBG_SKIP_SECURE_AUTH`.

Windows/Delphi branches were retained; a Windows compiler was not available for regression compilation. Recovery from malformed or incompatible saves can still abort during unit cleanup. Keep native saves separate from Windows saves.

OpenGL and OpenAL remain the existing native backends. The app is signed ad hoc for this local installation, not notarized for public distribution. Proprietary game data is kept local and is not included in the executable bundle or source changes.
