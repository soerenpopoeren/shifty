# Shifty – shift in Zwift & MyWhoosh with your Shimano Di2

*[Deutsche Version](README.de.md)*

A macOS menu bar app that reads your Shimano Di2 over Bluetooth and turns its buttons into virtual
shifting for Zwift or MyWhoosh – whether the game runs on the Mac or on an iPad.

```
Di2 (D-Fly) ──Bluetooth──▶ Shifty (Mac) ──Wi-Fi──▶ Zwift      (acts as a Zwift Ride controller)
                                        ──Wi-Fi──▶ MyWhoosh   (open OpenBikeControl protocol)
                                        ──Keys───▶ MyWhoosh   (I/K, this Mac only, optional)
```

**Supported:** Shimano Di2 12-speed (wireless, rear derailleur "RD-R…"). The 11-speed Di2 with the
**EW-WU111** wireless unit should work the same way but is not tested yet. The older EW-WU101 only
speaks ANT+ and does not work.
**Requirements:** macOS 14 or later, Xcode Command Line Tools to build.
**Languages:** English, Deutsch, Français, Español (switch in the settings).

## Download

Grab `Shifty-<version>.zip` from the [Releases](../../releases) page, unzip it and move `Shifty.app` to
your *Applications* folder.

Shifty is not notarized by Apple, so macOS refuses the first start ("cannot be opened" / "unidentified
developer"). Either **right-click the app → Open → Open**, or open *System Settings → Privacy & Security*
and click **Open Anyway** at the bottom. This is only needed once.

You can also build it yourself: `./build.sh` (Xcode Command Line Tools required).

**Status: 0.9 beta.** Tested with a 12-speed Di2 (RD-R8150), MyWhoosh and Zwift (iPad) with a Zwift Hub.
Not yet tested: 11-speed Di2 (EW-WU111), holding a button.

## One-time setup

1. **E-TUBE Project Cyclist** (phone app): under *switch settings*, assign the buttons you want to
   **D-Fly Ch.1–4**. Shifty's default: Ch.1/Ch.2 (left) = easier, Ch.3/Ch.4 (right) = harder.
   You can change this in Shifty's settings.
   Tip: use the extra buttons on top of the hoods, then the real derailleur doesn't shift along.
   Close the E-TUBE app afterwards – the Di2 only allows one Bluetooth connection.
2. On first launch, allow **Bluetooth** and **Local Network**. The keyboard mode also needs
   *Accessibility*.

## Interface

- Shifty lives in the **menu bar** (bike icon + current gear). Click it to open the window with the
  gear display, plus/minus and the app tiles.
- **Mini display:** the picture-in-picture icon at the top shows a small floating gear display. It
  stays visible above Zwift/MyWhoosh in full screen and can be moved around.
- **Logos:** drop a logo image (or the app itself) onto a tile. The repository deliberately
  contains no third-party logos.
- **Gears:** Zwift = 24 gears, MyWhoosh = 30. Shifty remembers the last gear per app.
- **Sync:** Zwift and MyWhoosh don't report their gear. Zwift starts every ride in gear 8, so Shifty
  starts counting at 8 when Zwift connects. MyWhoosh is synced on its first connection after Shifty
  starts: all the way down to 1, then up to the remembered gear. Manually: right-click the gear number.
- **Stays awake:** while the Di2 or a training app is connected, Shifty keeps the Mac from sleeping
  (the display may still turn off) – in sleep, Bluetooth and Wi-Fi would drop.
- Settings (gear icon): language, Di2 search, button mapping, gear, log.

## Usage

- Start Shifty and press a Di2 lever to wake it up. Shifty then connects automatically and
  remembers the Di2. The lights under "Button mapping" flash on every press.
- **Zwift:** Shifty appears as **"Shifty Di2"** on Wi-Fi (it also offers a power meter that always reports
  0 W – Zwift only lists Wi-Fi devices with one). Pairing takes three steps: **1.** choose "Shifty Di2" as **power source**,
  **2.** choose "Shifty Di2" under **Controls**, **3.** set the power source back to your trainer – the
  controls stay. (Zwift only offers Shifty as a power source at first, hence the detour.) The "?" on the
  Zwift tile shows these steps, and Shifty reminds you of step 3 until you shift for the first time. Virtual shifting needs a trainer that supports it in Zwift (e.g. Zwift
  Hub / Cog).
- **MyWhoosh:** on the connection screen, tap the OpenBikeControl icon at the top right and confirm
  with "Yes". The service is named like your Mac on the network.
- Mac and iPad must be on the same Wi-Fi (no guest network, no client isolation).
- Log (always in English): in the settings and in `~/Library/Logs/Shifty.log`

## Releasing

`./release.sh` builds the app and packs it as `build/Shifty-<version>.zip` (version from `Info.plist`).
Upload that file to a new GitHub release.

## Technical overview

| Part | File | Protocol |
|---|---|---|
| Di2 | `Sources/Di2Client.swift` | BLE service `18EF`, characteristic `2AC2` (indications) |
| Zwift | `Sources/ZwiftOutput.swift`, `Sources/ZwiftProtocol.swift` | Wahoo DirCon (`_wahoo-fitness-tnp._tcp`, port 36866), speaks like a Zwift Click v2 |
| Zwift probe | `Tools/ZwiftProbe` | developer tool: reads a real Zwift controller's answers (`Tools/ZwiftProbe/run.sh`) |
| MyWhoosh | `Sources/MyWhooshOutput.swift` | [OpenBikeControl](https://github.com/OpenBikeControl/openbikecontrol-protocol) over mDNS/TCP |
| Keyboard | `Sources/KeyboardOutput.swift` | MyWhoosh keys I (easier) / K (harder) |
| Translations | `Sources/Localization.swift`, `Resources/*.lproj` | one table, columns EN/DE/FR/ES |

Where the protocol details come from is documented in [CREDITS.md](CREDITS.md).
New languages are welcome: add a column to the table in `Localization.swift` and a
`Resources/<lang>.lproj/InfoPlist.strings`.

## License

Copyright (C) 2026 soerenpopoeren ([@soerenpopoeren](https://www.instagram.com/soerenpopoeren/) on Instagram)

Shifty is licensed under the **GNU General Public License v3.0 or later** (see [LICENSE](LICENSE)).
You may use, modify and share it, also in modified form. Shared versions must again be licensed
under the GPL and publish their source code.

**Exception – logo:** the Shifty logo (`Assets/AppIcon.png`) is **not** covered by the GPL.
All rights remain with soerenpopoeren. It may be used in unmodified builds of this project.
If you modify and redistribute Shifty, please replace the logo with your own. The build script
works without it. See [Assets/LICENSE.md](Assets/LICENSE.md).

## Disclaimer and trademarks

Shifty is an independent hobby project and is not affiliated with Shimano, Zwift, MyWhoosh,
Wahoo or SRAM. All trademarks belong to their owners (details in [CREDITS.md](CREDITS.md)).
The software is provided without any warranty. Use at your own risk.
