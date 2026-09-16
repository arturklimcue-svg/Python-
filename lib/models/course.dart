import 'exercise.dart';

class Lesson {
  final String id;
  final String title;
  final bool isPractice;
  final int xp;
  final List<Exercise> exercises;

  const Lesson({
    required this.id,
    required this.title,
    required this.isPractice,
    required this.xp,
    required this.exercises,
  });

  int get exerciseCount => exercises.length;

  factory Lesson.fromJson(String moduleId, int moduleNumber,
      Map<String, dynamic> j, int index) {
    final id = 'm$moduleNumber-l${index + 1}';
    return Lesson(
      id: id,
      title: (j['title'] as String?) ?? 'Урок',
      isPractice: j['type'] == 'practice',
      xp: (j['xp'] as num?)?.toInt() ?? 15,
      exercises: ((j['exercises'] as List<dynamic>?) ?? const [])
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CourseModule {
  final int number;
  final String title;
  final List<Lesson> lessons;

  const CourseModule({
    required this.number,
    required this.title,
    required this.lessons,
  });

  int get lessonCount => lessons.length;

  factory CourseModule.fromJson(Map<String, dynamic> j, int index) {
    final number = (j['number'] as num?)?.toInt() ?? (index + 1);
    final lessonsJson = (j['lessons'] as List<dynamic>?) ?? const [];
    return CourseModule(
      number: number,
      title: (j['title'] as String?) ?? 'Модуль $number',
      lessons: lessonsJson.asMap().entries.map((en) {
        final i = en.key;
        return Lesson.fromJson(
          'm$number', number, en.value as Map<String, dynamic>, i);
      }).toList(),
    );
  }
}

class Course {
  final String title;
  final List<CourseModule> modules;

  const Course({required this.title, required this.modules});

  int get moduleCount => modules.length;

  int get totalLessons =>
      modules.fold(0, (sum, m) => sum + m.lessonCount);

  factory Course.fromJson(Map<String, dynamic> j) {
    final modulesJson = (j['modules'] as List<dynamic>?) ?? const [];
    return Course(
      title: (j['title'] as String?) ?? 'Python-разработчик',
      modules: modulesJson.asMap().entries.map((en) {
        return CourseModule.fromJson(
            en.value as Map<String, dynamic>, en.key);
      }).toList(),
    );
  }
}