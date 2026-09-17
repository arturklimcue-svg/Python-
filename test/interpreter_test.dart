import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/data/course_repository.dart';
import 'package:kodik/models/exercise.dart';
import 'package:kodik/services/python_interpreter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('вывод интерпретатора совпадает с эталоном CPython', () {
    final raw = File('test/fixtures/course_outputs.json').readAsStringSync();
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    var passed = 0;
    var skipped = 0;
    final failures = <String>[];
    for (final row in rows) {
      if (row['skip'] != null) {
        skipped++;
        continue;
      }
      final result = runPython(
        row['code'] as String,
        stdin: (row['stdin'] as String?) ?? '',
      );
      final expected = row['out'] as String;
      if (!result.ok || result.stdout != expected) {
        failures.add(
          '${row['key']}: got ${jsonEncode(result.stdout)} '
          'err=${jsonEncode(result.error)} want ${jsonEncode(expected)}',
        );
      } else {
        passed++;
      }
    }
    expect(failures, isEmpty);
    expect(passed, greaterThan(150));
    expect(skipped, greaterThan(0));
  });

  test('решения заданий code_editor дают эталонный вывод', () async {
    final course = await CourseRepository.loadFromAssets();
    var checked = 0;
    for (final module in course.modules) {
      for (final lesson in module.lessons) {
        for (final exercise in lesson.exercises) {
          if (!exercise.hasTask) continue;
          final task = exercise.task!;
          if (task.type != TaskType.codeEditor) continue;
          checked++;
          final result = runPython(task.solution, stdin: task.stdin);
          expect(result.ok, isTrue, reason: '${lesson.id}: ${result.error}');
          expect(
            task.checkEditorOutput(result.stdout),
            isTrue,
            reason: '${lesson.id}: got ${jsonEncode(result.stdout)}',
          );
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(10));
  });

  test('все проекты проходят гибкую проверку своим решением', () async {
    final course = await CourseRepository.loadFromAssets();
    var checked = 0;
    for (final module in course.modules) {
      for (final lesson in module.lessons) {
        for (final exercise in lesson.exercises) {
          if (!exercise.hasTask) continue;
          final task = exercise.task!;
          if (task.type != TaskType.codeEditor) continue;
          if (task.editorCheck.isEmpty) continue;
          checked++;
          expect(task.checkEditorCode(task.solution), isTrue,
              reason: '${lesson.id}: project solution fails editor_check');
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(9));
  });

  test('эмуляция requests: статус, json и текст ответа', () {
    final r = runPython(
        'import requests\n'
        'r = requests.get("https://api.example.com/rates")\n'
        'print(r.status_code)\n'
        'print(r.json()["rates"]["RUB"])');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.stdout, '200\n92.5\n');

    final chat = runPython(
        'import requests\n'
        'r = requests.post("https://api.ai.example/generate", '
        'json={"prompt": "Привет!"})\n'
        'print(r.json()["choices"][0]["content"])');
    expect(chat.ok, isTrue, reason: chat.error);
    expect(chat.stdout, 'Привет, друг!\n');

    final text = runPython(
        'import requests\n'
        'r = requests.get("https://api.example.com/rates")\n'
        'print("RUB" in r.text)');
    expect(text.stdout, 'True\n');
  });

  test('недоступные модули объясняют причину', () {
    final r = runPython('import datetime');
    expect(r.ok, isFalse);
    expect(r.error, contains('недоступен'));
    final r2 = runPython('import qwerty');
    expect(r2.error, contains('No module named'));
  });

  test('input сообщает, что данных во stdin не хватило', () {
    final r = runPython('name = input("Как зовут? ")\nprint("Привет,", name)');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.inputsMissing, 1);
    expect(r.stdout, 'Как зовут? Привет, \n');

    final partial = runPython('a = input()\nb = input()', stdin: '1');
    expect(partial.inputsMissing, 1);

    final enough = runPython('a = input()\nprint(a)', stdin: '1\n');
    expect(enough.inputsMissing, 0);
    expect(enough.stdout, '1\n');

    final empty = runPython('a = input()', stdin: '');
    expect(empty.inputsMissing, 1);
  });
}
