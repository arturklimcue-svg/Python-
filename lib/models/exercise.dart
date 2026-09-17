import '../services/python_interpreter.dart';

enum ExerciseKind { theory, theoryTask }

enum TaskType { single, multi, trueFalse, fill, codeOutput, codeBuild, codeEditor }

enum TaskStatus { unattempted, correct, wrong }

/// Один проверочный прогон для заданий code_editor. Вывод программы ученика
/// нормализуется, после чего проверяется наличие фрагментов [require]
/// и хотя бы одного из [requireAny].
class EditorCheckCase {
  final String stdin;
  final List<String> require;
  final List<String> requireAny;

  const EditorCheckCase({
    this.stdin = '',
    this.require = const [],
    this.requireAny = const [],
  });

  factory EditorCheckCase.fromJson(Map<String, dynamic> j) {
    return EditorCheckCase(
      stdin: (j['stdin'] as String?) ?? '',
      require: ((j['require'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      requireAny: ((j['require_any'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

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
  final String starter;
  final String stdin;
  final String referenceOutput;
  final String solution;
  final List<EditorCheckCase> editorCheck;

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
    this.starter = '',
    this.stdin = '',
    this.referenceOutput = '',
    this.solution = '',
    this.editorCheck = const [],
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
      starter: (j['starter'] as String?) ?? '',
      stdin: (j['stdin'] as String?) ?? '',
      referenceOutput: (j['reference_output'] as String?) ?? '',
      solution: (j['solution'] as String?) ?? '',
      editorCheck: (((j['editor_check'] as Map<String, dynamic>?)?['cases']
                  as List<dynamic>?) ??
              const [])
          .map((e) => EditorCheckCase.fromJson(e as Map<String, dynamic>))
          .toList(),
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
      case 'code_build':
        return TaskType.codeBuild;
      case 'code_editor':
        return TaskType.codeEditor;
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
      case TaskType.codeBuild:
        return _checkBuild(answer);
      case TaskType.codeEditor:
        return answer is String && checkEditorCode(answer);
    }
  }

  /// Сравнивает вывод программы ученика с эталонным, игнорируя
  /// висячие пробелы и пустые строки в конце.
  bool checkEditorOutput(String actual) {
    if (referenceOutput.isEmpty) return false;
    return _normOutput(actual) == _normOutput(referenceOutput);
  }

  /// Гибкая проверка проекта: прогоняет код ученика на каждом кейсе и
  /// проверяет наличие ключевых фрагментов. Если кейсов нет — работает
  /// строгое сравнение с эталоном.
  bool checkEditorCode(String code) {
    if (editorCheck.isEmpty) {
      final r = runPython(code, stdin: stdin);
      return r.ok && checkEditorOutput(r.stdout);
    }
    for (final c in editorCheck) {
      final r = runPython(code, stdin: c.stdin);
      if (!r.ok) return false;
      final out = _lean(r.stdout);
      for (final f in c.require) {
        if (!out.contains(_lean(f))) return false;
      }
      if (c.requireAny.isNotEmpty &&
          !c.requireAny.any((f) => out.contains(_lean(f)))) {
        return false;
      }
    }
    return true;
  }

  /// Нормализация для мягкого сравнения: регистр, пробелы и любые знаки
  /// препинания игнорируются, остаются только буквы и цифры. Так «Привет,
  /// Аня!» и «привет аня» считаются одинаковыми.
  static String _lean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^0-9a-zа-яё]+'), '');

  static String _normOutput(String s) {
    final lines = s
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''))
        .toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    return lines.join('\n');
  }

  bool _checkBuild(dynamic answer) {
    if (answer is! List) return false;
    final order = answer.cast<int>().toList();
    if (order.isEmpty || order.length != correct.length) return false;
    for (var i = 0; i < order.length; i++) {
      if (order[i] != correct[i]) return false;
    }
    return true;
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
    return out.replaceAll("'", '"');
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