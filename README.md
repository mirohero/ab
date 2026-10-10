# Flutter-Forschungsfragebogen · Supabase v2

Fragen, Antwortoptionen und Ergebnisregeln kommen aus Supabase. Die Flutter-Webapp übermittelt nur IDs. Supabase validiert jede Auswahl, berechnet das Ergebnis, protokolliert Ereignisse mit Server-Zeitstempeln und aktualisiert Zähler atomar.

## Upgrade von der bisherigen Version

1. Bestehende Forschungs-/Testdaten bei Bedarf exportieren. Die v2-Migration löscht keine v1-Daten.
2. `supabase/migrations/002_research.sql` einmal im Supabase SQL Editor ausführen. Sie sperrt auch die direkte v1-Tabelle `questionnaire_sessions` für Browserzugriffe. Eine alte App-Version kann danach nicht mehr speichern: unmittelbar anschließend neue App veröffentlichen.
3. `supabase/003_seed.sql` ausführen. Das legt den ersten veröffentlichten Fragebogen an.
4. Anonyme Anmeldung in Authentication aktivieren. Data API und Schema `public` müssen aktiviert bleiben.
5. Die eigene `config/app_config.json` aus deinem bisherigen Projekt **behalten**: im Download sind nur leere Platzhalter. Niemals Secret-/service_role-Schlüssel eintragen.
6. Projektdateien ersetzen, einschließlich `pubspec.yaml`, `lib`, `test` und Workflow. Die nicht mehr vorhandene lokale Demo-/Verlaufsspeicherung gehört nicht zu v2.
7. Starten:

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=config/app_config.json
```

Analyse, Tests und Release-Build:

```bash
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=config/app_config.json
```

Der GitHub-Pages-Workflow nutzt weiterhin die Konfigurationsdatei. Supabase selbst ist das Backend. Der vollständige Flutter-Build wurde in der Erstellungsumgebung mangels SDK nicht ausgeführt. Die PostgreSQL-Funktionen werden separat mit einer lokalen PostgreSQL-kompatiblen Testumgebung auf Funktion, Rechte und Ereigniszähler geprüft (siehe `supabase/TEST_REPORT.md`). Ein echtes Supabase-Projekt ist hier nicht verbunden.

## Fragen und Ergebnisse auf dem Server einrichten

`public.study_versions` enthält Titel, Veröffentlichungsstatus und die JSON-Spalte `definition`:

- `questions`: geordnete Fragen; jede hat `id`, `title` und `options` mit `id`, `label`, `code`.
- `rules`: geordnete Regeln mit `id`, `code`, `when`, `title`, `text`.
- `when` enthält Frage-ID → Options-ID. Die **erste passende Regel** gewinnt.
- Eine Regel mit `when: {}` ist der Standardfall; sie gehört ans Ende.
- Zahlencodes sind ganze Zahlen. Stabile IDs sind die Auswertungsgrundlage; Codes sind zusätzlich für Forschung verfügbar. Summen von Kategoriencodes sind nur sinnvoll, wenn die Codes tatsächlich eine quantitative Bedeutung haben.
- `supabase/definition.example.json` zeigt die Konfiguration; diese Datei wird nicht von Flutter geladen, sondern dient als Vorlage für die Datenbank.

Für Änderungen nach den ersten Nutzungen `supabase/publish_new_version.sql` anpassen und ausführen. Bereits benutzte Definitionen sind unveränderlich. Jeder Durchlauf bleibt an seiner Version gebunden; neue Seitenaufrufe nutzen die neue veröffentlichte Version. Damit werden historische Ereignisse nicht nachträglich anders interpretiert. Es gibt maximal eine veröffentlichte Version. Editieren eines unbenutzten Entwurfs ist im Table Editor möglich.

Fragenreihenfolge ist verbindlich: vorangehende Fragen müssen beantwortet sein. Zurückgehen und Auswahlwechsel sind erlaubt. Das Ergebnis verwendet die zuletzt bestätigte Auswahl pro Frage. Es gibt keinen clientseitigen Ergebnisalgorithmus und keine freie Textübermittlung. Bedingungen sind Gleichheitsprüfungen, keine KI oder Skriptausführung.

## Forschung: Zeitverlauf und Zähler

| Tabelle | Inhalt |
|---|---|
| `study_versions` | Historisch stabile Fragebogen-/Regeldefinitionen |
| `study_runs` | Durchlauf, Eigentümer, Version, Start/Abschluss, letzte Auswahlen, Ergebnis |
| `study_events` | Unveränderliche Ereignisfolge: visit, selection, result |
| `study_counters` | Ereignishäufigkeit und Codesumme pro Version/Frage/Option bzw. Ergebnis |

`visit` wird unmittelbar beim ersten erfolgreichen API-Aufruf nach der anonymen Authentifizierung gespeichert – ohne separaten Startknopf. Nach Neuladen entsteht ein neuer Durchlauf; es ist keine Zählung eindeutig identifizierter Menschen. Ein offline abgebrochener Seitenaufruf vor erfolgreicher API-Verbindung kann naturgemäß nicht serverseitig protokolliert werden.

Jede erfolgreich bestätigte Auswahl (auch spätere erneute Auswahl derselben Option) hat Serverzeit, Sequenznummer, IDs, Zahlencode und einen Snapshot der Texte/aktuellen Antworten. Das Ergebnisereignis dokumentiert das serverseitig erzeugte und an den Browser zurückgesendete Ergebnis; es beweist nicht, dass ein Mensch es gesehen hat. Es gibt keine clientseitig behaupteten Uhrzeiten. In der Datenbank stehen UTC-Zeiten; Sequenz/ID löst gleiche Zeitstempel auf.

Ereignis, letzter Durchlaufzustand und Zähler werden in einer Transaktion gespeichert. Eine Request-ID darf nur genau einen identischen Vorgang repräsentieren. Manueller Retry nach Verbindungsabbruch verwendet dieselbe ID und zählt nicht doppelt. Nach einem vollständigen Seitenreload entsteht bewusst ein neuer visit.

`study_counters.event_count` ist die Anzahl aller Auswahlereignisse, **nicht** die Anzahl eindeutiger Nutzer oder finaler Antworten. `numeric_sum` summiert die Zahlencodes. `supabase/research_queries.sql` enthält Rohdatenexport, Summen, Ergebnisverteilung, Bearbeitungszeiten, finale Antworten pro Frage und einen Konsistenzcheck. Im Dashboard/SQL Editor als Betreiber ausführen; Tabellen sind für den Browser vollständig gesperrt. CSV-Exporte sind dadurch möglich, ohne öffentliche Admin-Endpunkte zu schaffen.

## Reset vor Release

`supabase/reset_before_release.sql` ist ein manueller, destruktiver Reset für Test-/Forschungsdaten, Zähler, Idempotenz und Limits sowie die alte v1-Tabelle, falls vorhanden. **Erst exportieren/Backup machen.** Nicht automatisch beim Deployment ausführen. Der Reset wartet auf laufende Schreibvorgänge. Für einen klaren Release-Stichtag App vorher offline nehmen oder die veröffentlichte Version deaktivieren, Reset ausführen, dann veröffentlichen. Sonst können unmittelbar nach dem Reset wieder neue Besuche entstehen.

Fragebogenkonfiguration und Auth-Benutzer bleiben erhalten. Fremde Auth-Benutzer werden nicht gelöscht. Bereits geöffnete Browserdurchläufe müssen neu laden. Kein Reset-Aufruf ist für Browsernutzer erreichbar.

## Request- und Missbrauchsschutz

Implementiert:

- Authentifizierter RPC `study_call`; `auth.uid()` kommt aus Supabase Auth, nicht aus dem Request.
- Keine direkten SELECT/INSERT/UPDATE/DELETE-Grants auf v2-Tabellen und keine browserseitig ausführbaren internen Hilfsfunktionen.
- Fester leerer `search_path` bei Funktionen und explizite Eigentümerprüfung, da der kontrollierte RPC als SECURITY DEFINER läuft.
- Maximal 60 Aufrufe/Nutzer/60 Sekunden und 1000 Aufrufe insgesamt/60 Sekunden (feste Fenster, kein gleitendes Limit). Fehlversuche mit gültiger API-Signatur und Retries verbrauchen ebenfalls das Budget. Werte in `study_call` bei Bedarf anpassen und Funktion erneut definieren.
- 200 Ereignisse pro Durchlauf, ID-Längenbeschränkung, maximal 50 Fragen/20 Optionen/100 Regeln pro Version.
- Besitzprüfung, gültige Options-IDs, Fragenreihenfolge und Vollständigkeit werden serverseitig geprüft.
- UI sendet seriell, sperrt Doppelklicks während einer Anfrage, wartet mindestens eine Sekunde zwischen bestätigten Requests, respektiert Server-Backoff; kein Polling und keine automatischen Retry-Schleifen.
- Serverlimits und Zähler benutzen Datenbanklocks, kein unsicherer prozesslokaler Zähler.

Grenzen und Betrieb:

- Diese Limits begrenzen erfolgreiche Forschungsaktionen und weitere Verarbeitung. Sie verhindern nicht, dass ein Angreifer HTTP-Requests zum Supabase-Gateway sendet: auch abgewiesene Aufrufe verursachen Last. Das globale Budget kann bewusst ausgeschöpft werden. Für Schutz vor großem Traffic ist ein vorgelagerter WAF/API-Gateway erforderlich.
- Anonyme Identitäten sind pseudonym, keine verlässliche Personen-/Geräteidentität. Auth hat eigene IP-Limits; neue anonyme Konten könnten nutzerbezogene Limits umgehen. Für öffentlichen Forschungsbetrieb Auth-CAPTCHA/Turnstile integrieren oder Teilnehmer über echte Anmeldung/Einladung zulassen. Diese Version hat **noch keine CAPTCHA-Oberfläche**; Auth-CAPTCHA im Dashboard allein einzuschalten führt ohne Tokenübergabe zu Anmeldefehlern.
- Keine feste Länder-/Gerätesperre voreingestellt, weil erlaubte Länder/Geräte noch nicht festgelegt wurden. Supabase Network Restrictions gelten für direkte Postgres-/Pooler-Verbindungen, nicht für die hier verwendete HTTPS Data API.
- Länderfilter: GeoIP-Prüfung an einem vertrauenswürdigen WAF/API-Gateway oder einer Edge Function. VPNs können GeoIP umgehen. Wenn ein Gateway eingesetzt wird, den RPC nur noch für dessen Serverrolle freigeben und Browserausführung widerrufen; sonst kann das Gateway über die direkte Supabase-URL umgangen werden. Ein vorgeschalteter Schutz allein auf der GitHub-Pages-Domain schützt keine direkten API-Aufrufe.
- Gerätefilter: User-Agent/Browsermeldungen sind fälschbar. Für belastbare Zugriffskontrolle echte Benutzer-/Teilnehmerautorisierung bzw. verwaltete Geräte mit geeigneter Authentifizierung benutzen. CORS, Origin und das Verbergen des Publishable Keys sind kein Identitäts-/Missbrauchsschutz.
- Die Ereignisse enthalten keine IP-Adressen oder Gerätefingerprints. Es werden Auth-ID, Fragebogeninhalte und Serverzeiten erfasst. Auth-/Plattformlogs können unabhängig davon Verbindungsdaten erfassen.
- Bei Browserdatenlöschung wird eine neue anonyme Kennung erzeugt. Der alte Datensatz bleibt für Forschung erhalten.
- Datenwachstum/Löschfristen/Export und Auth-Kontenpflege sind Betreiberaufgaben. Das Limit pro User speichert eine Zeile je Auth-ID; Idempotenzantworten bleiben für Forschung erhalten, bis exportiert/reset wird.

Offizielle Dokumentation:
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/platform/network-restrictions
- https://supabase.com/docs/guides/auth/auth-anonymous
- https://supabase.com/docs/guides/functions/examples/rate-limiting
