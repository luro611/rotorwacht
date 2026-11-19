# Changelog

Versionen: 0.x bis zum ersten fertigen Stand, dann 1.0.0.

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
