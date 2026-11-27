<p align="center">
  <img src="Sources/Rotorwacht/Images/siegel-hell.png#gh-light-mode-only" width="120" alt="luro HOMELAB">
  <img src="Sources/Rotorwacht/Images/siegel-dunkel.png#gh-dark-mode-only" width="120" alt="luro HOMELAB">
</p>

# Rotorwacht

Eigenes Hubschrauber-Rettungsspiel für den Mac (Swift, SpriteKit, SwiftUI): nach Naturkatastrophen Menschen von Dächern und Anhöhen holen und ins Lager bringen, bevor Wetter, Wasser oder Treibstoff dir einen Strich durch die Rechnung machen.

**Status:** Version 0.10.0 (zehn Einsätze, fünf Stufen, Gamepad, Musik, Durchfahrten mit Shuttern, Bestenliste, Hindernisse, Wetterwechsel, Zeitbonus, Kombos und Endlosmodus; Grafik aus gerenderten 3D-Modellen, in 0.10 neu: Hintergründe, Tunnel, Brücken, Shutter, größere Personen). Nur zum eigenen Gebrauch, unnotarisiert.

**Lizenz:** MIT für den Code, CC BY 4.0 für eigene Grafik und Ton (siehe `LICENSE`, `LICENSE-ASSETS.md`)

![Startbildschirm mit zehn Einsätzen und fünf Stufen](docs/bilder/start-0.9.png)
![Tunnel durch den Berg mit Shutter und Ampeln](docs/bilder/tunnel-0.10.png)
![Hochwasser: neue Berge, Wolken und größere Personen](docs/bilder/hochwasser-0.10.png)
![Aquädukt als Unterführung in der Altstadt](docs/bilder/bruecke-0.10.png)
![Vulkan mit Aschewolke](docs/bilder/vulkan-0.10.png)
![Nacht an der Küste](docs/bilder/kueste-0.10.png)
![Bohrinsel im Sturm](docs/bilder/bohrinsel-0.10.png)
![Wüste](docs/bilder/wueste-0.10.png)
![Sturmnacht an der Küste, heller als zuvor](docs/bilder/sturmnacht-0.8.png)
![Hochwasser mit ruhigeren Fernbergen](docs/bilder/hochwasser-0.8.png)
![Tunnel mit Shuttern im Vulkan-Einsatz](docs/bilder/tunnel-0.6.png)
![Baukran mit schwenkendem Ausleger in der Altstadt](docs/bilder/kran-0.7.png)
![Nebelbank mit Windsack und Leitung im Hochwasser-Einsatz](docs/bilder/nebel-0.7.png)
![Wertungskarte mit Bestenliste](docs/bilder/wertung-bestenliste-0.6.png)
![Hochwasser mit neuem Hubschrauber und Landeplätzen](docs/bilder/hochwasser-0.4.png)
![Waldbrand: Landeplätze mit Wartenden am Rand](docs/bilder/waldbrand-landeplatz-0.4.png)
![Altstadt](docs/bilder/altstadt-0.4.png)
![Gebirge mit Seilwinde](docs/bilder/gebirge-seilwinde-0.4.png)
![Einsatz 1: Rettung vom Dach](docs/bilder/flug-0.1.png)
![Einsatz 2: Löschflug am Waldbrand](docs/bilder/loeschen-0.2.png)
![Startbildschirm mit sechs Einsätzen, Stufen und Sperren](docs/bilder/start-0.3.png)
![Einsatz 3: Blitz in der Sturmnacht](docs/bilder/sturmnacht-blitz-0.3.png)
![Einsatz 4: Gassen der Altstadt](docs/bilder/altstadt-0.3.png)
![Einsatz 5: Lavabrocken auf gestrichelter Flugbahn](docs/bilder/vulkan-lavabrocken-0.3.png)
![Einsatz 6: Seilwinde am Felsvorsprung](docs/bilder/gebirge-seilwinde-0.3.png)

## Starten

Voraussetzung: macOS 14 oder neuer, Apple-Silicon-Mac, Swift-Werkzeuge (die Command Line Tools genügen, Xcode ist nicht nötig).

```bash
scripts/build.sh --run
```

Das baut `build/Rotorwacht.app` (ad hoc signiert) und startet sie. Beim ersten Start einer unnotarisierten App: Rechtsklick auf die App, „Öffnen“.

