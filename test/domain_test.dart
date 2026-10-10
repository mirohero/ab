import 'package:flutter_test/flutter_test.dart';
import 'package:fragebogen_app/domain.dart';

void main() {
  test('Server-IDs und Zahlencodes bleiben beim Einlesen erhalten', () {
    final study = Study.fromJson({
      'run_id': 'run', 'version_id': 'v1', 'title': 'Server-Titel',
      'questions': [{'id': 'q1', 'title': 'Server-Frage', 'options': [
        {'id': 'a', 'label': 'Option A', 'code': 7},
        {'id': 'b', 'label': 'Option B', 'code': 8},
      ]}],
    });
    expect(study.questions.single.options.first.code, 7);
    expect(study.questions.single.id, 'q1');
    final decision = Decision.fromJson({'id':'r', 'code':42, 'title':'Server-Ergebnis', 'text':'Server-Antwort'});
    expect(decision.code, 42);
    expect(decision.text, 'Server-Antwort');
  });
}
