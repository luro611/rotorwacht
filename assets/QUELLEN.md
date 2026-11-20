# Quellen

## Grafik und Ton

Alle Grafiken des Spielfelds (Hubschrauber, Menschen, Landeplätze, Gebäude, Gelände, Panoramen) sind eigene 3D-Modelle, die per Python-Skript in Blender (Version 5.3, GPL, nur als Werkzeug; die Bilder sind eigene Werke) erzeugt und gerendert werden: `art/*.py`, Ausgabe in `Sources/Rotorwacht/Renders`. Keine fremden Modelle oder Texturen. Effekte und das Menü entstehen im Code, alle Geräusche werden synthetisiert. Es gibt keine fremden Bild- oder Tondateien. Nichts stammt aus Choplifter oder einem anderen bestehenden Spiel.

## Luro-Siegel

`Sources/Rotorwacht/Images/siegel-hell.png`, `siegel-dunkel.png`: eigenes Logo, aus `lurohome/logos/png` (luro-siegel-kompakt, 512 px).

## Schriften (SIL Open Font License 1.1)

Statische OTF-Schnitte aus `lurohome/src/fonts/otf/`, Lizenztexte in `Sources/Rotorwacht/Fonts/OFL-*.txt`:

- Instrument Serif (Regular, Italic): Überschriften
- Inter (Regular, Medium): Text
- Archivo (Medium, SemiBold): Beschriftungen und Knöpfe
- Geist Mono (Regular, Medium): Kleinzeilen, Zahlen