Tests (Swift Testing, 208 Tests für Flugphysik, Landen, Ein-/Aussteigen, Tank, Feuer, Blitz, Trümmer, Lava, Lawinen, Seilwinde, Durchfahrten, Hindernisse, Wetterwechsel, Punkte, Endlosmodus, Übungsmodus, Bestenliste, Fortschritt und Autopilot-Proben aller zehn Einsätze auf allen fünf Stufen):

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

Controller (Xbox, PlayStation, MFi; optional, per Bluetooth oder Kabel): linker Stick oder Steuerkreuz fliegen (der Stick dosiert weich), A/Kreuz Löschwasser, Start/Menü Pause. Im Menü wählen Stick oder Steuerkreuz, A bestätigt, B geht zurück. Ob ein Controller verbunden ist, steht im Startmenü und in den Einstellungen (Cmd+,, dort auch die Totzone). Wird er im Einsatz abgesteckt, pausiert das Spiel.

Landen: sanft aufsetzen (unter etwa 75 Einheiten Sinkgeschwindigkeit, wenig Seitenfahrt, gerade). Gelandet steigen Menschen von selbst ein; im Lager am rechten Rand steigen sie aus, und der Hubschrauber tankt und wird langsam repariert. Im Wasser landen kostet Haltbarkeit.

Einsätze und Stufen: Auf dem Startbildschirm wählst du Anfänger, Leicht, Mittel, Schwer oder Profi und einen von zehn Einsätzen. Mittel ist die Grundeinstellung, Anfänger verzeiht deutlich mehr, Profi hat nur einen Hubschrauber. Der erste ist offen, jeder weitere, sobald der vorige mit mindestens einem Stern geschafft ist. Sterne und Bestwerte bleiben gespeichert.

Neue Gefahren: Blitze kündigen sich mit rotem Strahl und Kreis an, dann zur Seite fliegen. Nachbeben lassen Trümmer fallen und sperren Landeplätze für eine Weile. Lavabrocken fliegen auf gestrichelten Bahnen, der Lavastrom und Lawinen nehmen Rettungspunkte. Außenposten (Symbol in der Übersichtsleiste) betanken den Hubschrauber.

Durchfahrten (Einsätze 1, 4, 5, 6): Unter Brücken und durch Tunnel musst du hindurch, darüber geht es nicht. Die Decke nicht berühren, nicht von der Seite hineinfliegen. Tunnel haben Shutter, die im Takt auf- und zugehen: **grün** offen, **gelb blinkend** mit Klacken kurz vor dem Schließen, **rot** zu. Zwischen den Toren darfst du warten, aber wer im Tor getroffen wird oder stecken bleibt, verliert diesen Hubschrauber. Im Tunnel leuchtet dein Scheinwerfer.

Neue Einsätze 7 bis 10: Auf der Bohrinsel schwanken Schiff und Floß (sanft aufsetzen, der Hubschrauber fährt mit). In der Schlucht läuft eine Flutwelle vom gebrochenen Damm. Am Pass vereist der Hubschrauber im Flug und wird träge; im Lager oder an der Straßenmeisterei taut er ab. In der Wüste kostet Hitze Treibstoff und Steigkraft, Sandstürme nehmen die Sicht.

Durchfahrten auch in den Einsätzen 8 und 9.

Hindernisse (in jedem Einsatz): Hochspannungsleitungen, Kräne mit schwenkendem Ausleger, Seilbahnen mit fahrender Gondel und Windräder stehen im Weg, immer so, dass man darüber hinwegfliegen kann. Drähte und Seile berühren kostet Haltbarkeit (Funken), feste Teile (Flügel, Ausleger, Gondel, Turm) zerstören den Hubschrauber. Wer unten durch oder zwischen den Flügeln hindurch will, geht ein Risiko ein.

Wetterwechsel: Im Einsatz drehen sich Wind und Wetter. Zuerst kommt die Vorwarnung (Hinweis, Signalton und der **Windsack** links unten, der vor Böen und Windwechsel mit gelbem Pfeil und Sekunden die kommende Richtung zeigt), dann Böen, ein Windwechsel, eine Nebelbank (schlechte Sicht, nur ein kleiner freier Fleck um den Hubschrauber) oder ein aufziehendes Gewitter mit Blitzen.

Bestenliste: Je Einsatz und Stufe die zehn besten Ergebnisse, im Startmenü (Knopf neben den Stufen) und auf der Wertungskarte. Den Namen gibst du beim ersten Eintrag an, später änderst du ihn in den Einstellungen (Cmd+,).

