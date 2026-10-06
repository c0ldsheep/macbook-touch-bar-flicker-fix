# MacBook Pro Touch Bar Flickering Fix

**Stop the white flashes and flicker on your MacBook Pro Touch Bar.** It's free and open source, takes about 5 minutes, and needs no admin password.

![MacBook Pro Touch Bar flickering: white flashes on the right side of the Touch Bar in a dark room](docs/touchbar-flicker.gif)

*The problem, filmed in a dark room: the right side of the Touch Bar keeps flashing white.*

## Is this your problem?

You probably have the same problem if several of these are true:

- The Touch Bar **flashes white** or flickers, often on the **right side**.
- It's worse in a **dark room** or at night.
- It's worse when it's **cold** (winter, air conditioning) and rare when it's warm.
- It **stops when the Touch Bar goes fully black** after you stop typing.
- It **stops if you shine a phone flashlight at the camera** above the screen.
- There's **no flicker on the login screen** after a restart, but it starts a few seconds after you log in.
- **Plugging in the charger makes no difference.**

## The fix in one sentence

In a dark room macOS turns the Touch Bar down very low, and a worn Touch Bar screen flickers at those very low levels. **tbkeep keeps the Touch Bar bright enough not to flicker, and switches it off instead of dimming it.**

## Install

1. Open **Terminal**: press `Cmd + Space`, type `Terminal`, then press `Return`.
2. Copy these three lines, paste them into Terminal and press `Return`:

   ```sh
   git clone https://github.com/c0ldsheep/macbook-touch-bar-flicker-fix.git
   cd macbook-touch-bar-flicker-fix
   ./install.sh
   ```

   If a window asks to install the **command line developer tools**, click **Install**. Wait until it finishes, then paste the three lines again. These are free Apple tools that build the program on your own Mac.

3. At the end you'll see `Background job: running`. That's it. The flicker should stop right away, and the fix starts by itself every time you log in.

**Optional: find the best level for your Touch Bar.** Every Touch Bar is a little different. Run `tbkeep try` and answer `y` or `n` at each step. It saves the lowest level that doesn't flicker, plus a little extra for cold days.

## Everyday commands

| Command | What it does |
|---|---|
| `tbkeep` | Shows the status |
| `tbkeep 70` | Sets the level to 70%. **If the flicker comes back, use a higher number.** |
| `tbkeep try` | Finds the lowest level with no flicker |
| `tbkeep dim off` | Keeps macOS's normal dimming before the bar turns off (`tbkeep dim on` skips it again) |
| `tbkeep auto` | Pauses the fix, so macOS controls the Touch Bar again |
| `tbkeep uninstall` | Removes everything |

If Terminal says `command not found: tbkeep`, open a new Terminal window and try again.

## Why does this happen?

- The Touch Bar is a small **OLED screen**, the same kind as many phone screens.
- macOS sets its brightness automatically, using the **light sensor next to the camera**. In a dark room it goes **very dim**. We measured about **15 nits**, while full brightness is about 357 nits.
- As a Touch Bar ages, its screen **can't hold a steady light at very low brightness any more**, so it flickers. Cold makes it worse.
- That's why the **flashlight trick** works. Bright light on the sensor makes macOS turn the Touch Bar up, and the flicker stops.
- It's a **hardware weakness**. It isn't a virus, an app or a macOS bug, which is why macOS updates don't fix it.

## What we tested

We tested on a 13-inch MacBook Pro (M1, 2020) running macOS 27.

**1. We watched it in different situations.** That's the checklist at the top: dark vs. bright room, cold vs. warm, charger vs. battery, login screen vs. after login, and a flashlight on the camera.

**2. We measured the Touch Bar's brightness inside macOS.** In a dark room macOS had set it to about 15 nits. With a flashlight on the sensor it went up to the maximum.

**3. We set the brightness ourselves and watched for flicker.**

| Touch Bar brightness | Flicker? |
|---|---|
| About 15 nits (what macOS picks in a dark room) | Yes |
| 98 nits | Yes |
| 219 nits | **No** |
| 357 nits (maximum) | **No** |
| Off (fully black) | **No** |

**4. We measured what happens when you stop typing.** On our Mac, after about 30 seconds macOS dims the Touch Bar to about 15% of its brightness. After about 45 seconds it turns it off. Even at maximum brightness that dim stage is only about 53 nits, which is in the flicker zone. So tbkeep turns the bar off at 30 seconds instead of dimming it.

