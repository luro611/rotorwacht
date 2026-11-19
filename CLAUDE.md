# Rotorwacht

Eigenes Hubschrauber-Rettungsspiel für den Mac, nur zum eigenen Gebrauch. Inspiriert vom Genre des C64-Spiels Choplifter, das Lutz früher gern gespielt hat, aber **kein Nachbau**: eigenes Thema (Katastrophenrettung), eigener Name, eigene Figuren, Grafiken, Einsätze, Musik und Geräusche, in heutiger Grafik.

## Stand

- **Phase:** Vorbereitung. Spielkonzept als Vorschlag in `docs/planung/02 Spielkonzept.md`, Entscheidungen E1–E4 offen.
- **Vor der Freigabe keinen Anwendungscode schreiben.**
- Bis 19.11.2026 hieß das Projekt „Wühltisch“ (erster Entwurf mit Kaufhaus-Thema, Missverständnis: gemeint war Choplifter, nicht „Shoplifter“).

## Planung

Liegt unter `docs/planung/`:

- `01 Offene Fragen.md`: Fragen zu Spielprinzip, Steuerung, Grafik und Technik
- `02 Spielkonzept.md`: Vorschlag vom 19.11.2026 (Katastrophenrettung, sechs Einsätze, Umfang 0.1)

## Projekt-Eckdaten

- **Name:** Rotorwacht (Ordner und Repo `rotorwacht`).
- **Plattform:** GitHub `luro611/rotorwacht` (privat). Nicht Codeberg.
- **Lizenz:** später festlegen.
- **Versionen:** 0.x bis zum ersten fertigen Stand, dann 1.0.0.
- **Technik:** native Mac-App mit Swift, SpriteKit und SwiftUI, unnotarisiert (kein Apple-Entwicklerkonto; nicht wieder ansprechen).
- **Steuerung:** Pfeiltasten zum Fliegen, Leertaste für Löschwasser, Esc Pause.
- **Grafik:** detailreiche, hochauflösende 2D-Grafik mit Parallax, Licht und Partikeln (kein Pixel-Look).

## Eigenständigkeit (verbindlich)

- Keine Namen, Figuren, Sprites, Levelpläne, Musik, Texte oder Bildschirmaufbauten aus Choplifter oder anderen bestehenden Spielen übernehmen, auch nicht abgewandelt. Kein Kriegs-/Geisel-Thema.
- Übernommen wird nur das allgemeine Spielprinzip (seitlich fliegen, Menschen abholen, zur Basis bringen).
- Grafik und Ton selbst erstellt oder frei lizenziert (CC0), Herkunft in `assets/QUELLEN.md`.
- Keine ROMs, Disk-Images oder Dateien des Originals ins Repository.

## Designsprache

Das Spielfeld hat eine eigene Grafik. Menü, Einstellungen und Über-Fenster folgen der Designsprache von lurohome (`/Users/luro/Documents/Projekte/Webseiten/lurohome/src/style.css`, Schriften aus `lurohome/src/fonts/`, hell und dunkel). Marke luro: Siegel kompakt auf dem Startbildschirm, Wortmarke als Fußzeile.

## Regeln

- Keine Zugangsdaten oder privaten Daten im Repository; Zugangsdaten nur in `.env`, im Repository nur `.env.example`.
