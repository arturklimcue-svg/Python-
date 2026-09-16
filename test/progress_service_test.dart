import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/models/course.dart';
import 'package:kodik/models/exercise.dart';
import 'package:kodik/services/progress_service.dart';
import 'package:kodik/services/storage_service.dart';

Course _course({int lessons = 2}) {
  final course = Course(
    title: 'Py',
    modules: [
      CourseModule(
        number: 1,
        title: 'M1',
        lessons: [
          for (var i = 0; i < lessons; i++)
            Lesson(
              id: 'm1-l${i + 1}',
              title: 'L${i + 1}',
              isPractice: false,
              xp: 15,
              exercises: [
                const Exercise(
                  kind: ExerciseKind.theoryTask,
                  task: Task(
                    type: TaskType.fill,
                    answers: ['ok'],
                    explanation: 'e',
                  ),
                ),
              ],
            ),
        ],
      ),
      const CourseModule(
        number: 2,
        title: 'M2',
        lessons: [
          Lesson(
            id: 'm2-l1',
            title: 'L',
            isPractice: false,
            xp: 15,
            exercises: [],
          ),
        ],
      ),
    ],
  );
  return course;
}

void main() {
  test('xp выдаётся один раз за упражнение', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    await p.recordExercise('m1-l1', 0, true);
    expect(p.xp, 4);
    await p.recordExercise('m1-l1', 0, true);
    expect(p.xp, 4, reason: 'второй раз за правильный ответ XP не даётся');
    await p.recordExercise('m1-l1', 0, false);
    expect(p.xp, 4);
  });

  test('ошибочный ответ не даёт XP, но двигает прогресс', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    await p.recordExercise('m1-l1', 0, false);
    expect(p.xp, 0);
    final lp = p.lessonProgressOf('m1-l1')!;
    expect(lp.last, 1);
  });

  test('завершение урока начисляет XP один раз', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    await p.completeLesson('m1-l1', 15, 5);
    expect(p.isLessonComplete('m1-l1'), true);
    await p.completeLesson('m1-l1', 15, 5);
    expect(p.xp, 15);
    expect(p.coins, 5);
  });

  test('уровни считаются по кривой', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    expect(p.level(), 1);
    await p.completeLesson('m1-l1', 100, 5);
    expect(p.level(), 2);
  });

  test('проценты и завершённые модули', () async {
    final course = _course();
    final p = ProgressService(MemoryStorage());
    await p.load();
    expect(p.coursePercent(course), 0);
    expect(p.completedModules(course), 0);
    await p.completeLesson('m1-l1', 15, 5);
    expect(p.coursePercent(course), closeTo(1 / 3, 0.001));
    await p.completeLesson('m1-l2', 15, 5);
    expect(p.isModuleComplete(course.modules.first), true);
    expect(p.completedModules(course), 1);
  });

  test('стрик растёт день за днём и сбрасывается при пропуске', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    await p.touchStreak(DateTime(2026, 1, 1));
    expect(p.streak, 1);
    await p.touchStreak(DateTime(2026, 1, 2));
    expect(p.streak, 2);
    await p.touchStreak(DateTime(2026, 1, 2));
    expect(p.streak, 2, reason: 'в тот же день стрик не растёт');
    await p.touchStreak(DateTime(2026, 1, 5));
    expect(p.streak, 1, reason: 'пропуск больше суток — стрик сброшен');
    expect(p.bestStreak, 2);
  });

  test('сброс курса очищает данные', () async {
    final p = ProgressService(MemoryStorage());
    await p.load();
    await p.setUserName('Тест');
    await p.recordExercise('m1-l1', 0, true);
    await p.completeLesson('m1-l1', 15, 5);
    await p.resetCourse();
    expect(p.userName, isNotEmpty);
    expect(p.xp, 0);
    expect(p.coins, 0);
    expect(p.lessons, isEmpty);
  });

  test('прогресс сохраняется в storage', () async {
    final storage = MemoryStorage();
    final p = ProgressService(storage);
    await p.load();
    await p.setUserName('Иван');
    await p.recordExercise('m1-l1', 0, true);
    await p.completeLesson('m1-l1', 15, 5);

    final p2 = ProgressService(storage);
    await p2.load();
    expect(p2.userName, 'Иван');
    expect(p2.xp, 19);
    expect(p2.isLessonComplete('m1-l1'), true);
  });

  test('достижения разблокируются', () async {
    final course = _course(lessons: 1);
    final p = ProgressService(MemoryStorage());
    await p.load();
    final none = p.achievements(course).where((a) => a.unlocked);
    expect(none, isEmpty);
    await p.recordExercise('m1-l1', 0, true);
    await p.completeLesson('m1-l1', 15, 5);
    await p.touchStreak(DateTime(2026, 1, 1));
    final some = p.achievements(course).where((a) => a.unlocked);
    expect(some.length, greaterThanOrEqualTo(2));
  });
}