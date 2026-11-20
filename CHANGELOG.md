# Changelog

Versionen: 0.x bis zum ersten fertigen Stand, dann 1.0.0.

## [0.4.0] – 2026-11-20

Grafik-Überarbeitung: alles aus gerenderten 3D-Modellen (Blender, per Python-Skript, `art/`).

- **Hubschrauber:** moderner zweimotoriger Rettungshubschrauber (eigenes Design, rot-weiß) mit ummanteltem Heckrotor, Seilwinde, Suchscheinwerfer und Kufen; 9 Blickwinkel für das Wenden von links über die Frontansicht nach rechts, drehender Rotor als Scheibe, blinkende Lichter, Schatten auf dem Untergrund.
- **Menschen:** fünf Figurtypen mit Winken, Laufen, Einsteigen und Hochziehen; die Füße stehen immer auf der Fläche (Fehler „schwebende Personen“ behoben).
- **Landeplätze:** jeder Rettungspunkt hat eine erkennbare, ebene Landefläche mit H-Markierung (Dach, Turm, Plattform, Wiese, Pflaster, Bootsdeck, Leuchtturm); mindestens so breit wie die Kufen, die Wartenden stehen am Rand. Seilwinden-Vorsprünge haben eine Markierung. Einsatzdateien entsprechend angepasst (Geländeplateaus, breitere Flächen, Altstadt-Plätze).
- **Gelände, Gebäude und Panoramen** je Einsatz gerendert (Gras, Erde, Fels, Schnee, Asche, Häuserfassaden, Bäume, Felsen, ferne Berge und Hügel); Wetter und Feuer bleiben SpriteKit-Partikel.
- Lager als gerendertes Bild mit ebener Fläche.
- Tests: neue `PadTests` (Fläche eben und breit genug, Personen auf der Fläche, Sprites vorhanden); zusammen 99.
- Werkzeug: Blender (`brew install --cask blender`), `scripts/render-art.sh` erzeugt alle Bilder neu; die Bilder liegen im Repository (`Sources/Rotorwacht/Renders`, etwa 50 MB).

## [0.3.0] – 2026-11-19

Die Einsätze 3 bis 6 und die Kampagne.

- **Einsatz 3 „Sturmnacht an der Küste“:** Nacht mit Scheinwerferkegel am Hubschrauber und Leuchtfeuern an den Rettungspunkten, Gewitterzellen mit Blitzschlag (roter Strahl und Kreis kündigen jeden Blitz vorher an), Seegang mit Wellen und Gischt, Rettungspunkte auf Klippen, einem Fischkutter und dem Leuchtturm.
- **Einsatz 4 „Erdbeben in der Altstadt“:** enge Plätze und Gassen zwischen Häuserzeilen, Dachlandeplätze; Nachbeben kündigen sich mit Grollen und Kamerawackeln an, Trümmer fallen, treffen den Hubschrauber und sperren Landeplätze, bis der Schutt geräumt ist; Staubwolken.
- **Einsatz 5 „Vulkanausbruch auf der Insel“:** Ascheregen nimmt die Sicht, Lavabrocken fliegen auf angezeigten gestrichelten Flugbahnen, ein Lavastrom läuft den Hang hinab und nimmt Rettungspunkte, knapper Treibstoff mit Außenposten zum Tanken.
- **Einsatz 6 „Lawinen im Hochgebirge“:** Seilwinde statt Landen auf Felsvorsprüngen (über dem Vorsprung schweben, ruhig halten, nicht höher als das Seil; Pfeil runter holt das Seil näher, keine neue Taste), starker Wind, Lawinen als Gefahr.
- **Neue Gefahren als wiederverwendbare Bausteine** in `RotorwachtCore` (`Hazards.swift`, `SimHazards.swift`), in den Einsatzdateien frei kombinierbar: Gewitterzelle (`storms`), fallende und fliegende Objekte (`volleys`: Trümmer, Lavabrocken, Felsen), Bodenströme (`flows`: Lava, Lawine), Seilwinde (`access: "winch"`), Außenposten (`outposts`), Seegang (`flood.swell`), Atmosphäre (`atmosphere`: Nacht, Asche, Schnee, Staub) und Landschaftsstil (`look`).
- **Drei Stufen** (leicht, mittel, schwer) je Einsatz: skalieren Zeit, Hubschrauber (4/3/2), Treibstoffverbrauch, Wind, Flut- und Feuertempo, Schaden und Tempo der Gefahren sowie die Vorwarnzeit. Mittel ist der Wert der Datei.
- **Einsatzauswahl für alle sechs:** der nächste Einsatz wird frei, sobald der vorige mit mindestens einem Stern geschafft ist (auf irgendeiner Stufe). Sterne und Punkte je Einsatz und Stufe werden lokal gespeichert (`~/Library/Application Support/Rotorwacht/progress.json`).
- Autopilot kann jetzt Seilwinde, Außenposten, Blitze und gesperrte Plätze (für die Tests und Bildschirmfotos).
- Ton: Donner, Grollen, Lavaknall. Anzeige: Seilwinden-Balken, Lava- und Lawinenstrecken und Außenposten in der Übersichtsleiste.
- 30 neue Tests (Blitz, Salven und Nachbeben, Flugbahn, Lava, Lawine, Seilwinde, Außenposten, Seegang, Asche, Stufen, Fortschritt und Freischalten, Laden und Autopilot aller sechs Einsätze auf allen drei Stufen); zusammen 94.

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
