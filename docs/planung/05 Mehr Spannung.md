# Mehr Spannung: Durchfahrten und Bestenliste

Rückmeldung von Lutz am 20.11.2026 nach dem Anspielen von 0.5.0: Es ist noch zu langweilig. Wünsche: eine **Unterführung**, durch die man fliegen muss, einen **Tunnel mit Shuttern (Rolltoren), die auf- und zugehen**, und eine **Score-Liste**. Bleibt man im Shutter hängen, ist ein Hubschrauber weg.

## Entscheidungen (Annahmen von Claude, Lutz kann ändern)

### Durchfahrten (neuer Gefahren-Baustein `passages`)
- **Unterführung:** Brücke, Überführung oder Viadukt, deren Durchflug nur eine begrenzte Höhe frei lässt (nur wenig mehr als Hubschrauberhöhe plus Rotor). Berührt der Hubschrauber Decke oder Pfeiler, gibt es Schaden bzw. Absturz.
- **Tunnel mit Shuttern:** geschlossener Tunnel mit Länge, durch den man hindurch muss. An Eingang, Ausgang und optional dazwischen sitzen Shutter, die nach festem Takt auf- und zugehen. Ein Ampellicht (rot/grün) und ein kurzes Klacken kündigen das Schließen an (Vorwarnzeit wie bei Blitzen, nach Stufe). **Wird der Hubschrauber vom Shutter getroffen oder bleibt er stecken: dieser Hubschrauber ist verloren** (wie ein Absturz, Ersatz aus dem Lager, wenn noch welche da sind).
- Innen ist es dunkel: Scheinwerfer des Hubschraubers leuchtet, Rettungspunkte dürfen auch im Tunnel liegen (Wartende in einer Nische).
- Die Durchfahrt liegt so, dass man sie **nicht umfliegen kann** (Tunnel durch einen Berg, Unterführung unter einer durchgehenden Brücke bis zur Flughöhengrenze); mindestens ein Rettungspunkt oder das Lager liegt dahinter.
- Stufen (leicht, mittel, schwer) skalieren Taktzeit, Offenzeit, Vorwarnzeit und Höhe der Öffnung.
- Einsätze: Unterführungen in Einsatz 4 Altstadt und 1 Hochwasser (Brücken), Tunnel mit Shuttern in Einsatz 6 Hochgebirge (Lawinengalerie) und 5 Vulkan (Tunnel durch den Hang); alle Felder in der Einsatzdatei optional wie die anderen Bausteine.
- Grafik: Tunnel, Brücke und Shutter als Blender-Modelle (`art/`), Shutter als bewegliche SpriteKit-Teile; Autopilot kann Durchfahrten (für Tests und Bildschirmfotos).

### Bestenliste
- Je Einsatz und Stufe eine Liste der besten Ergebnisse (Top 10: Punkte, Sterne, Datum, Name), lokal gespeichert wie der Fortschritt (`~/Library/Application Support/Rotorwacht/`).
- Name vor dem ersten Eintrag einmal abfragen (Standard: Benutzername), änderbar in den Einstellungen.
- Anzeige im Menü (Bestenliste je Einsatz/Stufe) und auf der Wertungskarte (eigener Platz hervorgehoben).

## Detailentwurf `passages` (Version 0.6.0)

Entworfen vor dem Bauen, 20.11.2026. Alle Felder in der Einsatzdatei sind optional (`passages` fehlt = wie bisher).

### Daten (`Passage`, `Shutter`)
- `Passage`: `id`, `kind` (`"bridge"` Unterführung oder `"tunnel"`), `x0`/`x1` (Spanne in Weltkoordinaten), `roof` (Höhe der Unterseite der Decke, absolut), `shutters` (nur Tunnel, optional).
- Der **Boden** ist nie Teil der Daten: `floorRef = max(höchste Geländehöhe in der Spanne, höchster Wasserstand der Welt)`. Die Decke muss mindestens `Passage.heliHeight + 36` über `floorRef` liegen (Prüfung in `validate`), Geländeprofil in der Spanne bleibt unverändert (bei Tunneln eben).
- `Shutter`: `x`, `period` (Sekunden je Zyklus), `open` (Sekunden voll offen je Zyklus), `phase` (Verschiebung), `warn` (Vorwarnzeit vor dem Schließen), `gap` (Höhe der Öffnung über dem Boden, wenn offen; Standard bis zur Decke), `move` (Bewegungszeit, Standard 0,6 s). Pflicht: `period > open + 2·move + 0,5`.

