import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/data/course_repository.dart';
import 'package:kodik/models/exercise.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parse курс из assets', () async {
    final course = await CourseRepository.loadFromAssets();
    expect(course.title, 'Python-разработчик');
    expect(course.moduleCount, 9);
    expect(course.totalLessons, 71);
    final m1 = course.modules.first;
    expect(m1.title, 'Введение в Python');
    expect(m1.lessonCount, 11);
    final practice = m1.lessons.firstWhere((l) => l.isPractice);
    expect(practice.title, contains('Практика'));
    expect(practice.exercises.length, greaterThan(10));
  });

  test('id уроков уникальны и предсказуемы', () async {
    final course = await CourseRepository.loadFromAssets();
    final m = course.modules.first;
    final ids = m.lessons.map((l) => l.id).toSet();
    expect(ids.length, m.lessonCount);
    expect(m.lessons.first.id, 'm1-l1');
    expect(m.lessons.last.id, 'm1-l11');
  });

  test('все упражнения модуля валидны', () async {
    final course = await CourseRepository.loadFromAssets();
    var tasks = 0;
    for (final m in course.modules) {
      for (final l in m.lessons) {
        expect(l.xp, greaterThan(0));
        for (final e in l.exercises) {
          expect(e.kind, isA<ExerciseKind>());
          if (e.hasTask) {
            tasks++;
            final t = e.task!;
            expect(t.explanation, isNotEmpty);
            switch (t.type) {
              case TaskType.single:
              case TaskType.codeOutput:
                expect(t.correct.length, 1);
                expect(t.correct.first, lessThan(t.options.length));
              case TaskType.multi:
                expect(t.correct.length, greaterThan(1));
              case TaskType.trueFalse:
                expect(t.correctBool, isNotNull);
              case TaskType.fill:
                expect(t.answers, isNotEmpty);
              case TaskType.codeBuild:
                expect(t.correct.length, t.options.length);
                for (var c in t.correct) {
                  expect(c, lessThan(t.options.length));
                }
                expect(t.correct.toSet().length, t.correct.length,
                    reason: 'code_build должен быть перестановкой');
              case TaskType.codeEditor:
                expect(t.starter, isNotEmpty);
                expect(t.referenceOutput, isNotEmpty);
                expect(t.solution, isNotEmpty);
            }
          }
        }
      }
    }
    expect(tasks, greaterThan(50));
  });

  test('проекты code_editor проходят editor_check своим решением', () async {
    final course = await CourseRepository.loadFromAssets();
    var projects = 0;
    for (final m in course.modules) {
      for (final l in m.lessons) {
        for (final e in l.exercises) {
          final t = e.task;
          if (t == null || t.type != TaskType.codeEditor) continue;
          if (t.editorCheck.isEmpty) continue;
          projects++;
          expect(
            t.checkEditorCode(t.solution),
            isTrue,
            reason: '${l.id}: решение не проходит editor_check',
          );
        }
      }
    }
    expect(projects, greaterThanOrEqualTo(9));
  });

  test('мягкая проверка принимает переиначенный код с тем же смыслом', () {
    const task = Task(
      type: TaskType.codeEditor,
      editorCheck: [
        EditorCheckCase(stdin: 'Аня\n', require: ['Привет, Аня!']),
      ],
    );
    expect(
      task.checkEditorCode('name = input()\nprint(f"Привет, {name}!")'),
      isTrue,
    );
    expect(
      task.checkEditorCode('n = input()\nprint("Привет, " + n + "!")'),
      isTrue,
    );
    expect(task.checkEditorCode('print("Пока")'), isFalse);
  });

  test('многострочный вывод в вариантах хранится с переносами строк', () async {
    final course = await CourseRepository.loadFromAssets();
    for (final m in course.modules) {
      for (final l in m.lessons) {
        for (final e in l.exercises) {
          for (final o in e.task?.options ?? const <String>[]) {
            expect(
              o.contains(r'\n'),
              isFalse,
              reason: '${l.id}: вариант содержит литеральный \\n',
            );
          }
        }
      }
    }
  });

  test('fill принимает и полную строку, и только пропуск', () {    const task = Task(
      type: TaskType.fill,
      question: 'q',
      fillBefore: '',
      fillAfter: '("Меня зовут Ботти!")',
      answers: ['print'],
    );
    expect(task.checkAnswer('print'), isTrue);
    expect(task.checkAnswer('print("Меня зовут Ботти!")'), isTrue);
    expect(task.checkAnswer("print('Меня зовут Ботти!')"), isTrue);
    expect(task.checkAnswer('print(1)'), isFalse);
    expect(task.checkAnswer('  PRINT("Меня зовут Ботти!") '), isTrue);
  });

  test('fill с синтаксисом x = ___ печатает то же самое', () {
    const task = Task(
      type: TaskType.fill,
      question: 'q',
      fillBefore: 'x = ',
      fillAfter: '',
      answers: ['42'],
    );
    expect(task.checkAnswer('42'), isTrue);
    expect(task.checkAnswer('x = 42'), isTrue);
    expect(task.checkAnswer('  42  '), isTrue);
    expect(task.checkAnswer('43'), isFalse);
  });

  test('parse вручную собранного JSON', () {
    const json = '''
    {"title":"T","modules":[
      {"number":1,"title":"M","lessons":[
        {"type":"lesson","title":"L1","xp":10,"exercises":[
          {"kind":"theory","text":"a"},
          {"kind":"theory_task","text":"b","code":"print(1)",
           "task":{"type":"single","question":"q","options":["x","y"],"correct":[1],"explanation":"e"}}
        ]},
        {"type":"practice","title":"P","xp":40,"exercises":[
          {"kind":"theory_task","text":"c",
           "task":{"type":"tf","question":"t","correct_bool":true,"explanation":"e"}}
        ]}
      ]}
    ]}''';
    final course = CourseRepository.parse(json);
    expect(course.totalLessons, 2);
    expect(course.modules.first.lessons.first.exercises.length, 2);
    expect(course.modules.first.lessons.last.isPractice, true);
  });
}