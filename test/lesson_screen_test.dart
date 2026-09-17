import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/app.dart';
import 'package:kodik/models/course.dart';
import 'package:kodik/models/exercise.dart';
import 'package:kodik/screens/lesson_screen.dart';
import 'package:kodik/services/progress_service.dart';
import 'package:kodik/services/storage_service.dart';

ProgressService _progress() => ProgressService(MemoryStorage());

void main() {
  testWidgets('экран урока: правильный выбор показывает «Верно!»',
      (tester) async {
    const lesson = Lesson(
      id: 'm1-l1',
      title: 'Тест',
      isPractice: false,
      xp: 15,
      exercises: [
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Вопрос',
          code: 'print(1)',
          task: Task(
            type: TaskType.single,
            question: 'Что выведет?',
            options: ['a', 'b'],
            correct: [1],
            explanation: 'Потому что b',
          ),
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, progress: p)),
    );
    expect(find.text('Что выведет?'), findsOneWidget);

    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Верно!'), findsOneWidget);
    expect(p.xp, 4);
  });

  testWidgets('code_build: сборка программы в верном порядке', (tester) async {
    const lesson = Lesson(
      id: 'm1-l4',
      title: 'Сборка',
      isPractice: false,
      xp: 40,
      exercises: [
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Собери программу',
          task: Task(
            type: TaskType.codeBuild,
            question: 'Расположи строки',
            options: ['b', 'a'],
            correct: [1, 0],
            explanation: 'a, потом b',
          ),
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, progress: p)),
    );

    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Верно!'), findsOneWidget);
    expect(p.xp, 4);
  });

  testWidgets('экран урока: ошибка не пропускает упражнение', (tester) async {
    const lesson = Lesson(
      id: 'm1-l2',
      title: 'Тест 2',
      isPractice: false,
      xp: 15,
      exercises: [
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Вопрос',
          task: Task(
            type: TaskType.single,
            question: 'Что верно?',
            options: ['а', 'б'],
            correct: [1],
            explanation: 'Потому что б',
          ),
        ),
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Следующее',
          task: Task(
            type: TaskType.single,
            question: 'Дальше?',
            options: ['да', 'нет'],
            correct: [0],
          ),
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, progress: p)),
    );
    expect(find.text('Что верно?'), findsOneWidget);

    await tester.tap(find.text('а'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Не совсем'), findsOneWidget);
    expect(find.text('Попробовать ещё раз'), findsOneWidget);
    expect(find.text('Продолжить'), findsNothing);
    expect(p.lessonProgressOf('m1-l2')!.last, 0,
        reason: 'неправильный ответ не двигает позицию');

    await tester.tap(find.text('Попробовать ещё раз'));
    await tester.pump();
    await tester.tap(find.text('б'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Верно!'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Следующее'), findsOneWidget);
    expect(p.xp, 4);
  });

  testWidgets('fill: принимается и полная строка с ответом', (tester) async {
    const lesson = Lesson(
      id: 'm1-l3',
      title: 'Fill',
      isPractice: false,
      xp: 15,
      exercises: [
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Вставь команду',
          task: Task(
            type: TaskType.fill,
            question: 'Бот говорит «Меня зовут Ботти!»',
            fillBefore: '',
            fillAfter: '("Меня зовут Ботти!")',
            answers: ['print'],
          ),
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, progress: p)),
    );

    await tester.enterText(
        find.byType(TextField), 'print("Меня зовут Ботти!")');
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Верно!'), findsOneWidget);
    expect(p.xp, 4);
  });

  testWidgets('code_editor: запуск показывает вывод и засчитывает ответ',
      (tester) async {
    const lesson = Lesson(
      id: 'm1-l1',
      title: 'Редактор',
      isPractice: false,
      xp: 20,
      exercises: [
        Exercise(
          kind: ExerciseKind.theoryTask,
          text: 'Напиши программу',
          task: Task(
            type: TaskType.codeEditor,
            question: 'Выведи Hello, world!',
            starter: '# твой код\n',
            stdin: '',
            referenceOutput: 'Hello, world!\n',
            solution: 'print("Hello, world!")',
            explanation: 'print выводит текст',
          ),
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, progress: p)),
    );
    expect(find.text('Запустить'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField), 'print("Hello, world!")');
    await tester.pump();
    await tester.tap(find.text('Запустить'));
    await tester.pump();

    expect(find.text('Вывод программы'), findsOneWidget);
    expect(find.textContaining('Hello, world!'), findsWidgets);

    await tester.tap(find.text('Проверить'));
    await tester.pump();

    expect(find.text('Верно!'), findsOneWidget);
    expect(p.xp, 4);
  });

  testWidgets('онбординг: ввод имени открывает курс', (tester) async {
    const course = Course(
      title: 'Py',
      modules: [
        CourseModule(
          number: 1,
          title: 'Введение в Python',
          lessons: [
            Lesson(
              id: 'm1-l1',
              title: 'Введение',
              isPractice: false,
              xp: 15,
              exercises: [
                Exercise(kind: ExerciseKind.theory, text: 'Привет'),
              ],
            ),
          ],
        ),
      ],
    );
    final p = _progress();
    await p.load();

    await tester.pumpWidget(KodikApp(course: course, progress: p));
    expect(find.text('КодиК'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField), 'Артём');
    await tester.tap(find.text('Начать обучение'));
    await tester.pumpAndSettle();

    expect(find.text('Модули курса'), findsOneWidget);
    expect(p.userName, 'Артём');
  });
}