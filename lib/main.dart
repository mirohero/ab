import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'repository.dart';
import 'app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    final SessionRepository repository;
    if (AppConfig.storageMode == 'local') {
      repository = LocalSessionRepository();
    } else {
      await Supabase.initialize(url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey);
      repository = SupabaseSessionRepository(Supabase.instance.client);
    }
    runApp(QuestionnaireApp(repository: repository));
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: SelectableText('Start fehlgeschlagen: $error'),
    )))));
  }
}

class QuestionnaireApp extends StatelessWidget {
  final SessionRepository repository;
  const QuestionnaireApp({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Entscheidungsassistent',
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff275dad))),
    home: QuestionnairePage(repository: repository),
  );
}

class QuestionnairePage extends StatefulWidget {
  final SessionRepository repository;
  const QuestionnairePage({super.key, required this.repository});
  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage> {
  List<Session> _sessions = [];
  Session? _active;
  int _step = 0;
  bool _busy = true;
  bool _loaded = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final sessions = await widget.repository.load();
      if (!mounted) return;
      setState(() { _sessions = sessions; _loaded = true; _busy = false; _error = null; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Verlauf konnte nicht geladen werden. Prüfe Internetverbindung, Supabase-Tabelle und anonyme Anmeldung; bitte erneut versuchen.'; });
    }
  }

  Future<bool> _persist(List<Session> next, {Session? changed}) async {
    setState(() { _busy = true; _error = null; });
    try {
      if (changed == null) {
        await widget.repository.clear();
      } else {
        await widget.repository.save(changed);
      }
      if (!mounted) return false;
      setState(() => _sessions = next);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen. Bitte prüfe Verbindung und Konfiguration und versuche es erneut.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final now = DateTime.now().toUtc();
    final session = Session(id: now.microsecondsSinceEpoch.toString(), startedAt: now, answers: {});
    if (await _persist([..._sessions, session], changed: session) && mounted) {
      setState(() { _active = session; _step = 0; });
    }
  }

  Future<void> _answer(String value) async {
    final active = _active!;
    final updated = Session(id: active.id, startedAt: active.startedAt,
      answers: {...active.answers, questions[_step].id: value});
    if (await _persist(_sessions.map((s) => s.id == updated.id ? updated : s).toList(), changed: updated) && mounted) {
      setState(() => _active = updated);
    }
  }

  Future<void> _finish() async {
    final active = _active!;
    final result = Session(id: active.id, startedAt: active.startedAt,
      completedAt: DateTime.now().toUtc(), answers: active.answers,
      decision: evaluate(active.answers));
    if (await _persist(_sessions.map((s) => s.id == result.id ? result : s).toList(), changed: result) && mounted) {
      setState(() => _active = result);
    }
  }

  String _date(DateTime value) => value.toLocal().toString().split('.').first;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Eigenen Verlauf löschen?'),
      content: const Text('Alle Eingaben und Ergebnisse deiner aktuellen Nutzerkennung werden gelöscht.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen'))],
    ));
    if (confirmed == true && mounted && await _persist([]) && mounted) {
      setState(() => _active = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final completed = _sessions.where((s) => s.completedAt != null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Entscheidungsassistent')),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Eine klare Antwort. Schritt für Schritt.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(widget.repository is SupabaseSessionRepository
            ? 'Demo mit festen Regeln. Eingaben und Ergebnisse werden zentral in Supabase unter einer anonymen Nutzerkennung gespeichert.'
            : 'Demo mit festen Regeln. Eingaben und Ergebnisse werden lokal auf diesem Gerät gespeichert.'),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!_loaded && !_busy) FilledButton(onPressed: _load, child: const Text('Erneut laden')),
          if (_loaded) Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (active == null) ...[
                const Text('Beantworte drei Fragen für eine Support-Empfehlung.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _start, child: const Text('Fragebogen starten')),
              ] else if (active.decision != null) ...[
                Text(active.decision!.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12), Text(active.decision!.text),
                const SizedBox(height: 16), const Text('Ergebnis gespeichert.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _start, child: const Text('Neuer Fragebogen')),
              ] else ...[
                Text('Frage ${_step + 1} von ${questions.length}'),
                const SizedBox(height: 12), LinearProgressIndicator(value: (_step + 1) / questions.length),
                const SizedBox(height: 24), Text(questions[_step].title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                for (final option in questions[_step].options)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _answer(option),
                    icon: Icon(active.answers[questions[_step].id] == option ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    label: Padding(padding: const EdgeInsets.all(12), child: Text(option)))),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(onPressed: _busy || _step == 0 ? null : () => setState(() => _step--), child: const Text('Zurück')),
                  const Spacer(), FilledButton(
                    onPressed: _busy || active.answers[questions[_step].id] == null ? null : () {
                      if (_step < questions.length - 1) { setState(() => _step++); } else { _finish(); }
                    }, child: Text(_step == questions.length - 1 ? 'Ergebnis ermitteln' : 'Weiter')),
                ]),
              ],
            ],
          ))),
          const SizedBox(height: 28),
          Text('Mein Verlauf', style: Theme.of(context).textTheme.titleLarge),
          Text('${_sessions.length} gestartet · $completed abgeschlossen · ${_sessions.length - completed} offen'),
          const SizedBox(height: 12),
          if (_sessions.isEmpty) const Text('Noch keine Nutzungen gespeichert.'),
          for (final session in _sessions.reversed) Card(child: ExpansionTile(
            title: Text(session.decision?.title ?? 'Nicht abgeschlossen'),
            subtitle: Text(_date(session.startedAt)),
            children: [Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final question in questions) Text('${question.title}\n${session.answers[question.id] ?? '–'}\n'),
                if (session.decision != null) Text(session.decision!.text),
                if (session.completedAt != null) Text('Dauer: ${session.completedAt!.difference(session.startedAt).inSeconds} Sekunden'),
                if (session.completedAt == null) TextButton(onPressed: _busy ? null : () => setState(() { _active = session; _step = 0; }), child: const Text('Fortsetzen')),
              ],
            ))],
          )),
          if (_loaded && _sessions.isNotEmpty) Wrap(spacing: 12, children: [
            TextButton.icon(onPressed: _busy ? null : () async {
              await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_sessions.map((s) => s.toJson()).toList())));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON in die Zwischenablage kopiert.')));
            }, icon: const Icon(Icons.copy), label: const Text('JSON kopieren')),
            TextButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline), label: const Text('Verlauf löschen')),
          ]),
        ]),
      )),
    );
  }
}
