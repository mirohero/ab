# Flutter Fragebogen mit Supabase

Web-Grundprojekt mit drei Beispielfragen, regelbasierter Support-Empfehlung, zentral gespeicherten Eingaben/Ergebnissen, Bearbeitungszeiten und eigenem Verlauf. Hosting: GitHub Pages; Backend: Supabase.

## 1. Supabase vorbereiten

1. Supabase-Projekt erstellen.
2. `supabase/schema.sql` im SQL Editor ausführen. Es erstellt Tabelle, Constraints, Grants und RLS-Regeln für den Zugriff auf eigene Daten. Für eine neue Tabelle vorgesehen; bestehende fremde Policies nicht übernehmen.
3. Unter Authentication → Sign In / Providers die **Anonymous Sign-Ins** aktivieren. Die App meldet Nutzer automatisch anonym an; es gibt kein Registrierungsformular.
4. Projekt-URL und **Publishable Key** aus dem Connect-Dialog kopieren.
5. In den Data-API-Einstellungen sicherstellen, dass die Data API aktiviert und das Schema `public` erreichbar ist.

## 2. Externe Variablendatei bearbeiten

Alle Werte in `config/app_config.json` eintragen:

```json
{
  "STORAGE_MODE": "supabase",
  "SUPABASE_URL": "https://DEIN_PROJEKT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_DEIN_KEY"
}
```

Diese JSON-Datei wird **beim Start/Build** eingelesen, nicht erst zur Laufzeit geladen. Nach einer Änderung erneut starten bzw. bauen. URL und Publishable Key sind öffentlich und werden Bestandteil der Webapp. Ausschließlich den öffentlichen Publishable Key verwenden; keine Secret Keys, service_role-Schlüssel oder Datenbankpasswörter eintragen. RLS schützt die Daten, nicht das Verbergen des Publishable Keys.

Für die lokale Demo ohne Backend `STORAGE_MODE` auf `local` setzen. Vorhandene lokale Daten werden nicht automatisch zu Supabase hochgeladen.

## 3. Starten und prüfen

Aktuelles Flutter Stable SDK installieren. Im Projektordner:

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=config/app_config.json
```

Prüfungen:

```bash
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=config/app_config.json
```

Bei fehlenden Variablen erscheint eine Konfigurationsmeldung. Fehler beim Laden oder Schreiben werden angezeigt; es gibt keinen stillen Wechsel auf lokale Speicherung.

## 4. GitHub Pages

Den Inhalt dieses Ordners einschließlich `.github` ins Repository-Stammverzeichnis kopieren. `config/app_config.json` vorher mit den öffentlichen Projektwerten ausfüllen. Unter Repository Settings → Pages als Quelle **GitHub Actions** auswählen. Zu `main` pushen oder den mitgelieferten Workflow starten. Der Workflow führt Analyse, Tests und Build aus, liest die JSON-Konfiguration und bestimmt den passenden Pages-Basispfad.

Manuell für Repository-Pages:

```bash
flutter build web --release --base-href /DEIN_REPOSITORY/ --dart-define-from-file=config/app_config.json
```

Das Verzeichnis `build/web` ist die fertige statische Webseite. Es wird bei GitHub Pages gehostet, Supabase verarbeitet die Daten.

## Speicherung und Zugriff

- Ein Datensatz pro Fragebogen: ID, Eigentümer-ID, Start/Abschluss in UTC, Antworten und Ergebnis als JSON.
- Speicherung beim Start, nach jeder Auswahl und nach der Auswertung; offene Fragebögen lassen sich fortsetzen.
- Updates schreiben nur den betroffenen Fragebogen, nicht den ganzen Verlauf.
- RLS erlaubt Lesen, Einfügen, Ändern und Löschen ausschließlich für `auth.uid() = user_id`.
- Nutzer sehen ihren eigenen Verlauf. Als Projektbetreiber kannst du alle Daten im Supabase Table Editor auswerten; eine geschützte Admin-Webseite ist noch nicht enthalten.
- Anonyme Sitzungen bleiben im Browser gespeichert. Löschen der Browserdaten oder Nutzung eines anderen Browsers erzeugt eine neue Kennung: Die bisherigen Datensätze bleiben zentral gespeichert, sind für diesen Besucher aber nicht mehr erreichbar. Für geräteübergreifenden Zugriff später einen regulären Login ergänzen.
- „Verlauf löschen“ löscht nur Fragebogen-Datensätze der aktuellen Kennung, nicht den Auth-Benutzer.
- Fragen und `evaluate` in `lib/domain.dart` sind Demo-Regeln im Client. Bei verbindlichen Entscheidungen serverseitig validieren und auswerten.
- Bei konkurrierender Bearbeitung desselben Fragebogens gewinnt die letzte Speicherung. Keine Offline-Warteschlange.
- Vor öffentlichem Einsatz bei anonymen Anmeldungen den von Supabase empfohlenen CAPTCHA-/Missbrauchsschutz konfigurieren. CAPTCHA ist in diesem Grundprojekt noch nicht integriert.

## Dateien

| Datei | Aufgabe |
|---|---|
| `config/app_config.json` | Deine Variablen |
| `lib/app_config.dart` | Konfiguration und Prüfung |
| `lib/domain.dart` | Fragen, Datenmodell, Regeln |
| `lib/repository.dart` | Lokale und Supabase-Speicherung |
| `lib/main.dart` | UI und Start |
| `supabase/schema.sql` | Tabelle und Zugriffsregeln |
| `test/` | Regeln, JSON-Roundtrip und Fragebogenablauf |

## Verifikation und Einrichtungstest

In der Erstellungsumgebung fehlt Flutter/Dart. Deshalb wurden die Flutter-Tests, Analyse und der Web-Build hier **nicht ausgeführt**. Auch das SQL wurde noch nicht gegen ein Supabase-Projekt ausgeführt. Syntax-nahe String-Prüfung, Konfigurations-JSON und ZIP-Inhalt wurden geprüft; vollständige Prüfung erfolgt lokal bzw. im GitHub-Workflow.

Nach Einrichtung einen Fragebogen abschließen, Seite neu laden und den gespeicherten Verlauf prüfen. In einem zweiten Browser/Inkognito-Fenster einen zweiten Fragebogen starten: Der Verlauf des ersten Browsers darf dort nicht sichtbar sein. Im Supabase Table Editor müssen beide Nutzerkennungen vorhanden sein. Löschen im zweiten Browser darf den ersten Datensatz nicht entfernen.

Dokumentation:
- https://supabase.com/docs/guides/getting-started/quickstarts/flutter
- https://supabase.com/docs/guides/auth/auth-anonymous
- https://supabase.com/docs/guides/database/postgres/row-level-security
