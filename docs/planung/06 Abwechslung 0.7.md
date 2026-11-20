# Abwechslung (Block 0.7)

Entscheidung von Lutz am 20.11.2026: Alle vier Ideen gegen die Langeweile (siehe Planung 05, Abschnitt „Weitere Ideen“) kommen in 0.7. Gebaut in zwei Teilen parallel.

## 0.7a: Hindernisse und Wetterwechsel (Gefahren-Bausteine, `RotorwachtCore` `Hazards`/`SimHazards`)
- **Hindernisse** (neuer Baustein `obstacles`, optional in Einsatzdateien): Hochspannungsleitungen (Drähte, Berühren = Schaden bzw. Absturz, Funken), Kräne (Ausleger schwenkt), Seilbahnen mit fahrender Gondel, Windräder (drehende Flügel, Berühren = Absturz). Setzbar in allen sechs Einsätzen, nicht umfliegbar nur dort, wo es Sinn ergibt; Autopilot und Tests müssen weiter alle Einsätze auf allen Stufen lösen.
- **Wetterwechsel** (`weather` als Zeitplan je Einsatz): Wetter ändert sich im Einsatz (Böen, Nebelbänke mit eingeschränkter Sicht, aufziehendes Gewitter, Windwechsel), mit Vorwarnung (Windsack, Anzeige), skaliert nach Stufe. Wetter und Atmosphäre bleiben SpriteKit-Partikel/Ebenen (`AtmosphereLayer.swift`).
- Grafik der Hindernisse als Blender-Modelle (`art/`), Rendern mit `scripts/render-art.sh`.

## 0.7b: Punkte (Zeitbonus, Kombos) und Endlosmodus
- **Zeitbonus und Kombos:** Punkte für schnelle Rettung (Restzeit), Serien ohne Schaden (Kombo-Zähler, der bei Schaden oder Verlust bricht), Bonus für alle Gerettete in einem Flug; Anzeige im Einsatz und auf der Wertungskarte; Bestenliste (0.6) nutzt die neuen Punkte. Sterne bleiben nachvollziehbar, bestehende Sternregeln nicht verschlechtern.
- **Endlosmodus:** Menüpunkt, zufällige Einsätze (aus den Bausteinen der sechs Einsätze, Startwert für Wiederholbarkeit), nacheinander und immer schwerer (Stufenkurve), Hubschrauber über die Läufe hinweg begrenzt, eigene Bestenliste (Lauflänge, Punkte). Logik in `RotorwachtCore` mit Tests; muss jederzeit lösbar sein (Autopilot-Test über viele Startwerte).
