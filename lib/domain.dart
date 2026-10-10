class AnswerOption {
  final String id;
  final String label;
  final int code;
  AnswerOption({required this.id, required this.label, required this.code});
  factory AnswerOption.fromJson(Map<String, dynamic> json) => AnswerOption(
    id: json['id'] as String, label: json['label'] as String,
    code: (json['code'] as num).toInt());
}

class Question {
  final String id;
  final String title;
  final List<AnswerOption> options;
  Question({required this.id, required this.title, required this.options});
  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'] as String, title: json['title'] as String,
    options: (json['options'] as List).map((e) => AnswerOption.fromJson(
      Map<String, dynamic>.from(e as Map))).toList());
}

class Study {
  final String runId;
  final String versionId;
  final String title;
  final List<Question> questions;
  Study({required this.runId, required this.versionId, required this.title, required this.questions});
  factory Study.fromJson(Map<String, dynamic> json) => Study(
    runId: json['run_id'] as String, versionId: json['version_id'] as String,
    title: json['title'] as String,
    questions: (json['questions'] as List).map((e) => Question.fromJson(
      Map<String, dynamic>.from(e as Map))).toList());
}

class Decision {
  final String id;
  final int code;
  final String title;
  final String text;
  Decision({required this.id, required this.code, required this.title, required this.text});
  factory Decision.fromJson(Map<String, dynamic> json) => Decision(
    id: json['id'] as String, code: (json['code'] as num).toInt(),
    title: json['title'] as String, text: json['text'] as String);
}
