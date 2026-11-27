# Neue Einsätze und fünf Stufen (Block 0.9)

Entscheidung von Lutz am 27.11.2026.

## Fünf Stufen
- Anfänger, leicht, mittel, schwer, Profi (bisher: leicht, mittel, schwer). **Mittel bleibt unverändert** (Wert der Einsatzdatei).
- Bestenlisten und Fortschritt der drei bisherigen Stufen bleiben erhalten (alte Dateien müssen weiter geladen werden).
- Anfänger verzeiht deutlich mehr (mehr Hubschrauber, mehr Treibstoff, lange Vorwarnung); Profi ist spürbar härter (wenige Hubschrauber, knapper Treibstoff, kurze Vorwarnung, schnelle Shutter), muss aber lösbar bleiben (Autopilot-Tests).
- Gilt für alle Einsätze, Übungsmodus, Endlosmodus und Menü.

## Vier neue Einsätze (7 bis 10)
- **Bohrinsel im Sturm:** schwankende Plattform auf offener See, Brand an Bord (Löschen), Seilwinde, hohe Wellen, Kran.
- **Schlucht und Staudamm:** Dammbruch, enge Schlucht, Flutwelle von hinten, Brücken zum Unterfliegen.
- **Schneesturm am Pass:** eingeschneite Autos und Berghütten, Whiteout, Vereisung (träger Hubschrauber, nach Enteisung am Lager wieder frei), Tunnel mit Shuttern.
- **Wüste mit Sandsturm:** verschüttete Karawane oder Forschungsstation, Sandsturm mit Sichtverlust, Hitze (höherer Verbrauch), Außenposten zum Tanken.

Jeder Einsatz bekommt eigenes Gelände und Panorama (Blender, `art/`), eigenes Musikthema, Einsatztext, Bestenliste und Übungsstrecke, wo sinnvoll. Freischalten wie bisher der Reihe nach. Der Endlosmodus nutzt die neuen Bausteine mit.

## Detailentwurf

Stand 0.9.0 (Bau). Alle Felder sind optional, bestehende Einsätze ändern sich nicht.

### Fünf Stufen (Faktoren; mittel = Wert der Einsatzdatei)

| | Anfänger | leicht | mittel | schwer | Profi |
|---|---|---|---|---|---|
| Zeit | 1,6 | 1,3 | 1 | 0,85 | 0,75 |
| Druck (Treibstoff, Wind, Wasser, Feuer, Schaden) | 0,6 | 0,8 | 1 | 1,2 | 1,35 |
| Vorwarnzeit | 1,7 | 1,3 | 1 | 0,8 | 0,65 |
| Shutter offen | 1,6 | 1,3 | 1 | 0,8 | 0,74 |
| Durchfahrtshöhe | 1,3 | 1,15 | 1 | 0,9 | 0,85 |
| Hubschrauber | 6 | 4 | 3 | 2 | 1 |

Anfänger und Profi verschieben zudem die Phase der Shutter mit dem Takt, sonst gäbe es bei zwei Toren kaum ein Fenster. Endlosmodus: Die gewählte Stufe verschiebt die Rampe (leicht, mittel, schwer je Stufennummer) um bis zu zwei Schritte; Bestand zu Beginn 7 bis 3 Hubschrauber; Bestenliste je Stufe (die alte Liste ist die von „mittel“).

### Neue Bausteine

- **Schwankende Plattform** (`rescuePoints[].heave`: `amplitude`, `period`, `phase`): Die Landefläche hebt und senkt sich sinusförmig. Ein gelandeter Hubschrauber fährt mit; die Wartenden auch. Landen auf der steigenden Fläche ist wie auf festem Grund. Stufen: Hub × Druck.
- **Vereisung** (`icing`: `rate`, `thaw`, `start`): Während des Flugs wächst der Eisbelag (0…1), am Boden im Lager oder Außenposten taut er ab. Eis macht den Hubschrauber träge: Schub bis −45 %, Steigrate bis −35 %. Anzeige „Eis“ im HUD. Stufen: Wachstum × Druck.
- **Hitze** (`heatwave`: `base`, `pulses`): Treibstoffverbrauch × (1 + Hitze), Steigrate × (1 − 0,25 × Hitze). Anzeige „Hitze“ im HUD. Stufen: × Druck.
- **Flutwelle** (`flows[].kind = "surge"`): wie Lava (bleibt stehen), aber Wasser, das alles mitnimmt.
- **Sandsturm / Whiteout:** kein neuer Regelbaustein, sondern `fog` mit `tint` „sand“ bzw. „snow“ zusammen mit Windwechseln; die App zeichnet zusätzlich treibenden Sand bzw. Schneetreiben.

### Einsätze 7 bis 10

7. **Bohrinsel im Sturm** (`bohrinsel`): zwei Bohrplattformen mit Brand an Deck (Löschwasser aus dem Meer), Versorgungsschiff und Rettungsfloß (schwankend), ein Kranmast mit Seilwinde, Gewitterzellen, hoher Seegang; Lager an der Küste rechts.
8. **Schlucht und Staudamm** (`staudamm`): Flutwelle vom gebrochenen Damm im Westen, Felsnadeln, zwei Brücken zum Unterfliegen, Menschen auf dem Talgrund zuerst in Gefahr.
9. **Schneesturm am Pass** (`pass`): eingeschneite Autos und Berghütten, Whiteout, Vereisung, Außenposten zum Enteisen und Tanken, Lawinengalerie mit Shuttern.
10. **Wüste mit Sandsturm** (`wueste`): verschüttete Karawane und Forschungsstation, Sandstürme, Hitze, zwei Außenposten.

### Nachtrag aus der Prüfung

- Endlosmodus: Jeder erzeugte Einsatz wird vorab per Autopilot geflogen (mindestens ein Stern mit zwei Hubschraubern) und sonst schrittweise entschärft: ohne Zusatzbausteine, weniger Menschen und mehr Zeit, dann eine Datenstufe leichter. Der Nachweis gilt für den Autopiloten, nicht für das Spielgefühl.
- Flutwelle: Brücken schützen nicht, nur Tunnel.
