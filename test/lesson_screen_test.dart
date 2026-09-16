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
    final lesson = Lesson(
      id: 'm1-l1',
      title: 'Тест',
      isPractice: false,
      xp: 15,
      exercises: [
        const Exercise(
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

  testWidgets('онбординг: ввод имени открывает курс', (tester) async {
    final course = Course(
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
              exercises: const [
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