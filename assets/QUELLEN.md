# Quellen

## Grafik und Ton

Alle Grafiken des Spielfelds (Hubschrauber, Menschen, Landeplätze, Gebäude, Gelände, Panoramen, Felswand und Betonbauwerk der Durchfahrten, Shutter und Signallampen, Hindernisse: Masten, Kran, Seilbahn, Windräder) sind eigene 3D-Modelle, die per Python-Skript in Blender (Version 5.3, GPL, nur als Werkzeug; die Bilder sind eigene Werke) erzeugt und gerendert werden: `art/*.py`, Ausgabe in `Sources/Rotorwacht/Renders`. Keine fremden Modelle oder Texturen. Effekte und das Menü entstehen im Code, alle Geräusche werden synthetisiert. Die Musik wird zur Laufzeit im Code erzeugt (eigene Tonleitern, Akkordfolgen, Melodien und Synthesizer-Stimmen in `Sources/RotorwachtCore/Music*.swift`), ebenso die Geräusche. Es gibt keine fremden Bild- oder Tondateien und keine Aufnahmen. Nichts stammt aus Choplifter oder einem anderen bestehenden Spiel.

## Luro-Siegel

`Sources/Rotorwacht/Images/siegel-hell.png`, `siegel-dunkel.png`: eigenes Logo, aus `lurohome/logos/png` (luro-siegel-kompakt, 512 px).

## Schriften (SIL Open Font License 1.1)

Statische OTF-Schnitte aus `lurohome/src/fonts/otf/`, Lizenztexte in `Sources/Rotorwacht/Fonts/OFL-*.txt`:

- Instrument Serif (Regular, Italic): Überschriften
- Inter (Regular, Medium): Text
- Archivo (Medium, SemiBold): Beschriftungen und Knöpfe
- Geist Mono (Regular, Medium): Kleinzeilen, Zahlen
