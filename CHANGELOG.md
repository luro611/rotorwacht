# Changelog

Versionen: 0.x bis zum ersten fertigen Stand, dann 1.0.0.

## [0.6.0] – 2026-11-20

Mehr Spannung (Rückmeldung von Lutz nach 0.5.0: zu langweilig): Durchfahrten und eine Bestenliste. Entwurf und Regeln: `docs/planung/05 Mehr Spannung.md`.

### Durchfahrten (`passages`)

- **Neuer Gefahren-Baustein:** Unterführung (`bridge`) und Tunnel (`tunnel`) mit Shuttern. Alle Felder in der Einsatzdatei sind optional. Über der Decke ist die Spanne bis zur Flughöhengrenze massiv (Brückenbauwerk, Fels): Man kann **nicht darüber fliegen**, nur hindurch.
- **Shutter** gehen nach festem Takt auf und zu (`period`, `open`, `phase`, `warn`, `gap`, `move`). Ampel an beiden Seiten: grün offen, **gelb blinkend** mit Klacken in der Vorwarnzeit, rot ab Schließbeginn. **Wird der Hubschrauber getroffen oder bleibt er im Tor stecken, ist er verloren** (Ersatz aus dem Lager).
- **Decke und Stirnwand:** Berührung der Decke drückt nach unten und kostet Haltbarkeit; wer von der Seite hineinfliegt, wird gestoppt und beschädigt. Fliegende Objekte über der Decke verschwinden, Lawinen und Lava schaden im Tunnel nicht (die Galerie schützt).
- **Stufen** skalieren Takt (offene und geschlossene Zeit), Vorwarnzeit und Höhe der Öffnung (leicht 1,15 / schwer 0,9 der Öffnungshöhe, nie unter Hubschrauberhöhe plus 36).
- **Einsätze:** Brücke in 1 Hochwasser (die Öffnung schrumpft mit der Flut) und 4 Altstadt (Unterführung vor dem Lager), Tunnel mit zwei Shuttern in 5 Vulkan (Hangtunnel) und 6 Hochgebirge (Lawinengalerie). Alle liegen zwischen Lager und den Rettungspunkten (in 1 teils), kein Gelände geändert. Rettungspunkte liegen nicht im Tunnel.
- **Autopilot** (für Tests und Bildschirmfotos): wartet vor dem Tor in Korridorhöhe, bis ein Zeitfenster für alle Tore passt (`Passage.canCross`), fliegt dann durch und steigt danach langsam über das Gelände.
- **Grafik:** Felswand und Betonbauwerk über dem Durchflug sowie Shutter-Teile (Lamellen, Warnleiste, Gehäuse, Lampen) sind Blender-Modelle (`art/passages.py`, `scripts/render-art.sh passages`); die Shutter fahren als bewegliche SpriteKit-Teile, das Tunnelinnere ist dunkel mit Deckenlampen, der Scheinwerfer des Hubschraubers leuchtet die Umgebung an (`PassageLayer.swift`). Hinweise im Einsatz, Klacken bei der Vorwarnung, dumpfer Schlag beim Schließen.
- Logik: `RotorwachtCore/Passages.swift`; Tests: `PassageTests` (Takt, Ereignisse, Treffer durch Shutter und Tür, Decke, Stirnwand, Objekte, Ströme, Prüfung schlechter Daten, Stufen, Lage der Durchfahrten, **Zeitfenster in beide Richtungen für jeden Einsatz und jede Stufe, Autopilot ohne einen Treffer auf allen Stufen**).

### Bestenliste

- Je Einsatz und Stufe die zehn besten Ergebnisse (Name, Punkte, Sterne, Datum), lokal in `~/Library/Application Support/Rotorwacht/highscores.json`. Gleiche Punkte: mehr Sterne, dann der frühere Eintrag; 0 Punkte kommen nicht hinein; Namen auf 16 Zeichen gekürzt, leer wird „Pilot“.
- **Startmenü:** Knopf „Bestenliste“ neben den Stufen (Fenster mit Einsatz und Stufe zum Wählen). **Wertungskarte:** Liste der Stufe rechts neben dem Ergebnis, der eigene neue Platz hervorgehoben.
- **Name:** vor dem ersten Eintrag einmal auf der Wertungskarte abgefragt (Standard: Benutzername des Macs), später änderbar in den Einstellungen (Cmd+,).
- Logik in `RotorwachtCore/HighScores.swift`, 8 neue Tests (`HighScoreTests`: Reihenfolge, Gleichstand, Zehnerliste, 0 Punkte, getrennte Listen, Namen, Speichern und beschädigte Datei, Umbenennen); zusammen 149 Tests grün.
- Nicht mit dem Controller bedienbar (Bestenliste im Startmenü nur mit Maus oder Tastatur).

