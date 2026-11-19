# Changelog

Versionen: 0.x bis zum ersten fertigen Stand, dann 1.0.0.

## [0.2.1] – 2026-11-19

Behebung der Befunde aus der Opus-Prüfung von 0.1.0.

- Leerer Tank auf festem Boden außerhalb des Lagers: nach 2,5 s gilt der Hubschrauber als verloren, Ersatz kommt ins Lager (vorher hing das Spiel bis zum Zeitende).
- Wartende Person blieb nach unterbrochenem Einsteigen halb durchsichtig.
- Flut-Meldung einmal je Rettungspunkt statt je Person.
- Landeerkennung am Rettungspunkt bis zur Kufenbreite des Hubschraubers (stand auf dem Dach, aber niemand stieg ein).
- Texturen für Partikel (Dampf, Regen, Flammen, Tropfen, Brandspuren, Markierung) werden einmal erzeugt statt bei jedem Aufruf; Wellenlinien nur noch mit 30 Hz.
- Ton: keine Speicherzuteilung mehr auf dem Audio-Thread; Beenden stoppt und löst die Audio-Engine.
- `Mission.validate()` prüft Einsatzdateien (Böen ohne Dauer, doppelte Geländepunkte, Größen); Fehler im JSON werden nicht mehr als „nicht gefunden“ gemeldet.
- Neue Tests: Sackgasse, Dachkante, Prüfung der Einsätze, Schrittweiten-Unabhängigkeit (64 Tests).

## [0.2.0] – 2026-11-19

Löschen und Waldbrand.

- **Löschwasser auf der Leertaste:** Tank mit Füllanzeige („Wasser“), Füllen im Tiefflug (unter etwa 55 Einheiten) über Fluss, See oder Flut sowie im Lager, Abwurf als einzelne Tropfen, die die Fluggeschwindigkeit mitnehmen und dann fallen (Trägheit, Wind).
- **Feuer als Spielmechanik:** Brände breiten sich Zelle für Zelle über brennbares Gelände aus, bergauf und mit dem Wind schneller, brennen aus und hinterlassen Asche. Wasser kühlt und macht den Boden nass; nasser Boden brennt nicht, ein Wasserstreifen vor der Flammenfront hält sie auf.
- Feuer bedroht Rettungspunkte: Wartende werden erst gewarnt, nach gut zehn Sekunden Nähe zu den Flammen verletzt. Rauch nimmt die Sicht, Hitze kostet Haltbarkeit.
- **Einsatz 2 „Waldbrand am Hang“** (24 Menschen, zwei Seen, drei Brandherde, Wind bergauf) als `waldbrand.json`. Neue Einsatzfelder (Tank, Seen, Brennzonen, Zündungen) sind optional, Einsatz 1 bleibt unverändert.
- **Einsatzauswahl** im Startmenü (Einsatz 1 und 2), Wertung und Anzeige je Einsatz.
- Grafik: Feuer, Rauch, Wasserdampf und Tropfen als Partikel, Brandspuren am Boden, Rauch- und Hitzeschleier; Seen mit Wellen. Ton: Feuerprasseln, Zischen beim Abwurf, Plätschern beim Füllen, Zündgeräusch.
- Anzeige: Wasserbalken, Brandmarken in der Übersichtsleiste.
- 23 neue Tests (Tank, Abwurf, Ausbreitung, Löschen, Wind, Hang, Gefahr für Wartende, Hitze, Rauch, Laden von Einsatz 2, Autopilot-Probe).

## [0.1.0] – 2026-11-19

Erster spielbarer Stand.

- Einsatz 1 „Hochwasser im Flusstal“ von Start bis Wertung: 28 Menschen auf Dächern, Anhöhen und einem Wasserturm, Lager mit Landeplatz am rechten Rand, steigende Flut, Böen, Regen.
- Fliegen mit Trägheit und Neigung, Wenden, sanftes Landen (zu hart oder zu schnell kostet Haltbarkeit), Ein- und Aussteigen, 12 Plätze, Treibstoff, Haltbarkeit, 3 Hubschrauber, Esc = Pause.
- Wertung mit Sternen; Menschen, die das Wasser erreicht, gelten als verloren.
- Platzhaltergrafik aus Code mit Parallax (Himmel, Berge, bewaldete Hügel, Spielebene), Abwind-Staub und Gischt, Windsack, synthetisierter Rotor-, Wind- und Signalton.
- Anzeige: Treibstoff, Haltbarkeit, an Bord, gerettet/gesamt, Zeit, Hubschrauber, Übersichtsleiste. Startbildschirm, Pause und Wertung in der lurohome-Designsprache mit luro-Siegel und Wortmarke.
- Einsatzdaten als JSON (`Sources/RotorwachtCore/Missions/hochwasser.json`).
- 35 Unit-Tests (Flugphysik, Landen, Ein-/Aussteigen, Flut, Absturz, Wertung, Autopilot-Probe).
- Bauen ohne Xcode: `scripts/build.sh`, `scripts/test.sh`.
