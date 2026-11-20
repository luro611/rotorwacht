# Feinschliff 0.8

Stand: 20.11.2026. Lutz hat „Block 8“ gesagt; seine Anspiel-Rückmeldung zu 0.5 bis 0.7 kommt später und wird Block 0.9. Dieser Block bringt nur Feinschliff, keine neuen Spielregeln. Lutz kann den Inhalt ändern.

## Inhalt

1. **Niedrige Befunde der Opus-Prüfungen beheben.** Quelle: Notizordner `/Users/luro/Library/Application Support/Claude/side-session-notes/local_842cd3b7-4ed7-49fa-b0f2-aded391d01d8/` (`pruefung-0.7.md`). Die Befunde zu 0.5 und 0.6 stehen nur in archivierten Prüf-Sitzungen und entfallen. Zuerst prüfen, ob der Bericht überhaupt niedrige Befunde nennt und ob sie in `main` noch gelten. Dazu gehört der Endlos-Generator: Er soll `obstacles` und `weather` der Grundlagen berücksichtigen (die vier Fehler in `EndlessTests.autopilotSolvesGeneratedEinsaetze` aus der Prüfung gelten vermutlich schon als behoben, 191 Tests grün; mit `scripts/test.sh` bestätigen).
2. **Grafikpunkte aus `CLAUDE.md`:** Nacht-Einsatz Küste ist sehr dunkel (Lichtstimmung, Lesbarkeit von Hubschrauber, Gelände, Menschen verbessern); Fernberge im Hochwasser-Einsatz wirken zu wuchtig (zurücknehmen). Änderungen in `art/` bzw. den Ebenen, neu rendern mit `scripts/render-art.sh`.
3. **Doku auf 0.7 bringen:** `README.md` und die Bildschirmfotos in `docs/bilder` (Erzeugung mit `ROTORWACHT_SHOTS`, siehe `CLAUDE.md`). `CLAUDE.md` (Stand) und `CHANGELOG.md` (Abschnitt 0.8.0) nachführen.

## Nicht Teil von 0.8

Spielgefühl, Klang, neue Einsätze oder Regeln. Das folgt mit Lutzens Rückmeldung in 0.9.

## Fertig, wenn

- Tests grün, App baut, Fotos und README aktuell.
- Kein Tag, kein Push, kein Merge; danach Opus-Prüfung (einmal), Merge und Push erst auf Lutzens Wort.