## [0.5.0] – 2026-11-20

### Gamepad

Controller (Xbox, PlayStation, MFi) zusätzlich zur Tastatur, über das Framework GameController.

- **Fliegen:** linker Stick analog (Totzone, Kurve; dosiert Fahrt und Steig-/Sinkgeschwindigkeit weich) und Steuerkreuz (volle Ausschläge). Tastatur unverändert; sobald eine Pfeiltaste gehalten wird, gilt die Tastatur.
- **A / Kreuz** Löschwasser, **Start / Menü** Pause, im Menü Stick oder Steuerkreuz wählen (mit Wiederholung), A bestätigen, B zurück (Pause: B setzt fort, Wertung: B zum Start). Fokusrahmen in Terrakotta, nur mit verbundenem Controller.
- Hinweis zum Controller im Startmenü und im neuen Einstellungsfenster (Cmd+,) mit Belegung und Totzone-Regler. Abtrennen im Einsatz pausiert und zeigt es im Pausenfenster an.
- Logik ohne Oberfläche in `RotorwachtCore/Gamepad.swift` (`GamepadInterpreter`, `GridFocus`), `PilotInput` hat dafür optionale Analogachsen (`axisX`, `axisY`); Anbindung in `Sources/Rotorwacht/GamepadController.swift`.
- 11 neue Tests (Totzone, Kurve, Steuerkreuz, Hysterese, Tasten, Wiederholung, Fokus, analoges Steigen); zusammen 110. Mit echtem Controller noch nicht geprüft.

### Musik und Klang

Eigene Musik, vollständig im Code erzeugt (keine Aufnahmen, keine fremden Stücke, nichts zu lizenzieren).

- **Menümusik** (ruhig, D-dorisch, Glockenmelodie) und **je Einsatz ein eigener Musikteppich** mit eigener Tonart, Tonleiter, Tempo und Melodie: Hochwasser (a-Moll, Flöte), Waldbrand (E-phrygisch, Blech, kräftiger Puls), Sturmnacht (fis-Moll, tief und weit), Altstadt (d-harmonisch Moll, gezupft, drängend), Vulkan (C-phrygisch-dominant, schwer und langsam), Hochgebirge (Es-lydisch, Glocken, offen). Die Melodie je Thema ist über den Startwert festgelegt und bleibt von Spiel zu Spiel erkennbar.
- **Intensität aus dem Spielzustand:** Zeitdruck (letztes Drittel), knapper Treibstoff, steigende Flut, Feuer, Rauch und Hitze, Schaden, dazu kurze Schübe bei verlorenen Personen, Treffern und verlorenen Hubschraubern. Bei höherer Intensität kommen nacheinander Bass, Arpeggio, Schlagwerk und hohe Tickstimmen dazu, das Tempo steigt um bis zu 14 %; sie steigt in etwa zwei Sekunden, fällt in etwa acht.
- **Abschluss bei der Wertung:** kurzes Siegesmotiv (mindestens ein Stern) oder ruhiger, absteigender Ausklang (sonst); danach Stille bis zum Menü, dort kehrt die Menümusik zurück.
- **Einstellungen** in Startmenü und Pausenkarte: Musik an/aus, Lautstärke Musik, Lautstärke Effekte (getrennt, wird gespeichert). Alle Pegeländerungen laufen als Rampen: Themenwechsel blenden über, Pause und Fensterwechsel blenden aus und halten die Musik an derselben Stelle an.
- **Technik:** Logik ohne Oberfläche in `RotorwachtCore` (`Music.swift` Themen, Tonleitern, Muster; `MusicSynth.swift` Synthesizer und Sequenzer; `MusicMixer.swift` Überblenden, Lautstärke, Pause; `MusicIntensity.swift` Intensitätskurve und Einstellungen), Wiedergabe mit eigener `AVAudioEngine` in `MusicPlayer.swift`, getrennt von den Effekten.
- 17 neue Tests (`MusicTests`): Startwert und Determinismus, alle Töne in der Tonleiter, Schichten je Intensität, Intensitätskurve, Überblenden, Pause, Aus/An, Abschlüsse sowie Offline-Rendern aller Themen bei drei Intensitäten (Spitzenpegel unter 0,95, Effektivpegel 0,08–0,15, keine stille Sekunde, keine Sprünge zwischen Samples). Der Klang selbst ist nicht automatisch prüfbar und muss von Lutz probegehört werden.

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