### Zyklus eines Shutters (rein rechnerisch aus der Zeit, ohne eigenen Zustand)
`u = (t + phase) mod period`: `u < open` offen; danach `move` s Schließen (Torunterkante fährt von `floorRef + gap` auf den Boden); geschlossen bis `period − move`; dann `move` s Öffnen. Ampel: **grün** (offen, noch keine Warnung), **gelb blinkend** ab `open − warn` bis Schließbeginn, **rot** ab Schließbeginn bis wieder ganz offen. Ereignisse: `shutterWarning` (Klacken, Gelb beginnt) und `shutterClosing` (Rot beginnt), je einmal je Zyklus.

### Kollisionsregeln (nach der Physik, nur solange der Hubschrauber fliegt)
Hubschrauberkörper: Breite `±36`, Höhe `heliHeight = 70` (Kufen bis Rotorkopf).
1. **Shutter:** Liegt `|heli.x − shutter.x| < 36 + 8` und die Torunterkante unter der Rotoroberkante (`heli.y + 70`) und `heli.y < Decke`, ist **dieser Hubschrauber verloren** (Haltbarkeit 0, normaler Absturz mit Ersatz aus dem Lager). Gilt auch, wenn das Tor von oben auf den Hubschrauber fährt (Steckenbleiben). Kein Schaden-Zwischenschritt.
2. **Decke (Mitte des Hubschraubers in der Spanne):** `heli.y` wird auf `Decke − 70` begrenzt, Steigen gestoppt, Schaden `8 + 0,15·Steiggeschwindigkeit` einmalig je Berührung (Sperre 0,5 s) plus 40 je Sekunde Dauerkontakt. Ereignis `passageContact`.
3. **Stirnwand (Mitte außerhalb der Spanne, aber weniger als 36 davor, und `heli.y + 70 > Decke`):** `x` wird an die Kante gesetzt, Geschwindigkeit nach innen gestoppt, Schaden `0,12·|vx|` einmalig je Berührung. So **kann man nicht darüber fliegen**: Über der Decke ist die Spanne bis zur Flughöhengrenze Masse (Brückenbauwerk bzw. Berg).
4. Fliegende Objekte (Lavabrocken, Trümmer), die über der Decke in die Spanne geraten, verschwinden; **Ströme** (Lava, Lawine) schaden im Tunnel nicht (Lawinengalerie als Schutz).

### Stufen (`Mission.scaled`)
- Takt: `open` × `warning` (leicht 1,3 / schwer 0,8), geschlossene Zeit × (2 − `warning`); `warn` × `warning`.
- Öffnung: Decke − `floorRef` × (leicht 1,15 / schwer 0,9), nie unter `heliHeight + 36`; `gap` entsprechend.

### Autopilot und Planung
- `Passage.canCross(...)` prüft für jeden Shutter in Fahrtrichtung, ob er zur geplanten Ankunftszeit (Abstand / 170 + 0,5 s Anlauf) von −0,8 s bis +0,9 s durchgehend begehbar ist (Torunterkante mindestens 18 über Hubschrauberhöhe). Der Autopilot wartet 140 vor dem Portal in Korridorhöhe, bis das Fenster passt, und fliegt dann mit 190 durch; ein Test prüft für jeden Einsatz und jede Stufe, dass ein Fenster in beide Richtungen existiert und der Autopilot keinen Hubschrauber verliert.
- Rettungspunkte liegen **nicht** im Tunnel (der Hubschrauber wartet nie zwischen Toren; Nischen bleiben eine spätere Idee).

### Einbau in die Einsätze (ohne Geländeänderung)
Hochwasser: Brücke über Wasser bei 3150–3400 (Decke 350, über dem höchsten Wasser 200; die Öffnung schrumpft mit der Flut). Altstadt: Brücke 5820–6040 über dem ebenen Platz vor dem Lager (Decke 250). Vulkan: Tunnel 6060–6560 vor dem Lager. Hochgebirge: Lawinengalerie 5900–6450 vor dem Lager. Alle liegen zwischen Lager und allen Rettungspunkten.

### Bestenliste
`HighScores` in `RotorwachtCore`: je `"<Einsatz>|<Stufe>"` Top 10 nach Punkten (dann Sterne, dann früher), `ScoreEntry` (Name, Punkte, Sterne, Datum). Name auf 16 Zeichen gekürzt, leer = „Pilot“; Datei `highscores.json` neben `progress.json`. Einträge mit 0 Punkten kommen nicht in die Liste.

## Weitere Ideen gegen Langeweile (noch nicht entschieden)
Mehr Abwechslung je Einsatz, Kombo-/Zeitbonus für schnelle Rettung, Hindernisse wie Hochspannungsleitungen und Kräne, wechselnde Wetterlagen, Endlosmodus. Lutz sagt, welche.
