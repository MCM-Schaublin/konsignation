# Kurzanleitung Konsignationsabgleich (Webtool)

**Wofür:** Vor Ort die Konsignationsware scannen und gegen die Soll-Liste des Kunden abgleichen. Am Ende entstehen ein PDF zur Unterschrift und eine CSV.

## 1 · Soll-Liste einlesen
1. Auf **Datei auswählen** tippen und die Soll-Liste wählen (PDF oder Excel).
2. **Liste einlesen** drücken.
3. Kontrolle: Darunter steht die Anzahl der Positionen, die Summe und der Standort (z. B. „K005 - Basel Universitätsspital“).
4. Wenn „Keine Positionen erkannt“ erscheint, ist das Format nicht bekannt. Dann bitte melden und die Datei mitschicken.

## 2 · Scannen
1. Kamera wählen (Standard: Rückkamera) und **Kamera starten** drücken. Der Barcode oder QR-Code wird automatisch erkannt.
2. Die Kamera startet nach 6 Sekunden ohne Erkennung selbst neu. Ein manuelles Aus- und Einschalten ist nicht nötig.
3. Jeder erkannte Code erscheint unten in der Liste, und die Zähler „… gescannt“ steigen.
4. Wenn ein Code nicht erkannt wird: den Text in das Feld **Code einfügen (GS1-Text)** kopieren und **Hinzufügen** drücken.
5. **Letzten Code +1**: Für einen zweiten Karton mit gleicher Charge nach dem letzten Scan drücken. Der Zähler wird um 1 erhöht, ohne den Code erneut zu scannen.
6. Sobald alle Artikel erfasst sind, **Kamera stoppen** drücken.

## 3 · Abgleich und Ergebnis
1. **Abgleich starten** drücken. Der Abschnitt „3 · Ergebnis“ erscheint.
2. Die Positionen werden so angezeigt:
   - **vorhanden**: Artikel stimmt mit der Soll-Liste überein.
   - **FEHLT**: Artikel steht auf der Soll-Liste, wurde aber nicht gescannt.
   - **ABWEICHUNG**: Artikel ist da, aber eine Charge oder Seriennummer weicht ab.
   - **ZUSÄTZLICH**: Artikel wurde gescannt, steht aber nicht auf der Liste.
3. Bei gleicher Charge mit zu wenig Stück gilt das als **Fehlmenge** (FEHLT), nicht als Abweichung.

## 4 · Unterschrift und Ausgabe
1. Unterschrift Kunde und Unterschrift MCM Schaublin AG mit Finger oder Stift ins Feld schreiben. Name und Datum eintragen.
   - Auf dem Handy quer halten, dann sind die Felder grösser.
   - Mit **Löschen** kann jedes Feld zurückgesetzt werden.
2. **PDF für Unterschrift** drücken. Das PDF enthält das Logo, das Ergebnis und die Unterschriften.
3. **CSV herunterladen** drücken, um die Ergebnisse als Tabelle zu speichern.

## Tipps
- Die Kamera braucht HTTPS. Die Seite muss also über die Web-Adresse geöffnet werden, nicht lokal.
- Bei Problemen: Screenshot der Meldung und ein Foto des Etiketts an den Entwickler schicken.
