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

## Weitere Ideen gegen Langeweile (noch nicht entschieden)
Mehr Abwechslung je Einsatz, Kombo-/Zeitbonus für schnelle Rettung, Hindernisse wie Hochspannungsleitungen und Kräne, wechselnde Wetterlagen, Endlosmodus. Lutz sagt, welche.
