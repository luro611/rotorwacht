# Abwechslung (Block 0.7)

Entscheidung von Lutz am 20.11.2026: Alle vier Ideen gegen die Langeweile (siehe Planung 05, Abschnitt „Weitere Ideen“) kommen in 0.7. Gebaut in zwei Teilen parallel.

## 0.7a: Hindernisse und Wetterwechsel (Gefahren-Bausteine, `RotorwachtCore` `Hazards`/`SimHazards`)
- **Hindernisse** (neuer Baustein `obstacles`, optional in Einsatzdateien): Hochspannungsleitungen (Drähte, Berühren = Schaden bzw. Absturz, Funken), Kräne (Ausleger schwenkt), Seilbahnen mit fahrender Gondel, Windräder (drehende Flügel, Berühren = Absturz). Setzbar in allen sechs Einsätzen, nicht umfliegbar nur dort, wo es Sinn ergibt; Autopilot und Tests müssen weiter alle Einsätze auf allen Stufen lösen.
- **Wetterwechsel** (`weather` als Zeitplan je Einsatz): Wetter ändert sich im Einsatz (Böen, Nebelbänke mit eingeschränkter Sicht, aufziehendes Gewitter, Windwechsel), mit Vorwarnung (Windsack, Anzeige), skaliert nach Stufe. Wetter und Atmosphäre bleiben SpriteKit-Partikel/Ebenen (`AtmosphereLayer.swift`).
- Grafik der Hindernisse als Blender-Modelle (`art/`), Rendern mit `scripts/render-art.sh`.

## 0.7b: Punkte (Zeitbonus, Kombos) und Endlosmodus
- **Zeitbonus und Kombos:** Punkte für schnelle Rettung (Restzeit), Serien ohne Schaden (Kombo-Zähler, der bei Schaden oder Verlust bricht), Bonus für alle Gerettete in einem Flug; Anzeige im Einsatz und auf der Wertungskarte; Bestenliste (0.6) nutzt die neuen Punkte. Sterne bleiben nachvollziehbar, bestehende Sternregeln nicht verschlechtern.
- **Endlosmodus:** Menüpunkt, zufällige Einsätze (aus den Bausteinen der sechs Einsätze, Startwert für Wiederholbarkeit), nacheinander und immer schwerer (Stufenkurve), Hubschrauber über die Läufe hinweg begrenzt, eigene Bestenliste (Lauflänge, Punkte). Logik in `RotorwachtCore` mit Tests; muss jederzeit lösbar sein (Autopilot-Test über viele Startwerte).

## Detailentwurf 0.7a (20.11.2026)

Beide Bausteine sind wie `passages` aufgebaut: Daten und reine Funktionen der Zeit im Core (`Obstacles.swift`, `Weather.swift`), Regeln in `MissionSimulation`, Darstellung in der App. Alle Felder in den Einsatzdateien sind optional; ohne `obstacles` und `weather` verhält sich ein Einsatz wie vor 0.7.

### Hindernisse (`obstacles`)

Jedes Hindernis steht auf dem Gelände (`groundHeight`) und ist immer **überfliegbar**: Seine Hülle (größte Breite, Oberkante) liegt mindestens 150 Einheiten unter der Flughöhengrenze, und es steht nie auf einem Rettungspunkt, im Lager, auf einem Außenposten oder in einer Durchfahrt (Abstand mindestens 70 Einheiten; geprüft in `validate`). Zum Durchfliegen taugen nur die Lücken (unter dem Draht, zwischen den Flügeln, wenn der Ausleger weg ist), das ist ein Risiko, kein Zwang.

| Art | Felder | Verhalten und Treffer |
|---|---|---|
| `powerline` | `x`, `x1`, `height` (Aufhängehöhe über Gelände am ersten Mast), `height1` (am zweiten, sonst gleich), `sag` (Durchhang als Anteil der Spannweite, Standard 0.05) | Mast, zwei Querträger, zwei Drähte (übereinander). Treffer: 40 Schaden (alle 0,7 s), Funken. |
| `crane` | `x`, `height` (Turm), `reach` (Ausleger), `period` (Schwenk, s), `phase`, `rope` (Seil, Standard 90) | Ausleger schwenkt: Die Länge, die man von der Seite sieht, ist `reach·cos(2π·t/period + phase)`; Gegenausleger 0,35 davon. Am Ausleger hängt Seil mit Last. Treffer auf Ausleger, Seil, Last oder Turm: Absturz. |
| `cablecar` | `x`, `x1`, `height`, `height1`, `period`, `phase` | Tragseil zwischen zwei Stationen, Gondel fährt in `period` Sekunden hin und zurück (Dreieckswelle, an den Enden langsamer). Treffer auf Gondel: Absturz, auf Seil: 40 Schaden. |
| `windmill` | `x`, `height` (Nabe), `blade` (Flügellänge), `period` (Umlauf, s, Standard 6), `phase` | Drei Flügel, von vorn gesehen drehend. Treffer auf Flügel oder Turm: Absturz. |

