# Muscle Legends for Matcha

Muscle Legends automation using [REM UI](https://gitlab.com/ellijahheath/rem-ui). Requires Matcha with Hybrid Mode enabled and Muscle Legends place `3623096087`.

```lua
loadstring(game:HttpGet("https://gitlab.com/ellijahheath/muscle-legends-matcha/-/raw/main/loader.lua"))()
```

Right Shift opens/closes the menu. End unloads it. Hub settings save to `muscle-legends-matcha-settings.json` and restore on reload. Your initial preset enables direct training at 5 requests/sec, auto rebirth, Ultimate upgrades, keep-size-2, auto equip best, and foreground anti-AFK. Rerunning stops the previous hub without overwriting saved toggles with teardown values.

## Features

- Direct reps, individual exercises, exercise cycling, and **Best strength source**.
- Best source ranks usable machines/tools by base strength gain per rep time, checks live requirements, confirms mounting, and backs off after rejection or missing gains. Unavailable bench switching preserves training on the current machine.
- Auto rebirth uses current strength requirements and pet/Ultimate reductions, with one request in flight and replicated confirmation.
- Auto Ultimate upgrades chooses the cheapest unmaxed upgrade, with stable name ordering for ties. It checks the live catalog and balance immediately before buying, and only buys if at least **100 rebirths remain**. It waits for both level and balance confirmation, and pauses on an ambiguous result. Manual spending outside the hub cannot be made atomic with its checks.
- Auto equip best watches inventory, equipment, gamepasses, and the Pet Slot Ultimate level. It invokes the native equip-best action on changes, absorbs its own equipment update, and refreshes after a confirmed Pet Slot upgrade. It also retains the manual equip-best button.
- Manual machine changes tolerate transient missing parent references without disabling training.
- **Anti AFK (with background helper)** sends a paired F15 press/release after 120 seconds without keyboard input. It waits while Roblox is unfocused, a modifier/mouse button is held, or a rebirth/upgrade/machine operation is pending. It never moves the character or mouse, changes the camera/input-routing setting, or requests a rejoin. It uses the existing scheduler and releases its own key on disable/unload. Its toggle is saved with the other hub settings.
- The optional background helper covers unfocused/minimized Roblox. It briefly activates a transparent Roblox window, sends F15, restores its window state and the previously focused application, and never uses Space, clicks, administrator elevation, or input blocking. It waits for a pause in physical input. If Roblox is elevated, Windows may reject non-admin input; the helper reports errors instead of elevating itself. The game's native idle handler independently requests a rejoin after 18 idle minutes.
- Ready-chest collection, travel, combat controls, and collision restoration.
- Dropdown scrollbar, navigation buttons, arrow keys, and Page Up/Page Down through the pinned REM Matcha edition.

Training and rebirths were verified in the live game. The current game sometimes accepts a normal bench leave request without releasing its seat weld; the hub keeps that bench training instead of stalling while trying to switch.

Emergency stop:

```lua
_G.MuscleLegendsMatcha.Stop()
```

## Source and verification

`loader.lua` loads the latest `main/matcha.lua`. The hub pins its REM dependency to a reviewed commit in the REM-UI repository so UI updates cannot silently change its API.

Node.js 18 or later:

```sh
npm ci
npm test
```

The runner downloads that exact REM revision, syntax checks it, and runs 56 contract checks covering automation lifecycle, machine selection and fallback, rebirth coordination, and Ultimate reserve/confirmation rules. To verify offline, pass a local copy of the pinned REM source:

```sh
node verification/run.cjs /path/to/rem_v6-matcha.lua
```

Based on [AkiraDev's Muscle Legends hub](https://github.com/akiradv/scriptsroblox), adapted for Matcha's supported APIs. REM UI originated in [daddysxgold/Blade-Ball-is-Easy](https://github.com/daddysxgold/Blade-Ball-is-Easy).

## Offline reload

When GitLab is unavailable, place `muscle-legends-rem-matcha.lua` (the hub source) and `rem-v6-matcha-7679732.lua` (the pinned REM edition) in your Matcha workspace. The hub uses its local REM cache before downloading anything.

```lua
loadstring(readfile("muscle-legends-rem-matcha.lua"))()
```

## Background anti-AFK helper

Load the hub first, then run this from the repository root:

```powershell
.\tools\start-background-anti-afk.ps1
```

The launcher downloads portable AutoHotkey v2.0.30 from the official AutoHotkey GitHub release and verifies its published SHA256. It makes no system-wide installation or startup registration. If you already have AutoHotkey v2, run `tools/background-anti-afk.ahk` directly with the hub state-file path as its first argument.

When the helper is running it owns both foreground and background pulses, so Lua does not send duplicates. Taps are due every 120 seconds and defer while physical input is active. This is not focus-free input: Roblox briefly receives foreground focus for a 50ms F15 press. A half-second focus-confirmation timeout prevents unbounded waiting; cleanup releases F15 and restores transparency, minimization and prior focus. The helper only runs when exactly one Roblox window matches. It reads the hub heartbeat and pauses within its next check when Anti AFK is disabled or the hub unloads, and after 15 seconds if the heartbeat stops. Turning the hub toggle back on resumes it. Use the helper's tray menu to exit entirely.

Local diagnostic files next to the hub state file:

- `muscle-legends-anti-afk-helper.ini`: current acknowledgement, pulse count and status.
- `muscle-legends-anti-afk-helper.jsonl`: tap timestamps and focus/window/key restoration results.

Inspired by [SpaceGT/Anti-AFK](https://github.com/SpaceGT/Anti-AFK), with its MIT notice included in `tools/SPACEGT-LICENSE.txt`. The game-specific `player.AFK` Lua snippet is intentionally omitted because Muscle Legends has no such value. Sending a tap is independently observable; preventing the actual idle kick still requires an uninterrupted live test.
