# Validierung v2

Ergebnis: **PASS** für den mitgelieferten Datenbanktest.

Umgebung: PGlite 0.5.8 (PostgreSQL in WASM), isolierte In-Memory-Datenbank. Supabase-Rollen anon/authenticated und auth.uid() wurden für diesen Test nachgebildet. Kein Zugriff auf ein produktives Supabase-Projekt.

Geprüft:

- Migration und Seed werden ausgeführt; veröffentlichte Fragen kommen aus der Datenbank, Regeln werden nicht im Fragebogenpayload offengelegt.
- Vorangehende Fragen und vollständige Antworten sind erforderlich; erfundene Optionen werden abgewiesen.
- Auswahländerungen ergeben eigene Ereignisse; vollständige Antworten erzeugen das serverseitig konfigurierte Ergebnis.
- Idempotenz für visit/selection/finish: gleiche Request-ID und gleicher Inhalt liefern dieselbe Antwort ohne zusätzliche Ereignisse; anderer Inhalt mit gleicher ID wird abgewiesen.
- Sequenz und Serverzeit aller sechs Testereignisse: visit, vier Auswahlen, Ergebnis.
- Häufigkeitssumme sechs, Zahlencodesumme sieben; Auswahländerung zählt mit, Retry nicht.
- Abgeschlossene Durchläufe können nicht verändert werden.
- Direkte Tabellenzugriffe und private Funktionsaufrufe scheitern für authenticated.
- Fremder Nutzer kann den Testdurchlauf nicht verändern.
- Bereits verwendete Definition kann nicht umgeschrieben werden.
- Nutzer- und globales Request-Limit greifen.
- Reset leert Rohdaten, Durchläufe, Zähler und Idempotenz; Fragebogen bleibt bestehen.
- anon ohne Nutzersitzung hat keine RPC-Ausführungsberechtigung; fehlende auth.uid() wird abgewiesen.

Wiederholen (Node.js erforderlich):

```bash
cd supabase/tests
npm install
npm test
```

Diese Tests verbinden sich niemals mit Supabase und verändern keine externen Daten. Nicht geprüft sind echte Supabase-JWT-/Auth-Integration, Auth-IP-Limits, gleichzeitige Verbindungen, reale HTTP-Fluten sowie der Flutter-Build. Transaktionen und Locks wurden funktional ausgeführt, aber nicht durch einen Parallel-Lasttest getestet.

Flutter-Widget-/Modelltests sind unter `test/` enthalten, wurden hier mangels Flutter SDK nicht ausgeführt. Der GitHub-Workflow führt Flutter-Analyse, Tests und Build aus.

Nach Einrichtung zusätzlich in deinem Supabase-Projekt testen:

1. Seite öffnen und drei Auswahlen/Ergebnis bestätigen: visit + drei selection + result.
2. In zweitem Browser/Inkognito einen unabhängigen Nutzer erzeugen.
3. Rohdaten und Zähler über `research_queries.sql` prüfen; Konsistenzabfrage liefert null Zeilen.
4. Nach Versionswechsel einen neuen Durchlauf starten und historische Version/Antwort prüfen.
5. Vor Release Export erstellen, App anhalten, manuellen Reset ausführen, dann neu öffnen.
