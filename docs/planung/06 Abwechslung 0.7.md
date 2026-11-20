# Abwechslung (Block 0.7)

Entscheidung von Lutz am 20.11.2026: Alle vier Ideen gegen die Langeweile (siehe Planung 05, Abschnitt „Weitere Ideen“) kommen in 0.7. Gebaut in zwei Teilen parallel.

## 0.7a: Hindernisse und Wetterwechsel (Gefahren-Bausteine, `RotorwachtCore` `Hazards`/`SimHazards`)
- **Hindernisse** (neuer Baustein `obstacles`, optional in Einsatzdateien): Hochspannungsleitungen (Drähte, Berühren = Schaden bzw. Absturz, Funken), Kräne (Ausleger schwenkt), Seilbahnen mit fahrender Gondel, Windräder (drehende Flügel, Berühren = Absturz). Setzbar in allen sechs Einsätzen, nicht umfliegbar nur dort, wo es Sinn ergibt; Autopilot und Tests müssen weiter alle Einsätze auf allen Stufen lösen.
- **Wetterwechsel** (`weather` als Zeitplan je Einsatz): Wetter ändert sich im Einsatz (Böen, Nebelbänke mit eingeschränkter Sicht, aufziehendes Gewitter, Windwechsel), mit Vorwarnung (Windsack, Anzeige), skaliert nach Stufe. Wetter und Atmosphäre bleiben SpriteKit-Partikel/Ebenen (`AtmosphereLayer.swift`).
- Grafik der Hindernisse als Blender-Modelle (`art/`), Rendern mit `scripts/render-art.sh`.

## 0.7b: Punkte (Zeitbonus, Kombos) und Endlosmodus
- **Zeitbonus und Kombos:** Punkte für schnelle Rettung (Restzeit), Serien ohne Schaden (Kombo-Zähler, der bei Schaden oder Verlust bricht), Bonus für alle Gerettete in einem Flug; Anzeige im Einsatz und auf der Wertungskarte; Bestenliste (0.6) nutzt die neuen Punkte. Sterne bleiben nachvollziehbar, bestehende Sternregeln nicht verschlechtern.
- **Endlosmodus:** Menüpunkt, zufällige Einsätze (aus den Bausteinen der sechs Einsätze, Startwert für Wiederholbarkeit), nacheinander und immer schwerer (Stufenkurve), Hubschrauber über die Läufe hinweg begrenzt, eigene Bestenliste (Lauflänge, Punkte). Logik in `RotorwachtCore` mit Tests; muss jederzeit lösbar sein (Autopilot-Test über viele Startwerte).

## Detailentwurf 0.7b

Stand: gebaut am 20.11.2026 (Sitzung 0.7b). Die Zahlen stehen in `Scoring.swift` und `Endless.swift`; ändert man sie, laufen die Tests neu.

### Punkte

- **Grundregel bleibt:** 100 je Gerettetem, minus 50 je verlorenem Hubschrauber, plus die Restsekunden bei „alle abgearbeitet“. Alte Ergebnisse waren also nie höher als neue (die Boni kommen nur dazu). Bestehende Bestenlisten bleiben gültig, neue Ergebnisse liegen eher darüber.
- **Zeitbonus:** je Gerettetem bis 40 Punkte, anteilig zur Restzeit im Moment der Ankunft im Lager (am Anfang 40, bei halber Zeit 20, am Ende 0).
- **Kombo:** Zähler der Geretteten in Folge. Er bricht, sobald der Hubschrauber Haltbarkeit verliert (Treffer, harte Landung, Hitze, Blitz, Wand), jemand verloren geht oder verletzt wird, oder der Hubschrauber verloren ist. Reparatur im Lager bricht ihn nicht. Bonus je Gerettetem: 5 je früherem Glied der Kette, höchstens 50 (ab dem 11. Glied).
- **Flugbonus** beim Aussteigen im Lager: 50 bei voller Kabine, 300, wenn **alle** Menschen des Einsatzes (mindestens zwei) in einem Flug ankommen. Je Flug einmal.
- **Sterne bleiben unberührt:** sie hängen weiter nur an Gerettetenanteil und verlorenen Hubschraubern. Bestenliste und Wertungskarte nehmen die neue Punktzahl.
- **Anzeige:** im Einsatz „Punkte“ (und bei Kette ≥ 2 „Kombo ×n“) oben, kurze Meldungen „+140 Punkte · Kombo ×3“, „Kombo ×5 abgebrochen“ (ab Länge 3), „Voller Flug …“. Auf der Wertungskarte die Zeilen Bonus Zeit, Bonus Kombo (längste Serie), Bonus Flüge.

