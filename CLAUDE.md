# Rotorwacht

Eigenes Hubschrauber-Rettungsspiel für den Mac, nur zum eigenen Gebrauch. Inspiriert vom Genre des C64-Spiels Choplifter, das Lutz früher gern gespielt hat, aber **kein Nachbau**: eigenes Thema (Katastrophenrettung), eigener Name, eigene Figuren, Grafiken, Einsätze, Musik und Geräusche, in heutiger Grafik.

## Stand

- **Phase:** Version 0.3.0 gebaut (19.11.2026): alle sechs Einsätze (Hochwasser, Waldbrand, Sturmnacht an der Küste, Erdbeben in der Altstadt, Vulkanausbruch, Lawinen im Hochgebirge) von Start bis Wertung spielbar, drei Stufen, Freischalten und lokaler Fortschritt, 94 Tests grün. Tags: `v0.1.0` gesetzt, `v0.2.0` und `v0.3.0` noch nicht (erst nach Rückfrage bei Lutz).
- Nächster Schritt: Grafik und Effekte ausbauen, Feinschliff der Einsätze (Spielbarkeit mit echter Hand prüfen), siehe Fahrplan in `docs/planung/02 Spielkonzept.md`.
- Bis 19.11.2026 hieß das Projekt „Wühltisch“ (erster Entwurf mit Kaufhaus-Thema, Missverständnis: gemeint war Choplifter, nicht „Shoplifter“).

## Bauen und Testen

- `scripts/build.sh [--run]` baut `build/Rotorwacht.app` mit `swiftc` (nur Command Line Tools, kein Xcode). `scripts/test.sh` führt die Tests (Swift Testing) aus.
- **Warum nicht `swift build`:** Die installierte Toolchain (CLT 27.2) hat eine unpassende Paketverwaltung (`PackageDescription` lässt sich nicht linken, XCBuild bricht ab), `swift build`/`swift test` laufen hier nicht. `Package.swift` liegt trotzdem bei und sollte mit Xcode oder einer heilen Toolchain funktionieren (nicht geprüft). Kein XCTest in den CLT, daher Swift Testing.
- Code: `Sources/RotorwachtCore` (Logik, ohne UI, getestet), `Sources/Rotorwacht` (App). Einsätze als JSON in `Sources/RotorwachtCore/Missions/` (`MissionLibrary.all` listet die im Menü angebotenen, in Reihenfolge). Feuer: `Fire.swift` (Zellen, Ausbreitung, Löschen), Tank und Tropfen in `MissionSimulation`. Gefahren-Bausteine (`Hazards.swift` Daten und Zustand, `SimHazards.swift` Regeln): Gewitterzellen `storms`, Salven `volleys` (Trümmer, Lavabrocken), Bodenströme `flows` (Lava, Lawine), Seilwinde (`access: "winch"` am Rettungspunkt), `outposts`, Seegang `flood.swell`, `atmosphere`, `look`; alle Felder optional. Stufen: `Difficulty.swift` (`Mission.scaled(for:)`), Fortschritt: `PlayerProgress.swift`. Die App zeichnet die Gefahren in `HazardLayer.swift` (Weltebene) und `AtmosphereLayer.swift` (Wetter, Nacht, Blitzlicht), Landschaftsstile in `ArtLooks.swift`.
- Koordinaten: x nach rechts, y nach oben, Einheiten = Bildpunkte der 1280x720-Szene. Das Lager steht rechts.
- Entwicklungshilfe: `ROTORWACHT_SHOTS=<Ordner>` (mit `ROTORWACHT_MISSION=<id>`, `ROTORWACHT_UNLOCK_ALL=1` und `ROTORWACHT_TIMES=10,20,…` für die Zeitpunkte) startet den Einsatz mit Autopilot und legt Bildschirmfotos ab (`DebugShots.swift`). Der Fortschritt wird dabei nicht angefasst.

## Planung

Liegt unter `docs/planung/`:

- `01 Offene Fragen.md`: Fragen zu Spielprinzip, Steuerung, Grafik und Technik
- `02 Spielkonzept.md`: freigegeben 19.11.2026 (Katastrophenrettung, sechs Einsätze, Umfang 0.1)

## Projekt-Eckdaten

- **Name:** Rotorwacht (Ordner und Repo `rotorwacht`).
- **Plattform:** GitHub `luro611/rotorwacht` (privat). Nicht Codeberg.
- **Lizenz:** später festlegen.
- **Versionen:** 0.x bis zum ersten fertigen Stand, dann 1.0.0.
- **Technik:** native Mac-App mit Swift, SpriteKit und SwiftUI, unnotarisiert (kein Apple-Entwicklerkonto; nicht wieder ansprechen).
- **Steuerung:** Pfeiltasten zum Fliegen, Leertaste für Löschwasser, Esc Pause.
- **Grafik:** detailreiche, hochauflösende 2D-Grafik mit Parallax, Licht und Partikeln (kein Pixel-Look).

## Eigenständigkeit (verbindlich)

- Keine Namen, Figuren, Sprites, Levelpläne, Musik, Texte oder Bildschirmaufbauten aus Choplifter oder anderen bestehenden Spielen übernehmen, auch nicht abgewandelt. Kein Kriegs-/Geisel-Thema.
- Übernommen wird nur das allgemeine Spielprinzip (seitlich fliegen, Menschen abholen, zur Basis bringen).
- Grafik und Ton selbst erstellt oder frei lizenziert (CC0), Herkunft in `assets/QUELLEN.md`.
- Keine ROMs, Disk-Images oder Dateien des Originals ins Repository.

## Designsprache

Das Spielfeld hat eine eigene Grafik. Menü, Einstellungen und Über-Fenster folgen der Designsprache von lurohome (`/Users/luro/Documents/Projekte/Webseiten/lurohome/src/style.css`, Schriften aus `lurohome/src/fonts/`, hell und dunkel). Marke luro: Siegel kompakt auf dem Startbildschirm, Wortmarke als Fußzeile.

## Regeln

- Keine Zugangsdaten oder privaten Daten im Repository; Zugangsdaten nur in `.env`, im Repository nur `.env.example`.
