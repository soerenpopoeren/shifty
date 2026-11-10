# Shifty – Shimano Di2 als Schalter für Zwift & MyWhoosh

*[English version](README.md) – die englische README ist die maßgebliche Fassung.*

Mac-App, die deine Di2 per Bluetooth liest und die Knöpfe als virtuelles Schalten
an Zwift oder MyWhoosh weitergibt, egal ob das Spiel auf dem Mac oder auf dem iPad läuft.

```
Di2 (D-Fly) ──Bluetooth──▶ Shifty (Mac) ──WLAN──▶ Zwift      (meldet sich als Zwift-Ride-Controller)
                                        ──WLAN──▶ MyWhoosh   (offenes OpenBikeControl-Protokoll)
                                        ──Tasten─▶ MyWhoosh   (I/K, nur auf diesem Mac, optional)
```

**Unterstützt:** Shimano Di2 12-fach (kabellos, Schaltwerk „RD-R…“). Die 11-fach Di2 mit
Funkeinheit **EW-WU111** sollte ebenso funktionieren, ist aber noch nicht getestet. Die ältere
EW-WU101 funkt nur ANT+ und geht nicht.
**Voraussetzung:** macOS 14 oder neuer, Xcode Command Line Tools zum Bauen.
**Sprachen:** English, Deutsch, Français, Español (umschaltbar in den Einstellungen).

## Download

Lade `Shifty-<Version>.zip` von der Seite [Releases](../../releases), entpacke sie und schieb `Shifty.app`
in deinen Ordner *Programme*.

Shifty ist nicht von Apple beglaubigt (notarisiert), deshalb verweigert macOS den ersten Start („kann nicht
geöffnet werden“ / „nicht verifizierter Entwickler“). Entweder **Rechtsklick auf die App → Öffnen →
Öffnen**, oder in *Systemeinstellungen → Datenschutz & Sicherheit* ganz unten auf **Dennoch öffnen**
klicken. Das ist nur einmal nötig.

Selbst bauen geht auch: `./build.sh` (Xcode Command Line Tools nötig).

**Stand: 0.9 Beta.** Getestet mit einer 12-fach Di2 (RD-R8150), MyWhoosh und Zwift (iPad) mit Zwift Hub.
Noch nicht getestet: 11-fach Di2 (EW-WU111), Knopf gedrückt halten.

## Einmalig einrichten

1. **E-TUBE Project Cyclist** (Handy-App): Unter *Schalterbelegung* die gewünschten Knöpfe
   auf **D-Fly Ch.1–4** legen. Standard in Shifty:
   Ch.1/Ch.2 (links) = leichter, Ch.3/Ch.4 (rechts) = schwerer. Das lässt sich in den Einstellungen ändern.
   Tipp: Nimm die Zusatzknöpfe oben auf den Griffen, dann schaltet das echte Schaltwerk nicht mit.
   Danach die E-TUBE App schließen, denn die Di2 erlaubt nur eine Bluetooth-Verbindung.
2. Beim ersten Start **Bluetooth** und **Lokales Netzwerk** erlauben. Für den Tastatur-Modus
   zusätzlich *Bedienungshilfen*.

## Oberfläche

- Shifty lebt in der **Menüleiste** (Fahrrad-Symbol + aktueller Gang). Ein Klick öffnet das Fenster
  mit Ganganzeige, Plus/Minus und den App-Kacheln.
- **Mini-Anzeige:** Mit dem Bild-in-Bild-Symbol oben im Fenster blendest du eine kleine,
  schwebende Ganganzeige ein. Sie bleibt auch über Zwift/MyWhoosh im Vollbild sichtbar und lässt sich verschieben.
- **Logos:** Ein Logo-Bild (oder die App selbst) einfach auf die Kachel ziehen. Das Repository
  enthält bewusst keine fremden Logos.
- **Gang:** Zwift = 24 Gänge, MyWhoosh = 30. Shifty merkt sich den letzten Gang je App.
- **Abgleich:** Zwift und MyWhoosh verraten ihren Gang nicht. Zwift beginnt jede Fahrt in Gang 8, darum
  zählt Shifty beim Verbinden mit Zwift ab 8. MyWhoosh wird beim ersten Verbinden nach dem Start von
  Shifty abgeglichen: ganz runter auf 1, dann hoch auf den gemerkten Gang. Von Hand: Rechtsklick auf
  die Gangzahl.