- **Treffer:** Der Hubschrauber zählt als drei Kreise übereinander (Kufen, Rumpf, Rotor); Hindernisse sind dicke Strecken (und Kreise für Gondel und Last). Schaden `damage` (Standard je Art) mit Abklingzeit 0,7 s, Absturz = Haltbarkeit 0. Ereignis `obstacleHit(kind:, damage:, x:, y:)`.
- **Zeitfunktionen:** Ausleger, Gondel und Flügel sind reine Funktionen der Einsatzzeit; Darstellung und Treffer nutzen dieselbe Funktion (`Obstacle.shapes(at:in:)`).
- **Hülle:** `Obstacle.envelope(in:)` = (x0, x1, Oberkante). Der Autopilot fliegt über die Hülle (Oberkante + 80) und bremst davor in der Höhe ab; die Tests belegen, dass er auf allen Stufen nie trifft.
- **Stufen:** `damage` × Druck (leicht 0,8, schwer 1,2).

### Wetterwechsel (`weather`)

Eine Liste von Ereignissen je Einsatz, jedes mit `start`, `duration` und `warn` (Vorwarnung in Sekunden), alles Zeitfunktionen:

| Art | Felder | Wirkung |
|---|---|---|
| `gust` | `strength` (Beschleunigung, Vorzeichen = Richtung) | Zusätzliche Böe, sinusförmig wie `wind.gusts`, aber mit Vorwarnung. |
| `windShift` | `strength` | Der Grundwind steigt in 4 s auf `strength`, bleibt `duration` Sekunden und fällt in 4 s zurück. |
| `fog` | `density` (0 bis 0,9), `x0`, `x1` (optional, sonst überall), `tint` (optional: `fog`, `dust`) | Nebelbank: schränkt die Sicht ein (nur Darstellung, keine Regel), blendet in 6 s ein und aus. Je nach Abstand zur Bank hängt die Dichte von `x` ab. |
| `thunder` | `x0`, `x1`, `interval`, `radius`, `damage` | Aufziehendes Gewitter: Der Himmel dunkelt in der Vorwarnung, dann schlagen im Bereich Blitze ein wie bei `storms` (die Gewitterzelle bekommt ein optionales `until`). |

- **Vorwarnung:** Ereignis `weatherWarning(kind:, seconds:)` einmal bei `start − warn`; dazu zeigt ein **Windsack** unten links die Windrichtung und -stärke, blinkt vor einer Böe/einem Windwechsel in der kommenden Richtung, und eine Zeile oben nennt, was kommt („Böen in 6 s von links“, „Nebelbank voraus“, „Gewitter zieht auf“).
- **Anzeige:** Nebel als Deckschicht mit Sichtloch um den Hubschrauber (Größe nach Dichte), Gewitter dunkelt den Himmel und löst die vorhandenen Blitze aus (`AtmosphereLayer`, auch in Einsätzen ohne `atmosphere`).
- **Stufen:** `strength` und `damage` × Druck, `warn` × Warnzeitfaktor, `density` × Druck (höchstens 0,9).
- **Lösbarkeit:** Böen höchstens so stark wie die vorhandenen im Einsatz (Autopilot gleicht aus); Nebel ändert keine Regel; Gewitter nur mit Ausweichen wie bei `storms`.

### Verteilung

| Einsatz | Hindernis | Wetter |
|---|---|---|
| Hochwasser | Hochspannungsleitung über dem Tal | Nebelbank über dem Fluss |
| Waldbrand | Leitung in der Waldschneise | aufziehendes Gewitter |
| Küste | zwei Windräder auf dem Weg zum Lager | Windwechsel und Sturmböen |
| Altstadt | Kran auf einem Dach | Staubwolke (Nebel, `dust`) |
| Vulkan | Seilbahn am Hang | Windwechsel |
| Gebirge | Leitung über dem Tal | Böe mit Vorwarnung und Nebelbank |

### Grafik

Blender (`art/obstacles.py`, `scripts/render-art.sh obstacles`): Mastkopf und Schaftteil (gestapelt), Kranturm-Teil, Ausleger, Last, Seilbahnstütze, Gondel, Windradturm und Flügel (drehend zusammengesetzt aus einem Flügelbild). Drähte und Seile zeichnet die App als Linien.
