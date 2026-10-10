import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fragebogen_app/main.dart';
import 'package:fragebogen_app/repository.dart';

class MemoryRepository implements StudyRepository {
  final List<String> requestIds = [];
  final List<String> actions = [];
  bool failOnce = false;
  @override
  Future<Map<String,dynamic>> call(String requestId, String action,
    {String? runId, String? questionId, String? optionId}) async {
    requestIds.add(requestId); actions.add(action);
    if (failOnce) { failOnce=false; throw Exception('network'); }
    if (action=='visit') {
      return {'run_id':'run', 'version_id':'v', 'title':'Server-Titel', 'questions':[
        {'id':'q','title':'Server-Frage','options':[
          {'id':'a','label':'Antwort A','code':1},
          {'id':'b','label':'Antwort B','code':2},
        ]},
      ]};
    }
    if (action=='selection') return {'answers':{questionId!:optionId!}};
    return {'result':{'id':'result','code':9,'title':'Server-Ergebnis','text':'Server-Antwort'}};
  }
}

void main() {
  testWidgets('Erster Aufruf, Auswahl und Ergebnis nutzen Server-API', (tester) async {
    final repository=MemoryRepository();
    await tester.pumpWidget(QuestionnaireApp(repository:repository));
    await tester.pumpAndSettle();
    expect(repository.actions, ['visit']);
    expect(find.text('Server-Frage'), findsOneWidget);
    await tester.pump(const Duration(seconds:1));
    await tester.tap(find.text('Antwort A'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds:1));
    final button=find.text('Ergebnis ermitteln');
    await tester.ensureVisible(button); await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repository.actions, ['visit','selection','finish']);
    expect(find.text('Server-Antwort'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Manueller Retry behält Request-ID und sendet nicht automatisch', (tester) async {
    final repository=MemoryRepository()..failOnce=true;
    await tester.pumpWidget(QuestionnaireApp(repository:repository));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds:4));
    expect(repository.requestIds.length,1);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(repository.requestIds.length,2);
    expect(repository.requestIds[0],repository.requestIds[1]);
    await tester.pumpWidget(const SizedBox());
  });
}