- **Bleibt wach:** Solange die Di2 oder eine Trainings-App verbunden ist, verhindert Shifty den
  Ruhezustand des Macs (der Bildschirm darf dunkel werden) – im Ruhezustand würden Bluetooth und WLAN
  abbrechen.
- Einstellungen (Zahnrad): Sprache, Di2 suchen, Kanal-Belegung, Gang, Log.

## Benutzen

- Shifty starten und einen Di2-Hebel drücken, damit sie aufwacht. Shifty verbindet sich dann automatisch
  und merkt sich die Di2. Die Lämpchen bei „Belegung“ leuchten bei jedem Druck auf.
- **Zwift:** Shifty erscheint im WLAN als **„Shifty Di2“** (es bietet zusätzlich einen Leistungsmesser an,
  der immer 0 Watt meldet – Zwift zeigt nur WLAN-Geräte mit so einem an). Koppeln in drei Schritten: **1.** „Shifty Di2“ als **Leistungsquelle**
  wählen, **2.** bei **Steuerung** „Shifty Di2“ wählen, **3.** Leistungsquelle zurück auf deinen Trainer –
  die Steuerung bleibt. (Zwift bietet Shifty zuerst nur als Leistungsquelle an, daher der Umweg.) Das „?“
  an der Zwift-Kachel zeigt diese Schritte, und Shifty erinnert an Schritt 3, bis du das erste Mal schaltest. Virtuelles Schalten braucht einen Trainer,
  der es in Zwift unterstützt (z. B. Zwift Hub / Cog).
- **MyWhoosh:** Im Verbindungsbildschirm oben rechts auf das OpenBikeControl-Symbol tippen und
  mit „Ja“ bestätigen. Der Dienst heißt wie dein Mac im Netzwerk.
- Mac und iPad müssen im selben WLAN sein (kein Gäste-WLAN, keine Client-Isolation).
- Log (immer auf Englisch): in den Einstellungen und in `~/Library/Logs/Shifty.log`

## Technik

| Teil | Datei | Protokoll |
|---|---|---|
| Di2 | `Sources/Di2Client.swift` | BLE-Service `18EF`, Characteristic `2AC2` (Indications) |
| Zwift | `Sources/ZwiftOutput.swift`, `Sources/ZwiftProtocol.swift` | Wahoo DirCon (`_wahoo-fitness-tnp._tcp`, Port 36866), spricht wie ein Zwift Click v2 |
| Zwift-Messung | `Tools/ZwiftProbe` | Entwickler-Werkzeug: liest die Antworten eines echten Zwift-Controllers (`Tools/ZwiftProbe/run.sh`) |
| MyWhoosh | `Sources/MyWhooshOutput.swift` | [OpenBikeControl](https://github.com/OpenBikeControl/openbikecontrol-protocol) über mDNS/TCP |
| Tastatur | `Sources/KeyboardOutput.swift` | MyWhoosh-Tasten I (leichter) / K (schwerer) |

| Übersetzungen | `Sources/Localization.swift`, `Resources/*.lproj` | eine Tabelle, Spalten EN/DE/FR/ES |

Woher die Protokoll-Angaben stammen, steht in [CREDITS.md](CREDITS.md) (auf Englisch).

## Lizenz

Copyright (C) 2026 soerenpopoeren ([@soerenpopoeren](https://www.instagram.com/soerenpopoeren/) auf Instagram)

Shifty steht unter der **GNU General Public License v3.0 oder neuer** (siehe [LICENSE](LICENSE)).
Du darfst es nutzen, verändern und weitergeben, auch verändert. Weitergegebene Versionen müssen
wieder unter der GPL stehen und ihren Quellcode offenlegen.

**Ausnahme Logo:** Das Shifty-Logo (`Assets/AppIcon.png`) steht **nicht** unter der GPL.
Alle Rechte daran liegen bei soerenpopoeren. Es darf in unveränderten Builds dieses Projekts
verwendet werden. Wer Shifty abwandelt und weitergibt, ersetzt das Logo bitte durch ein eigenes.
Das Build-Skript kommt auch ohne Logo aus.

## Haftung und Marken

Shifty ist ein unabhängiges Hobbyprojekt und steht in keiner Verbindung zu Shimano, Zwift, MyWhoosh,
Wahoo oder SRAM. Alle Marken gehören ihren Inhabern (Details in [CREDITS.md](CREDITS.md)).
Die Software wird ohne jede Gewährleistung bereitgestellt. Benutzung auf eigene Gefahr.
