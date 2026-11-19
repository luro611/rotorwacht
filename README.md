<p align="center">
  <img src="Sources/Rotorwacht/Images/siegel-hell.png#gh-light-mode-only" width="120" alt="luro HOMELAB">
  <img src="Sources/Rotorwacht/Images/siegel-dunkel.png#gh-dark-mode-only" width="120" alt="luro HOMELAB">
</p>

# Rotorwacht

Eigenes Hubschrauber-Rettungsspiel für den Mac (Swift, SpriteKit, SwiftUI): nach Naturkatastrophen Menschen von Dächern und Anhöhen holen und ins Lager bringen, bevor Wetter, Wasser oder Treibstoff dir einen Strich durch die Rechnung machen.

**Status:** Version 0.2.0 (Einsatz 1 „Hochwasser im Flusstal“, Einsatz 2 „Waldbrand am Hang“ mit Löschwasser und Feuer). Nur zum eigenen Gebrauch, unnotarisiert.

**Lizenz:** noch nicht festgelegt

![Einsatz 1: Rettung vom Dach](docs/bilder/flug-0.1.png)
![Einsatz 2: Löschflug am Waldbrand](docs/bilder/loeschen-0.2.png)

## Starten

Voraussetzung: macOS 14 oder neuer, Apple-Silicon-Mac, Swift-Werkzeuge (die Command Line Tools genügen, Xcode ist nicht nötig).

```bash
scripts/build.sh --run
```

Das baut `build/Rotorwacht.app` (ad hoc signiert) und startet sie. Beim ersten Start einer unnotarisierten App: Rechtsklick auf die App, „Öffnen“.

Tests (Swift Testing, 58 Tests für Flugphysik, Landen, Ein-/Aussteigen, Tank, Feuer und Autopilot-Proben beider Einsätze):

```bash
scripts/test.sh
```

Mit einem vollständigen Toolchain (Xcode) geht auch `swift build` und `swift test` über `Package.swift`.

## Steuerung

| Taste | Wirkung |
| --- | --- |
| Pfeil links/rechts | beschleunigen, neigen, wenden |
| Pfeil hoch/runter | steigen, sinken |
| Esc | Pause |
| Leertaste | Löschwasser abwerfen (halten) |

Landen: sanft aufsetzen (unter etwa 75 Einheiten Sinkgeschwindigkeit, wenig Seitenfahrt, gerade). Gelandet steigen Menschen von selbst ein; im Lager am rechten Rand steigen sie aus, und der Hubschrauber tankt und wird langsam repariert. Im Wasser landen kostet Haltbarkeit.

Löschen: Den Tank füllst du im Tiefflug über See, Fluss oder Flut (und im Lager). Die Leertaste wirft Tropfen ab, die deine Fluggeschwindigkeit mitnehmen. Wasser löscht Flammen und macht den Boden nass; nasser Boden brennt nicht, ein Streifen vor der Flammenfront hält das Feuer auf. Feuer läuft bergauf und mit dem Wind schneller, bedroht Wartende, Rauch nimmt die Sicht und Hitze kostet Haltbarkeit.

## Aufbau

- `Sources/RotorwachtCore`: Spiellogik ohne Oberfläche (Flugphysik, Regeln, Einsatzdaten). Von den Tests geprüft.
- `Sources/RotorwachtCore/Missions/*.json`: Einsätze als Daten (Gelände, Rettungspunkte, Flut, Seen, Brandzonen, Böen, Treibstoff, Tank).
- `Sources/Rotorwacht`: die Mac-App (SpriteKit-Szene, SwiftUI-Menüs und Anzeige, synthetisierter Ton).
- `scripts/`: `build.sh` (App bauen), `test.sh` (Tests).
- `docs/planung/`: Spielkonzept und offene Fragen.
- Grafik und Ton entstehen im Code, es gibt keine fremden Dateien. Schriften: siehe `assets/QUELLEN.md`.

Entwicklungshilfe: `ROTORWACHT_SHOTS=<Ordner> build/Rotorwacht.app/Contents/MacOS/Rotorwacht` startet den Einsatz selbst, lässt einen Autopiloten fliegen und legt Bildschirmfotos ab.
