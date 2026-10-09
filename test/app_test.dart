import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fragebogen_app/main.dart';
import 'package:fragebogen_app/domain.dart';
import 'package:fragebogen_app/repository.dart';

class MemoryRepository implements SessionRepository {
  List<Session> sessions = [];
  @override
  Future<List<Session>> load() async => sessions;
  @override
  Future<void> save(Session value) async {
    sessions = [...sessions.where((s) => s.id != value.id), value];
  }
  @override
  Future<void> clear() async { sessions = []; }
}

void main() {
  testWidgets('Fragebogen speichert Eingaben und Abschluss', (tester) async {
    final repository = MemoryRepository();
    await tester.pumpWidget(QuestionnaireApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fragebogen starten'));
    await tester.pumpAndSettle();
    expect(repository.sessions.length, 1);
    expect(find.widgetWithText(FilledButton, 'Weiter').evaluate().single.widget,
      isA<FilledButton>().having((button) => button.onPressed, 'disabled', isNull));
    for (final answer in ['Software', 'Dringend', 'Mehrere Personen']) {
      await tester.tap(find.text(answer).first);
      await tester.pumpAndSettle();
      final button = find.text(answer == 'Mehrere Personen' ? 'Ergebnis ermitteln' : 'Weiter');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(repository.sessions.single.completedAt, isNotNull);
    expect(repository.sessions.single.answers.length, 3);
    expect(repository.sessions.single.decision!.title, 'Hohe Priorität');
    expect(find.text('Ergebnis gespeichert.'), findsOneWidget);
  });
}