**5. We ruled out software.** No Touch Bar apps were installed. The flashes even appear on the empty black part of the bar, where macOS draws nothing. And the flicker follows brightness and temperature, which software can't do.

**6. We checked the rest of the Mac.** The storage was healthy and there were no crash reports. A flickering Touch Bar is not a sign that the whole Mac is failing.

## The downsides (please read)

- **The Touch Bar wears a bit faster.** A brighter OLED ages faster, and icons that never move (like volume) can slowly burn in. To limit this, tbkeep turns the bar off sooner, after 30 seconds without typing instead of 45.
- **It's brighter in the dark.** The Touch Bar no longer dims itself in a dark room.
- **It hides the problem, it doesn't repair it.** The screen may get worse with time. If the flicker comes back (often in winter), raise the level, for example with `tbkeep 80`.
- **It uses hidden macOS settings.** A future macOS update could change them. If that happens, tbkeep stops itself and the Touch Bar goes back to normal. Nothing breaks.
- **We've tested one Mac so far:** a 13-inch MacBook Pro (M1, 2020) on macOS 27. Other Touch Bar MacBook Pros (2016 to 2022) may work. If yours doesn't, please [open an issue](https://github.com/c0ldsheep/macbook-touch-bar-flicker-fix/issues) and paste the output of `tbkeep version`.

## Other things you can try

- **Flashlight trick (temporary):** shine your phone's flashlight at the camera above the screen.
- **Turn on a room light.** macOS then makes the Touch Bar brighter by itself.
- **Keep the Mac warm.** Don't let air conditioning blow on it. Don't use a hair dryer, because heat can damage the battery.
- **Cover the bar with black tape.** It hides the flashes, but you lose the buttons under it.
- **Common tips online** (restarting the Touch Bar, resetting NVRAM or SMC, Safe Mode, macOS updates) are safe to try, but they can't fix a hardware weakness.
- **"Touch Bar disabler" apps** only make the bar black, and most of them need you to switch off System Integrity Protection, which weakens your Mac's security. We don't recommend them.

## The permanent fix: replace the Touch Bar

- **Apple:** On the 13-inch MacBook Pro, the Touch Bar is built into the **top case** together with the keyboard and the battery. Apple's repair manual for the M1 model lists no separate Touch Bar part, so Apple replaces the whole top case.
- **If your battery also needs service:** System Settings → Battery may say **Service Recommended**. Apple's battery service on these models swaps that same top case, so ask Apple to confirm the new one comes with a new Touch Bar.
- **Independent repair shops** can often replace just the Touch Bar screen for less, usually with an aftermarket or used part.
- **Take a video first.** The flicker may not show in a warm, bright shop, and Apple's diagnostics may not detect it.
- **Back up your Mac** before any repair.

## Questions

**Why is my Touch Bar flickering?**
Most likely its OLED screen has worn and can't hold a steady light at low brightness. See [Why does this happen?](#why-does-this-happen)

**Is my MacBook going to die?**
Not because of this. The Touch Bar is a separate part, and a flickering Touch Bar doesn't mean the rest of the Mac is failing.

**Is it a virus?**
No. A virus can't make a black area light up, and it can't follow the room temperature.

**Is tbkeep safe?**
It's one short program, [tbkeep.m](tbkeep.m), that anyone can read. It's built on your own Mac from that file. It needs no admin password, never goes online, doesn't read your files, and only changes the Touch Bar, never your main screen.

**Does it work on Intel MacBook Pros?**
Maybe. We haven't tested one yet. The installer checks first: if your Mac isn't supported, it tells you and installs nothing.

**How do I turn it off?**
`tbkeep auto` pauses it. `tbkeep uninstall` removes it completely.

**How does it work, technically?**
See [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Search terms

MacBook Pro Touch Bar flickering, Touch Bar flashing white, Touch Bar white flashes on the right side, Touch Bar flicker fix, Touch Bar blinking, Touch Bar glitching, Touch Bar flickers in the dark, Touch Bar flickers when cold, M1 MacBook Pro Touch Bar flicker, M2 MacBook Pro Touch Bar flicker, MacBook Pro 2016 2017 2018 2019 2020 2022 Touch Bar flickering, A1706, A1707, A1989, A1990, A2159, A2141, A2251, A2289, A2338.

## License

[MIT](LICENSE). Not affiliated with Apple. MacBook Pro and Touch Bar are trademarks of Apple Inc. Use at your own risk.
