# Credits and sources

Shifty is independently written code. The protocol details it relies on come from the following
open sources or from our own observation. No code was copied.

## Licenses of the sources

| Source | License | Used for |
|---|---|---|
| [BikeControl](https://github.com/OpenBikeControl/bikecontrol), tag `gpl3` (Jan 2026) | GPL-3.0 | Di2 D-Fly service and characteristic, device names "RDR…", basic principle "every value change is a press, the first report is the initial state"; Zwift: "RideOn" response, keep-alive message; MyWhoosh keys I/K |
| [SwiftControl (fork alexan/swiftcontrol)](https://github.com/alexan/swiftcontrol) | GPL-3.0 | Zwift Ride: advertised service `FC82` / GATT service `00000001-19CA-…`, message type `0x23`, button mask (inverted; `SHFT_UP_L = 0x100`, `SHFT_UP_R = 0x1000` … as in `ride_notification.dart`, confirmed by measurement), characteristics `…0002/0003/0004-19CA-…` |
| [qdomyos-zwift](https://github.com/cagnulein/qdomyos-zwift) | GPL-3.0 | Wahoo Direct Connect (DirCon): packet format, message types, mDNS service `_wahoo-fitness-tnp._tcp` and TXT records, Cycling Power service values (`2A65` = `08 00 00 00`, `2A5D` = `0D`) |
| [OpenBikeControl Protocol](https://github.com/OpenBikeControl/openbikecontrol-protocol) | MIT | MyWhoosh connection: mDNS service `_openbikecontrol._tcp`, message format, button IDs |

Newer versions of BikeControl are released under a non-commercial license. Nothing in Shifty is
taken from them.

## Own observation

- **Zwift Click v2** (measured with `Tools/ZwiftProbe`): GATT service `FC82`, handshake answer
  `RideOn 02 03`, device information layout (GET object 0), button bits, battery notifications.
  Zwift's GET object 16 is not answered by the real device either.

- **Di2 press type** (bits `0x10` single, `0x40` double, `0x20` hold; the lower 4 bits count up;
  counter `1` = first press of a connection): observed on a Shimano RD-R8150. Shimano itself
  describes D-Fly as distinguishing single press, hold and double press. The "hold" bit has not been
  confirmed on a device yet.
- **MyWhoosh:** does not react to "Gear Set" (`0x03`), although it lists the command as supported.
  Shifty therefore always shifts relatively and syncs by shifting "all the way down, then up".

## Shifter drawing

The shifter drawing (`Assets/shifter.svg`, converted into `Sources/ShifterShapes.swift` by
`Tools/svg2swift.py`) is an original drawing by soerenpopoeren, © 2026, licensed under
GPL-3.0-or-later like the source code.

## Logo

The Shifty logo (`Assets/AppIcon.png`) is © 2026 soerenpopoeren, all rights reserved.
It is excluded from the GPL (see README, section License, and [Assets/LICENSE.md](Assets/LICENSE.md)).

## Trademarks

Shimano, Di2, D-Fly and E-TUBE are trademarks of Shimano Inc.; Zwift is a trademark of Zwift, Inc.;
MyWhoosh is a trademark of MyWhoosh FZ-LLC; Wahoo and KICKR are trademarks of Wahoo Fitness; SRAM and
AXS are trademarks of SRAM, LLC. Shifty is an independent project and not affiliated with these
companies. The names are only used to describe compatibility. The repository contains no logos of
these companies.
