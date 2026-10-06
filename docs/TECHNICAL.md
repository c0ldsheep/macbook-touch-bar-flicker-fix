# How tbkeep works

These notes are for developers and anyone who wants to check the fix. Everything was measured on a 13-inch MacBook Pro (M1, 2020) running macOS 27.

## The hardware

The Touch Bar is a 2170 × 60 OLED panel (Apple codename "summit", driver `AppleSummitLCD`). It is connected over MIPI-DSI to its own display pipe (`dispdfr`, driver `AppleMobileDispH13G-DFR`). Its brightness goes through an `AppleARMBacklight` node called `backlight-dfr`, which covers about 12 to 357 nits.

Read the live brightness with:

```sh
ioreg -r -n backlight-dfr -l | grep CurrentNits
```

## Who sets the brightness

- **CoreBrightness** (`corebrightnessd`) treats the Touch Bar as its own display. Its `CBDisplayType` is 3, while the built-in screen is 0. It has its own auto-brightness module, `CBAutoBrightnessModuleDFR`, which follows the ambient light sensor next to the camera. In a dark room (0 lux) it chose about 15 nits.
- **TouchBarServer** handles idle dimming through `DFRBrightnessClient` (DFRBrightness.framework), in steps:

  | Step | Meaning | When |
  |---|---|---|
  | 1 | Normal | While you type or touch the trackpad |
  | 2 | Dim, about 15% of the level | About 30 s without input |
  | 4 | Off | About 45 s without input |

The dim step is a fraction of the level, so raising the level can't lift the dim stage out of the flicker range. At 100% it is still only about 53 nits.

## What tbkeep changes

Through `BrightnessSystemClient` (CoreBrightness), **for the Touch Bar display only**:

- `DisplayBrightnessAuto` is set to `NO`.
- `DisplayBrightness` is set to `{Brightness: 0.60}`. The value runs from 0 to 1: 0.25 is about 98 nits, 0.60 about 219 nits, and 1.0 about 357 nits.

Through `DFRBrightnessClient`, when the dimming step becomes 2, tbkeep sets step 4 (off) with a 0.2-second fade. TouchBarServer turns the bar back on (step 1) at the next key press or touch, as usual.

The display ID comes from `-[DFRBrightnessClient getDFRDisplayID]` and is cross-checked against `CBDisplayType` on every pass. A display that reports another type is never touched, so the main screen can't be changed by mistake. If `getDFRDisplayID` is missing, tbkeep looks for the display whose type is 3.

## The background job

`~/Library/LaunchAgents/local.tbkeep.plist` starts `tbkeep run` at login.

- Every 2 seconds it re-reads the settings and re-applies the level if anything reset it.
- Every 0.5 seconds it checks the dimming step.
- It also re-applies the level when the Mac wakes.
- It logs to `~/Library/Logs/tbkeep.log`, only when it changes something, and at most 60 lines an hour.

Settings live in `~/Library/Application Support/tbkeep/`:

- `level` holds a value such as `0.60`, or `auto` when the fix is paused.
- `dim` holds `skip` (the default) or `keep`.

Before it starts, tbkeep checks that every Apple class and method it uses exists. If a future macOS removes any of them, `tbkeep run` exits with status 0. The LaunchAgent's `KeepAlive` → `SuccessfulExit = false` rule means it is not restarted, and the Touch Bar keeps Apple's normal behaviour.

## Measurements

| Setting | Measured | Flicker |
|---|---|---|
| Auto-brightness in a dark room (0 lux) | 14.8 nits | Yes |
| 25% | 98 nits | Yes |
| 60% | 219 nits | No |
| 100% | 357 nits | No |
| Dim step at 60% | 32 nits | (skipped by tbkeep) |
| Dim step at 100% | 53 nits | (skipped by tbkeep) |
| Off | panel power off | No |

What we observed:

- The flicker was worse in cold weather. In warm weather it still appeared at low brightness in a dark room.
- The charger made no difference.
- On Macs with FileVault, the login screen after a restart appears before macOS drives the Touch Bar. That's why the flicker only starts a few seconds after logging in.

## Things that don't help

- `DFRSetStatus()` in DFRFoundation only starts or stops the legacy Touch Bar simulator on current macOS. We checked its disassembly.
- Touch Bar "disabler" apps unload ControlStrip so the bar shows black, but the panel stays powered. Most of them need System Integrity Protection turned off.
- `sudo pkill TouchBarServer` just restarts the server.

## Bug reports

Please include the output of `tbkeep version` (the Mac model and macOS version) and `tbkeep`, and say what you see on the Touch Bar.
