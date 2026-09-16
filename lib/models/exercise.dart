enum ExerciseKind { theory, theoryTask }

enum TaskType { single, multi, trueFalse, fill, codeOutput }

enum TaskStatus { unattempted, correct, wrong }

class Task {
  final TaskType type;
  final String question;
  final List<String> options;
  final List<int> correct;
  final bool? correctBool;
  final String fillBefore;
  final String fillAfter;
  final List<String> answers;
  final bool caseInsensitive;
  final String explanation;

  const Task({
    required this.type,
    this.question = '',
    this.options = const [],
    this.correct = const [],
    this.correctBool,
    this.fillBefore = '',
    this.fillAfter = '',
    this.answers = const [],
    this.caseInsensitive = true,
    this.explanation = '',
  });

  factory Task.fromJson(Map<String, dynamic> j) {
    return Task(
      type: _parseTaskType(j['type'] as String),
      question: (j['question'] as String?) ?? '',
      options: ((j['options'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      correct: ((j['correct'] as List<dynamic>?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      correctBool: j['correct_bool'] as bool?,
      fillBefore: (j['fill_before'] as String?) ?? '',
      fillAfter: (j['fill_after'] as String?) ?? '',
      answers: ((j['answers'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      caseInsensitive: (j['case_insensitive'] as bool?) ?? true,
      explanation: (j['explanation'] as String?) ?? '',
    );
  }

  static TaskType _parseTaskType(String s) {
    switch (s) {
      case 'single':
        return TaskType.single;
      case 'multi':
        return TaskType.multi;
      case 'tf':
        return TaskType.trueFalse;
      case 'fill':
        return TaskType.fill;
      case 'code_output':
        return TaskType.codeOutput;
      default:
        throw ArgumentError('Unknown task type: $s');
    }
  }

  bool isSingleChoice() =>
      type == TaskType.single || type == TaskType.codeOutput;

  bool checkAnswer(dynamic answer) {
    switch (type) {
      case TaskType.single:
      case TaskType.codeOutput:
        return correct.isNotEmpty && answer == correct.first;
      case TaskType.multi:
        if (answer is! List) return false;
        final sel = answer.cast<int>().toSet();
        final right = correct.toSet();
        return sel.length == right.length && sel.containsAll(right);
      case TaskType.trueFalse:
        return correctBool != null && answer == correctBool;
      case TaskType.fill:
        return _checkFill(answer);
    }
  }

  bool _checkFill(dynamic answer) {
    if (answer is! String || answers.isEmpty) return false;
    final a = _norm(answer.trim());
    for (final expected in answers) {
      final e = _norm(expected.trim());
      if (a == e) return true;
      final full = _norm('$fillBefore$e$fillAfter');
      if (full.isNotEmpty && a == full) return true;
    }
    return false;
  }

  String _norm(String s) {
    var out = s.replaceAll(RegExp(r'\s+'), ' ');
    if (caseInsensitive) out = out.toLowerCase();
    return out;
  }
}

class Exercise {
  final ExerciseKind kind;
  final String text;
  final String? code;
  final Task? task;

  const Exercise({
    required this.kind,
    this.text = '',
    this.code,
    this.task,
  });

  bool get hasTask => task != null;

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final kind = (j['kind'] as String) == 'theory_task'
        ? ExerciseKind.theoryTask
        : ExerciseKind.theory;
    return Exercise(
      kind: kind,
      text: (j['text'] as String?) ?? '',
      code: j['code'] as String?,
      task: (j['task'] as Map<String, dynamic>?) == null
          ? null
          : Task.fromJson(j['task'] as Map<String, dynamic>),
    );
  }
}