### Endlosmodus

- **Aufbau eines Einsatzes:** Grundlage ist einer der sechs Einsätze (Gelände, Rettungspunkte, Look, Musik bleiben). Die sechs kommen in je einer gemischten Runde dran (Reihenfolge aus dem Startwert, nie zweimal derselbe hintereinander).
- **Abwandlung nach Startwert:** Rettungspunkte weglassen (nur in Einsätzen ohne „Uhr“, also ohne Lava, Feuer, steigendes Wasser), Menschenzahl je Punkt ändern (1 bis 6, wächst mit der Stufe; in Einsätzen mit Uhr nie über das Original), Zeit folgt der Arbeit, Böen des Originals verschieben sich. Waldbrand bekommt einen um 35 % größeren Tank, weil das Löschen weit vom Lager Treibstoff frisst.
- **Bausteine, zentrale Liste `EndlessKit.blocks`:** Gewitter (ab Stufe 2, nur auf der Strecke zwischen letztem Rettungspunkt und Lager, damit sie Flüge treffen, aber nicht die Arbeit am Landeplatz), Trümmer (ab 3, nur wo es sonst keine Salven gibt und kein Wasser steigt), Zusatzböen, Dauerwind (nur ohne Durchfahrten und ohne Seilwinde), durstiger Motor (nur ohne Außenposten und ohne Hochgebirge), trockener Wald (nur mit Feuer). Jeder Baustein hat `minStage`, `fits` (passt er zu diesem Einsatz?) und `apply` (mit Druck 0 bis 1). **Neue Bausteine** (0.7a: `obstacles`, `weather`) kommen als ein Eintrag in diese Liste dazu; der Generator wählt sie dann von selbst. Der Autopilot-Test zeigt sofort, ob damit etwas unlösbar wird.
- **Stufenkurve:** Stufe 1 und 2 Leicht, 3 bis 5 Mittel, ab 6 Schwer (die vorhandene Skalierung `scaled(for:)`), Druck wächst bis Stufe 12 von 0 auf 1 (Anzahl der Bausteine 1 bis 4, stärkere Werte), ab Stufe 9 zusätzlich bis zu 25 % weniger Zeit und bis 50 % härtere Treffer.
- **Hubschrauberbestand:** 5 zu Beginn für den ganzen Lauf, jede Stufe wird mit dem Rest geflogen, nach je 3 geschafften Stufen kommt einer dazu (höchstens 6). Eine Stufe ist geschafft mit mindestens einem Stern (Hälfte gerettet) und mindestens einem Hubschrauber übrig; sonst endet der Lauf.
- **Wertung des Laufs:** Summe der Stufenpunkte plus 50 × Stufennummer je geschaffter Stufe. **Eigene Bestenliste** (`endless.json`): Stufen, dann Punkte, Top 10, Name wie bei den Einsätzen. Endlos-Ergebnisse berühren weder die Listen der Einsätze noch den Fortschritt.
- **Wiederholbar:** gleicher Startwert, gleiche Folge. Der Startwert wird bei jedem Lauf zufällig gezogen (noch nicht angezeigt oder eingebbar).
- **Lösbarkeit:** `EndlessTests` lässt den Autopiloten jede Grundlage auf den Stufen 1, 4, 8, 13, 20 mit je 6 Startwerten fliegen; es muss mindestens die Hälfte gerettet werden und der Bestand darf nicht aufgebraucht sein. Bei der Entwicklung liefen zusätzlich 720 Läufe (12 Startwerte, 10 Stufen bis 30) ohne einen Ausfall. Die Probe hat Bausteine aussortiert oder eingeschränkt (Dauerwind im Tunnel, Trümmer unter steigendem Wasser, Gewitter auf den Landeplätzen, Menschenzahl bei Lava und Feuer).
