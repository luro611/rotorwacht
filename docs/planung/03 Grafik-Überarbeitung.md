# Grafik-Überarbeitung

Rückmeldung von Lutz am 19.11.2026 nach dem Anspielen von 0.2.1, mit seinen Entscheidungen. Kommt **vor** weiterem Ausbau.

## Rückmeldung

1. Die gesamte Grafik ist viel zu einfach.
2. Der Hubschrauber soll viel moderner aussehen.
3. Personen schweben teilweise über dem Boden.
4. An den Stellen, wo Personen warten, gibt es teils keinen klar erkennbaren Landeplatz.

## Entscheidungen (19.11.2026)

- **G1 Grafikweg:** 3D-Modelle, als Bilder gerendert. Hubschrauber, Gebäude, Gelände-Elemente und Menschen werden als 3D-Modelle in Blender **per Python-Skript** erzeugt (reproduzierbar, im Repository unter `art/`), daraus entstehen hochaufgelöste Sprites und Animationsfolgen mit Licht, Schatten und Materialien. Die gerenderten Bilder liegen im App-Bundle. Blender wird auf dem Mac installiert (Homebrew `--cask blender`); in `assets/QUELLEN.md` und als Werkzeug im README vermerken.
- **G2 Hubschrauber:** moderner zweimotoriger Rettungshubschrauber mit ummanteltem Heckrotor, Lackierung Rot-Weiß oder Gelb, Seilwinde, Suchscheinwerfer, Kufen. Eigenes Design, keine echten Marken, Kennzeichen oder Organisationen.

## Was gebaut werden soll

- **Hubschrauber:** Seitenansicht in beiden Richtungen und die Frontansicht (zum Spieler), Zwischenbilder beim Wenden, Neigung in mehreren Stufen, Hauptrotor als Bewegungsunschärfe-Scheibe, drehender Heckrotor, Positionslichter, Scheinwerfer, Schatten auf dem Boden.
- **Menschen:** mehrere Figurtypen, Animationen für Warten/Winken, Laufen, Einsteigen; Füße stehen **immer** auf der Oberfläche, auf der sie warten (Fehler 3).
- **Landeplätze:** Jeder Rettungspunkt hat eine klar erkennbare, ebene Landefläche passend zum Ort (Flachdach mit H-Markierung oder Notlandemarke, Plattform, Wiese mit Markierung, Bootsdeck); die Wartenden stehen am Rand dieser Fläche. Daten und Physik prüfen, dass die Fläche mindestens die Breite der Kufen hat (Fehler 4).
- **Gelände und Gebäude:** gerenderte Häuser, Bäume, Felsen, Wasserflächen; Parallax-Hintergründe als gerenderte Panoramen je Einsatz.
- **Effekte** (Wasser, Feuer, Rauch, Wetter) dürfen weiter Partikel aus SpriteKit sein, aber mit gerenderten Texturen.
- **Prüfung:** Ein Test stellt sicher, dass jede Person und jeder Rettungspunkt auf dem Gelände bzw. auf der Landefläche steht; Screenshots je Einsatz vor dem Bericht ansehen.

## Reihenfolge

1. Der laufende Block 0.3 (Einsätze 3–6) wird erst fertig gestellt und committet.
2. Danach Grafik-Überarbeitung als Version 0.4 für alle Einsätze.