Punkte: 100 je Gerettetem, dazu Zeitbonus (bis 40 je Gerettetem, je mehr Restzeit desto mehr), Kombo (je Gerettetem 5 mehr für jeden Geretteten in Folge, höchstens 50; bricht bei Schaden am Hubschrauber oder verlorenen Menschen) und Flugbonus (50 für eine volle Kabine, 300 für alle Menschen eines Einsatzes in einem Flug). Die Sterne hängen weiter nur an den Geretteten und den verlorenen Hubschraubern.

Endlos: Der Knopf „Endlos“ startet einen Lauf aus zufällig zusammengesetzten Einsätzen, einer nach dem anderen und immer schwerer. Du hast auf „mittel“ 5 Hubschrauber (je Stufe 7 bis 3) für den ganzen Lauf (nach je 3 geschafften Stufen kommt einer dazu). Eine Stufe ist geschafft, wenn mindestens die Hälfte gerettet ist; sonst endet der Lauf. Eigene Bestenliste je Stufe, nach Stufennummer und Punkten.

Üben: Der Knopf „Üben“ im Startmenü bietet dreizehn kurze Strecken (Unterführung, Tunnel, Galerie, Brücke, Blitze, Trümmer, Lava, Lawinen mit Seilwinde, Flutwelle, Vereisung, schwankende Decks, Sandsturm, Löschen) mit Stufenwahl und „Langsamer“. Unbegrenzt Hubschrauber, sofort weiter am Start, keine Wertung und keine Bestenliste.

Seilwinde (Einsatz 6): Auf Felsvorsprüngen nicht landen. Schwebe ruhig über dem Vorsprung, nicht höher als das Seil (Pfeil runter holt es näher): Die Winde zieht eine Person nach der anderen hoch. Zu viel Bewegung lässt das Seil die Person wieder verlieren.

Löschen: Den Tank füllst du im Tiefflug über See, Fluss oder Flut (und im Lager). Die Leertaste wirft Tropfen ab, die deine Fluggeschwindigkeit mitnehmen. Wasser löscht Flammen und macht den Boden nass; nasser Boden brennt nicht, ein Streifen vor der Flammenfront hält das Feuer auf. Feuer läuft bergauf und mit dem Wind schneller, bedroht Wartende, Rauch nimmt die Sicht und Hitze kostet Haltbarkeit.

## Musik und Ton

Alle Musik und alle Geräusche entstehen im Code (Synthesizer, keine Aufnahmen, nichts Fremdes): ruhige Menümusik, je Einsatz ein eigener Teppich mit eigener Melodie, der bei Zeitdruck, knappem Treibstoff, Flut, Feuer und Schaden dichter und schneller wird, und ein kurzer Abschluss bei der Wertung. Im Startmenü und in der Pause stellst du Musik an/aus, Musiklautstärke und Effektlautstärke getrennt ein. Die Logik (Tonleitern, Muster, Intensität) liegt in `RotorwachtCore/Music*.swift` und ist getestet, auch per Offline-Rendern (Pegel, Stille, Sprünge); den Klang selbst muss man hören.

## Aufbau

- `Sources/RotorwachtCore`: Spiellogik ohne Oberfläche (Flugphysik, Regeln, Einsatzdaten, Gefahren-Bausteine, Stufen, Fortschritt). Von den Tests geprüft.
- `Sources/RotorwachtCore/Missions/*.json`: Einsätze als Daten (Gelände, Rettungspunkte, Flut und Seegang, Seen, Brandzonen, Böen, Treibstoff, Tank, Gewitterzellen, Salven, Lava und Lawinen, Außenposten, Atmosphäre).
- `Sources/Rotorwacht`: die Mac-App (SpriteKit-Szene, SwiftUI-Menüs und Anzeige, synthetisierter Ton und selbst erzeugte Musik).
- `scripts/`: `build.sh` (App bauen), `test.sh` (Tests).
- `docs/planung/`: Spielkonzept und offene Fragen.
- `art/`: Blender-Skripte (Python), die alle 3D-Modelle erzeugen und rendern; `scripts/render-art.sh` rendert alles neu (Blender nötig: `brew install --cask blender`), die Bilder liegen fertig in `Sources/Rotorwacht/Renders`. Ton entsteht im Code. Herkunft und Schriften: `assets/QUELLEN.md`.

Entwicklungshilfe: `ROTORWACHT_SHOTS=<Ordner> build/Rotorwacht.app/Contents/MacOS/Rotorwacht` startet den Einsatz selbst, lässt einen Autopiloten fliegen und legt Bildschirmfotos ab.
