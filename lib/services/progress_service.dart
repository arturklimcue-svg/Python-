import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course.dart';
import 'storage_service.dart';

class LessonProgress {
  final int last;
  final int right;
  final List<int> awarded;
  final bool complete;

  const LessonProgress({
    required this.last,
    required this.right,
    required this.awarded,
    required this.complete,
  });

  factory LessonProgress.empty() =>
      const LessonProgress(last: 0, right: 0, awarded: [], complete: false);

  LessonProgress copyWith({
    int? last,
    int? right,
    List<int>? awarded,
    bool? complete,
  }) {
    return LessonProgress(
      last: last ?? this.last,
      right: right ?? this.right,
      awarded: awarded ?? this.awarded,
      complete: complete ?? this.complete,
    );
  }

  factory LessonProgress.fromJson(Map<String, dynamic> j) => LessonProgress(
        last: (j['last'] as num?)?.toInt() ?? 0,
        right: (j['right'] as num?)?.toInt() ?? 0,
        awarded: ((j['awarded'] as List<dynamic>?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        complete: (j['complete'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'last': last, 'right': right, 'awarded': awarded, 'complete': complete};
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });
}

class ProgressService extends ChangeNotifier {
  static const _key = 'kodik_progress_v1';

  final Storage _storage;

  String userName = '';
  int xp = 0;
  int coins = 0;
  int streak = 0;
  int bestStreak = 0;
  DateTime? lastStreakDate;

  final Map<String, LessonProgress> _lessons = {};

  bool _loaded = false;

  ProgressService(this._storage);

  bool get isLoaded => _loaded;

  LessonProgress? lessonProgressOf(String lessonId) => _lessons[lessonId];

  Map<String, LessonProgress> get lessons => Map.unmodifiable(_lessons);

  Future<void> load() async {
    final raw = await _storage.getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      userName = (j['userName'] as String?) ?? '';
      xp = (j['xp'] as num?)?.toInt() ?? 0;
      coins = (j['coins'] as num?)?.toInt() ?? 0;
      streak = (j['streak'] as num?)?.toInt() ?? 0;
      bestStreak = (j['bestStreak'] as num?)?.toInt() ?? 0;
      final last = j['lastStreakDate'];
      lastStreakDate = last == null ? null : DateTime.tryParse(last.toString());
      final l = j['lessons'];
      if (l is Map<String, dynamic>) {
        l.forEach((k, v) {
          _lessons[k] = LessonProgress.fromJson(v as Map<String, dynamic>);
        });
      }
    }
    _loaded = true;
  }

  Future<void> save() async {
    final j = {
      'userName': userName,
      'xp': xp,
      'coins': coins,
      'streak': streak,
      'bestStreak': bestStreak,
      'lastStreakDate': _dateKey(lastStreakDate),
      'lessons': {
        for (final e in _lessons.entries) e.key: e.value.toJson(),
      },
    };
    await _storage.setString(_key, jsonEncode(j));
  }

  Future<void> setUserName(String name) async {
    userName = name.trim();
    notifyListeners();
    await save();
  }

  Future<void> touchStreak(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (lastStreakDate == null) {
      streak = 1;
    } else {
      final last = DateTime(
          lastStreakDate!.year, lastStreakDate!.month, lastStreakDate!.day);
      final diff = today.difference(last).inDays;
      if (diff > 1) {
        streak = 1;
      } else if (diff == 1) {
        streak += 1;
      }
      // diff == 0: same day, streak stays
    }
    if (streak > bestStreak) bestStreak = streak;
    lastStreakDate = today;
    notifyListeners();
    return save();
  }

  Future<void> recordExercise(
      String lessonId, int exerciseIndex, bool isCorrect) async {
    final p = _lessons[lessonId] ?? LessonProgress.empty();
    final awarded = List<int>.from(p.awarded);
    var newXp = xp;
    var newCoins = coins;
    var newRight = p.right;
    if (isCorrect && !awarded.contains(exerciseIndex)) {
      awarded.add(exerciseIndex);
      newRight += 1;
      newXp += 4;
      newCoins += 1;
    }
    final last = p.last < exerciseIndex + 1 ? exerciseIndex + 1 : p.last;
    _lessons[lessonId] = p.copyWith(
        last: last, right: newRight, awarded: awarded);
    xp = newXp;
    coins = newCoins;
    notifyListeners();
    await save();
  }

  Future<void> completeLesson(String lessonId, int xpBonus, int coinBonus) async {
    final p = _lessons[lessonId] ?? LessonProgress.empty();
    if (!p.complete) {
      _lessons[lessonId] = p.copyWith(complete: true);
      xp += xpBonus;
      coins += coinBonus;
      notifyListeners();
      await save();
    }
  }

  bool isLessonComplete(String lessonId) =>
      _lessons[lessonId]?.complete ?? false;

  bool isModuleComplete(CourseModule m) =>
      m.lessons.every((l) => isLessonComplete(l.id));

  int totalCompletedLessons(Course course) {
    var n = 0;
    for (final m in course.modules) {
      for (final l in m.lessons) {
        if (isLessonComplete(l.id)) n++;
      }
    }
    return n;
  }

  int completedModules(Course course) =>
      course.modules.where(isModuleComplete).length;

  double coursePercent(Course course) {
    final total = course.totalLessons;
    if (total == 0) return 0;
    return totalCompletedLessons(course) / total;
  }

  int totalRightAnswers() {
    var n = 0;
    for (final p in _lessons.values) {
      n += p.right;
    }
    return n;
  }

  int level() {
    var l = 1;
    while (xp >= _needFor(l)) {
      l++;
    }
    return l;
  }

  double levelProgress() {
    final l = level();
    final prev = _needFor(l - 1);
    final next = _needFor(l);
    return (xp - prev) / (next - prev);
  }

  static int _needFor(int level) {
    if (level <= 0) return 0;
    return 40 * level * level + 60 * level;
  }

  List<Achievement> achievements(Course course) {
    final completedLessons = totalCompletedLessons(course);
    final percent = coursePercent(course);
    final anyModule = course.modules.any(isModuleComplete);

    return [
      Achievement(
        id: 'first_right',
        title: 'Блестящий старт',
        description: 'Первый правильный ответ',
        icon: '⚡',
        unlocked: totalRightAnswers() >= 1,
      ),
      Achievement(
        id: 'first_lesson',
        title: 'Первый шаг',
        description: 'Пройди первый урок',
        icon: '👣',
        unlocked: completedLessons >= 1,
      ),
      Achievement(
        id: 'ten_lessons',
        title: 'Усердный ученик',
        description: '10 пройденных уроков',
        icon: '📚',
        unlocked: completedLessons >= 10,
      ),
      Achievement(
        id: 'module_done',
        title: 'Покоритель модулей',
        description: 'Заверши целый модуль',
        icon: '🏁',
        unlocked: anyModule,
      ),
      Achievement(
        id: 'half_course',
        title: 'На полпути',
        description: 'Курс пройден на 50%',
        icon: '🚧',
        unlocked: percent >= 0.5,
      ),
      Achievement(
        id: 'full_course',
        title: 'Финальный аккорд',
        description: 'Курс пройден на 100%',
        icon: '🏆',
        unlocked: percent >= 1.0,
      ),
      Achievement(
        id: 'streak3',
        title: 'Огонёк',
        description: 'Стрик 3 дня подряд',
        icon: '🔥',
        unlocked: bestStreak >= 3,
      ),
      Achievement(
        id: 'streak7',
        title: 'Неугасимый',
        description: 'Стрик 7 дней подряд',
        icon: '🌋',
        unlocked: bestStreak >= 7,
      ),
      Achievement(
        id: 'coins100',
        title: 'Монетный двор',
        description: 'Накопи 100 монет',
        icon: '🪙',
        unlocked: coins >= 100,
      ),
    ];
  }

  Future<void> resetCourse() async {
    _lessons.clear();
    xp = 0;
    coins = 0;
    streak = 0;
    bestStreak = 0;
    lastStreakDate = null;
    notifyListeners();
    await save();
  }

  static String _dateKey(DateTime? d) {
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
