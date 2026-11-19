# Spielkonzept Rotorwacht (Vorschlag)

Stand: Entwurf vom 19.11.2026, zur Freigabe durch Lutz. Ersetzt den ersten Entwurf („Wühltisch“, Kaufhaus), der auf einem Missverständnis beruhte.

Vorbild ist das Genre von Choplifter (C64, 1982): ein Hubschrauber fliegt seitlich über eine Landschaft, holt Menschen ab und bringt sie zur Basis. **Übernommen wird nur dieses Grundprinzip.** Thema, Figuren, Gegner, Landschaften, Levels, Grafik und Ton sind eigene Erfindung; nichts aus dem Original wird nachgebaut (siehe CLAUDE.md, „Eigenständigkeit“).

## Die Idee in einem Satz

Als Pilotin bzw. Pilot der Rettungsstaffel „Rotorwacht“ fliegst du nach Naturkatastrophen in das Unglücksgebiet, löschst Brände, holst eingeschlossene Menschen von Dächern, Inseln und Felsvorsprüngen und bringst sie sicher ins Lager zurück, bevor Wetter, Feuer oder Treibstoff dir einen Strich durch die Rechnung machen.

## Steuerung

- **Pfeiltasten:** links/rechts beschleunigen und neigen, hoch/runter steigen und sinken. Der Hubschrauber hat Trägheit und neigt sich in Flugrichtung.
- **Wende:** kurz in die Gegenrichtung drücken dreht den Hubschrauber; im Stand zeigt er nach vorn zum Spieler (dann wirft er senkrecht ab).
- **Leertaste:** Löschwasser abwerfen (Wassertank, füllbar durch Tiefflug über See oder Fluss).
- **Landen:** sanft aufsetzen (zu schnell = Schaden). Gelandet steigen Menschen von selbst ein und aus.
- **Esc:** Pause. Später optional Gamepad.

## Ablauf einer Mission

1. Start im **Lager** am rechten Rand (Landeplatz, Zelt mit Sanitätern, Tankstelle).
2. Flug nach links ins Unglücksgebiet, die Landschaft scrollt mit.
3. Menschen warten an **Rettungspunkten**: auf Hausdächern in der Flut, auf Inseln, am Waldrand. Manche sind erst erreichbar, wenn ein Brand gelöscht oder ein Weg frei ist.
4. Platz an Bord: **12 Personen**. Volle Kabine heißt: zurück zum Lager, absetzen, tanken, wieder los.
5. Mission geschafft, wenn alle Menschen gerettet sind oder die Zeit abläuft; Wertung nach Geretteten.

## Gefahren (statt Feinde)

- **Feuer:** breitet sich aus, bedroht Rettungspunkte, Hitze und Rauch kosten Sicht und Haltbarkeit. Löschbar mit Wasser.
- **Wetter:** Böen versetzen den Hubschrauber, Gewitterzellen mit Blitzschlag, Nebelbänke, Regen.
- **Flut:** Wasser steigt im Lauf der Mission, niedrige Dächer gehen unter (Zeitdruck).
- **Trümmer und Glutflug:** herabstürzende Äste, Funkenflug, beim Vulkan Ascheregen und Lavabrocken.
- **Hindernisse:** Strommasten mit Leitungen, Kräne, Felswände, Brückenpfeiler.
- **Treibstoff:** begrenzt, Nachtanken nur im Lager oder an einem eingerichteten Außenposten.

Der Hubschrauber hat eine **Haltbarkeitsanzeige** statt sofortigem Absturz. Bei null: Notlandung, ein Hubschrauber weniger (3 pro Einsatz). Personen an Bord gelten dann als verletzt und kosten Wertung.

## Einsätze (Kampagne für 1.0)

1. **Hochwasser im Flusstal** (Einführung, Flut, Böen)
2. **Waldbrand am Hang** (Löschen lernen, Rauch)
3. **Sturmnacht an der Küste** (Nacht mit Scheinwerfer, Gewitter, Wellen)
4. **Erdbeben in der Altstadt** (Trümmer, enge Landeplätze zwischen Häusern)
5. **Vulkanausbruch auf der Insel** (Asche, Lava, Treibstoff knapp)
6. **Lawinen im Hochgebirge** (dünne Luft, Wind, Seilwinde statt Landen)

Jeder Einsatz in drei Stufen (leicht, mittel, schwer). Sterne je Einsatz für gerettete Menschen, Zeit und „ohne Schaden“.

## Grafik

- **Detailreiche 2D-Grafik** in hoher Auflösung, SpriteKit.
- **Parallax** mit 4 bis 6 Ebenen (Himmel, Berge, Wald, Spielebene, Vordergrund).
- **Effekte:** Rotor-Abwind drückt Gras, Bäume und Wasser; Rauch und Feuer als Partikel; Wasserspiegelungen; Tageszeit und Wetter mit Licht (SpriteKit-Lichter, Shader); Kamera folgt mit leichtem Vorlauf und Wackeln bei Treffern.
- **Figuren:** kleine, gut erkennbare Menschen mit einfachen Animationen (winken, laufen, einsteigen).
- **Grafikquellen:** selbst erstellt bzw. im Code erzeugt (Vektorformen, Verläufe, Prozedurales). Für Detailbilder sind frei lizenzierte Bausteine (CC0) möglich, jeweils mit Herkunft in `assets/QUELLEN.md`. Nichts aus Choplifter.
- 60 Bilder pro Sekunde, Fenster und Vollbild, Retina.

## Ton

- Rotorgeräusch, das sich mit Schub und Neigung ändert (synthetisiert), Wind, Regen, Feuer, Funksprüche als kurze Signaltöne.
- Musik: eigene, ruhige Stücke; im Einsatz eher Klangflächen als Melodie. Herkunft wie bei Grafik dokumentiert.

## Oberfläche

- Startbildschirm, Einsatzauswahl auf einer Karte, Einstellungen, Über-Fenster in der lurohome-Designsprache (hell und dunkel), luro-Siegel auf dem Startbildschirm, Wortmarke in der Fußzeile.
- Anzeige im Spiel schlicht: Treibstoff, Wasser, Haltbarkeit, Personen an Bord, Gerettete / Gesamt, Zeit.

## Technik

- Swift 6, SpriteKit, SwiftUI für Menüs, macOS ab 14.
- Einsätze als Datendateien (Landschaft, Rettungspunkte, Gefahren, Wetter), damit neue Einsätze ohne Code entstehen.
- Spielstand und Bestwerte lokal.

## Umfang Version 0.1 (erster spielbarer Stand)

- Einsatz 1 „Hochwasser im Flusstal“ in einer Stufe.
- Fliegen mit Trägheit, Landen, Einsteigen, Absetzen im Lager, Treibstoff, Haltbarkeit.
- Steigende Flut und Böen; noch kein Feuer und kein Löschwasser.
- Einfache, aber schon hochauflösende Platzhaltergrafik mit Parallax; Grundgeräusche.

Danach: 0.2 Löschen und Waldbrand, 0.3 Grafik und Effekte ausbauen, 0.4 Nacht, Gewitter, Einsatzkarte, 0.5 restliche Einsätze, 1.0 alle sechs Einsätze in drei Stufen.

## Zur Entscheidung

- E1: Thema Katastrophenrettung ohne Feinde, Leertaste für Löschwasser (statt Schuss)?
- E2: 12 Plätze an Bord, 3 Hubschrauber pro Einsatz, Haltbarkeit statt Sofort-Absturz?
- E3: Die sechs Einsätze wie oben?
- E4: Umfang 0.1 wie oben?
