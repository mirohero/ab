class Question {
  final String id;
  final String title;
  final List<String> options;
  const Question(this.id, this.title, this.options);
}

const questions = [
  Question('topic', 'Welches Thema betrifft deine Anfrage?',
      ['Software', 'Hardware', 'Sonstiges']),
  Question('urgency', 'Wie dringend ist die Anfrage?', ['Dringend', 'Normal']),
  Question('people', 'Wie viele Personen sind betroffen?',
      ['Eine Person', 'Mehrere Personen']),
];

class Decision {
  final String title;
  final String text;
  const Decision(this.title, this.text);
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
  factory Decision.fromJson(Map<String, dynamic> json) =>
      Decision(json['title'] as String, json['text'] as String);
}

Decision evaluate(Map<String, String> answers) {
  for (final question in questions) {
    if (!question.options.contains(answers[question.id])) {
      throw ArgumentError('Fehlende oder ungültige Antwort: ${question.id}');
    }
  }
  final team = answers['topic'] == 'Hardware'
      ? 'Hardware-Support'
      : answers['topic'] == 'Software'
          ? 'Software-Support'
          : 'Service-Team';
  final urgent = answers['urgency'] == 'Dringend';
  final multiple = answers['people'] == 'Mehrere Personen';
  return Decision(
    urgent && multiple ? 'Hohe Priorität' : urgent ? 'Zeitnah bearbeiten' : 'Reguläre Anfrage',
    'Wende dich an den $team. '
    '${urgent ? 'Melde die Anfrage telefonisch.' : 'Erstelle ein Support-Ticket.'} '
    '${multiple ? 'Nenne die betroffenen Personen und den Umfang der Störung.' : 'Beschreibe das Problem und die bisherigen Schritte.'}',
  );
}

class Session {
  final String id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Map<String, String> answers;
  final Decision? decision;
  Session({required this.id, required this.startedAt, this.completedAt,
    required Map<String, String> answers, this.decision})
      : answers = Map.unmodifiable(answers);
  Map<String, dynamic> toJson() => {
    'id': id, 'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'answers': answers, 'decision': decision?.toJson(),
  };
  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
    answers: Map<String, String>.from(json['answers'] as Map),
    decision: json['decision'] == null ? null : Decision.fromJson(Map<String, dynamic>.from(json['decision'] as Map)),
  );
}
