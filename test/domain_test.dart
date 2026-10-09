import 'package:flutter_test/flutter_test.dart';
import 'package:fragebogen_app/domain.dart';

void main() {
  test('Alle gültigen Antwortkombinationen erzeugen ein Ergebnis', () {
    for (final topic in questions[0].options) {
      for (final urgency in questions[1].options) {
        for (final people in questions[2].options) {
          final result = evaluate({'topic': topic, 'urgency': urgency, 'people': people});
          expect(result.text, isNotEmpty);
          if (urgency == 'Dringend' && people == 'Mehrere Personen') {
            expect(result.title, 'Hohe Priorität');
          }
        }
      }
    }
  });
  test('Unvollständige und ungültige Eingaben werden abgewiesen', () {
    expect(() => evaluate({}), throwsArgumentError);
    expect(() => evaluate({'topic': 'invalid', 'urgency': 'Normal', 'people': 'Eine Person'}), throwsArgumentError);
  });
  test('Session behält Antworten und Ergebnis beim JSON-Roundtrip', () {
    final answers = {'topic': 'Software', 'urgency': 'Normal', 'people': 'Eine Person'};
    final session = Session(id: 'test', startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026, 1, 1, 0, 1), answers: answers, decision: evaluate(answers));
    final restored = Session.fromJson(session.toJson());
    expect(restored.toJson(), session.toJson());
  });
}
