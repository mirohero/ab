import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'domain.dart';
import 'repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    await Supabase.initialize(url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey);
    runApp(QuestionnaireApp(repository: SupabaseStudyRepository(Supabase.instance.client)));
  } catch (_) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: EdgeInsets.all(24), child: Text('Start fehlgeschlagen. Bitte config/app_config.json und Internetverbindung prüfen.'),
    )))));
  }
}

class QuestionnaireApp extends StatelessWidget {
  final StudyRepository repository;
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
  final StudyRepository repository;
  const QuestionnairePage({super.key, required this.repository});
  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage> {
  Study? _study;
  Decision? _decision;
  Map<String, String> _answers = {};
  PendingRequest? _pending;
  int _step = 0;
  int _wait = 0;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  bool get _locked => _busy || _wait > 0 || _pending != null;

  @override
  void initState() { super.initState(); _send(PendingRequest('visit')); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _cooldown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  Future<void> _send(PendingRequest request) async {
    if (_busy || _wait > 0) return;
    setState(() { _busy = true; _error = null; _pending = request; });
    try {
      final data = await widget.repository.call(request.id, request.action,
        runId: request.runId, questionId: request.questionId, optionId: request.optionId);
      if (!mounted) return;
      setState(() {
        if (request.action == 'visit') {
          _study = Study.fromJson(data); _answers = {}; _decision = null; _step = 0;
        } else if (request.action == 'selection') {
          _answers = Map<String, String>.from(data['answers'] as Map);
        } else if (request.action == 'finish') {
          _decision = Decision.fromJson(Map<String, dynamic>.from(data['result'] as Map));
        }
        _pending = null;
      });
      // No automatic retries or polling; requests are serialized.
      _cooldown(1);
    } catch (error) {
      if (!mounted) return;
      if (error is StudyApiException) {
        setState(() => _error = switch (error.code) {
          'RATE_LIMIT' => 'Zu viele Anfragen. Bitte warte vor dem erneuten Versuch.',
          'NO_PUBLISHED_STUDY' => 'Der Fragebogen ist noch nicht veröffentlicht.',
          'RUN_NOT_FOUND' => 'Dieser Durchlauf ist nicht mehr vorhanden. Bitte lade die Seite neu.',
          _ => 'Server hat die Anfrage abgelehnt (${error.code}).',
        });
        _cooldown(error.retryAfter > 0 ? error.retryAfter : 3);
      } else {
        setState(() => _error = 'Anfrage nicht bestätigt. Prüfe deine Verbindung und versuche es erneut.');
        _cooldown(3);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final study = _study;
    final decision = _decision;
    return Scaffold(
      appBar: AppBar(title: Text(study?.title ?? 'Entscheidungsassistent')),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Schritt für Schritt zur Antwort', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('Aufruf, bestätigte Auswahlen und Ergebnis werden mit Server-Zeitstempeln unter einer pseudonymen Nutzerkennung gespeichert.'),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || _wait > 0 || _pending == null ? null : () => _send(_pending!),
              child: Text(_wait > 0 ? 'Erneut versuchen in $_wait s' : 'Erneut versuchen')),
          ],
          if (study != null) Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (decision != null) ...[
                Text(decision.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12), Text(decision.text),
                const SizedBox(height: 16), const Text('Ergebnis serverseitig gespeichert.'),
                FilledButton(onPressed: _locked ? null : () => _send(PendingRequest('visit')),
                  child: const Text('Neuer Durchlauf')),
              ] else ...[
                Text('Frage ${_step + 1} von ${study.questions.length}'),
                const SizedBox(height: 12), LinearProgressIndicator(value: (_step + 1) / study.questions.length),
                const SizedBox(height: 24),
                Text(study.questions[_step].title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                for (final option in study.questions[_step].options)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton.icon(
                    onPressed: _locked ? null : () => _send(PendingRequest('selection',
                      runId: study.runId, questionId: study.questions[_step].id, optionId: option.id)),
                    icon: Icon(_answers[study.questions[_step].id] == option.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    label: Padding(padding: const EdgeInsets.all(12), child: Text(option.label)))),
                const SizedBox(height: 16), Row(children: [
                  TextButton(onPressed: _locked || _step == 0 ? null : () => setState(() => _step--), child: const Text('Zurück')),
                  const Spacer(), FilledButton(
                    onPressed: _locked || _answers[study.questions[_step].id] == null ? null : () {
                      if (_step < study.questions.length - 1) { setState(() => _step++); }
                      else { _send(PendingRequest('finish', runId: study.runId)); }
                    }, child: Text(_step == study.questions.length - 1 ? 'Ergebnis ermitteln' : 'Weiter')),
                ]),
              ],
            ],
          ))),
        ]),
      )),
    );
  }
}
