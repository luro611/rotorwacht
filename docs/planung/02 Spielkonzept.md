# Spielkonzept Wühltisch (Vorschlag)

Stand: Entwurf vom 19.11.2026, zur Freigabe durch Lutz. Alles hier ist eigene Erfindung; aus dem C64-Vorbild stammt nur das allgemeine Genre (Arcade-Spiel in einem Kaufhaus, Gegenstände einsammeln, Verfolgern ausweichen).

## Die Idee in einem Satz

Beim großen Schlussverkauf im Kaufhaus „Wühltisch“ jagt die Spielfigur über mehrere Etagen die Schnäppchen auf ihrem Einkaufszettel, weicht drängelnden Kunden und dem Hausdetektiv aus und muss vor Ladenschluss mit vollem Korb an der Kasse sein.

## Spielfigur

- **Frieda Feilscher**, eine resolute Schnäppchenjägerin mit Einkaufskorb und Hut.
- Kann laufen, auf Rolltreppen fahren, Leitern bzw. Treppen nehmen, kurz springen (über Kartons, Pfützen).
- Ein Knopf: **Schubser** (kurzer Rempler, der einen Verfolger für zwei Sekunden aus dem Weg schiebt; danach Abklingzeit).

## Spielfeld

- **Seitenansicht** eines Kaufhauses, ein Bildschirm pro Abteilung, 3 bis 4 Etagen übereinander (Erdgeschoss mit Kasse, darüber Abteilungen).
- Verbunden durch Rolltreppen (fahren selbst, nur eine Richtung), Treppen und einen Aufzug, der in festem Takt fährt.
- Abteilungen je Level wechselnd: Haushalt, Spielwaren, Mode, Elektro, Lebensmittel, Sport.

## Ziel einer Runde (ein Level = ein Verkaufstag)

1. Oben am Bildschirm steht der **Einkaufszettel** mit 4 bis 8 Artikeln.
2. Die Artikel liegen auf Wühltischen und in Regalen, teils versteckt (erst durch Durchwühlen sichtbar: kurz stehen bleiben).
3. Sind alle Artikel im Korb, zur **Kasse** im Erdgeschoss.
4. Die **Uhr** läuft bis Ladenschluss (z. B. 90 Sekunden Spielzeit). Restzeit gibt Bonuspunkte.

## Gegenspieler und Hindernisse

- **Drängler:** andere Kunden, laufen hin und her, schnappen dir einen Artikel weg, wenn sie zuerst da sind (Artikel taucht anderswo neu auf).
- **Hausdetektiv Kowalski:** verfolgt dich, sobald du zu schnell rennst oder schubst. Erwischt er dich, verlierst du ein Leben.
- **Putzroboter:** fährt feste Bahnen und hinterlässt nasse Stellen, auf denen man rutscht.
- **Kartonstapel:** fallen um, wenn man dagegen läuft, und blockieren kurz den Weg.
- **Durchsagen** („Sonderangebot in der Spielwarenabteilung!“) erzeugen zufällig einen Bonusartikel mit Zeitlimit.

## Punkte, Leben, Schwierigkeit

- Punkte je Artikel, Bonus für Sonderangebote, Restzeit und „ohne Schubser geschafft“.
- 3 Leben, Extraleben alle 10 000 Punkte.
- Mit jedem Verkaufstag: längerer Zettel, mehr Drängler, schnellerer Detektiv, kürzere Zeit. Alle 5 Tage ein Sondertag (z. B. Inventur: Licht flackert, nur Taschenlampenkegel).
- Highscore-Liste lokal mit drei Buchstaben wie am Automaten.

## Steuerung

- Tastatur (Pfeiltasten oder WASD, Leertaste = Schubser) und Gamepad (Xbox/PlayStation-Controller über Apple GameController).
- Bewusst nur Richtung + ein Knopf, wie am Joystick.

## Grafik und Ton

- Eigene Pixelgrafik im 80er-Stil: feste Auflösung 320 × 200, ganzzahlig skaliert, eigene Palette mit 16 Farben (nicht die C64-Palette).
- Figuren 16 × 21 Pixel, Animationen mit 2 bis 4 Bildern.
- Musik und Geräusche als eigene Chiptunes, im Spiel synthetisiert (Rechteck, Dreieck, Rauschen), keine fremden Dateien.
- Menü, Einstellungen und Über-Fenster in der lurohome-Designsprache mit Siegel und Wortmarke.

## Technik

- Swift, SpriteKit, SwiftUI für Menüs; macOS ab Version 14.
- Levels als Textdateien (Kachelraster), damit neue Abteilungen ohne Code entstehen.
- Fenster und Vollbild, Pause mit Esc.

## Umfang Version 0.1 (erster spielbarer Stand)

- Ein Kaufhaus mit 3 Etagen und 3 Verkaufstagen.
- Frieda, Drängler und Hausdetektiv; noch kein Putzroboter, keine Durchsagen.
- Platzhaltergrafik und einfache Töne, Punkte und Leben, kein Highscore.

Danach: 0.2 Grafik und Ton, 0.3 weitere Gegner und Sondertage, 0.4 Highscore und Gamepad, 1.0 sechs Abteilungen und 20 Verkaufstage.

## Zur Entscheidung

- E1: Thema Schnäppchenjagd im Schlussverkauf wie oben?
- E2: Seitenansicht mit Etagen, ein Bildschirm pro Abteilung (statt scrollend)?
- E3: Schubser als einziger Aktionsknopf?
- E4: Umfang 0.1 wie oben?
