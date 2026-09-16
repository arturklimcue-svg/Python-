import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/progress_service.dart';
import '../theme.dart';

class ProgressTab extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const ProgressTab({super.key, required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final level = progress.level();
        final levelFrac = progress.levelProgress();
        final lessonsDone = progress.totalCompletedLessons(course);
        final accuracy = _accuracy();
        final achievements = progress.achievements(course);
        final unlocked = achievements.where((a) => a.unlocked).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Прогресс',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$level',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Текущий уровень',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: levelFrac.clamp(0.0, 1.0),
                                  minHeight: 10,
                                  backgroundColor: AppColors.background,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${progress.xp} XP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(icon: Icons.menu_book, value: '$lessonsDone', label: 'Уроков'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.monetization_on, value: '${progress.coins}', label: 'Монет'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.local_fire_department, value: '${progress.bestStreak}', label: 'Стрик'),
                const SizedBox(width: 10),
                _StatCard(icon: Icons.check_circle, value: '$accuracy%', label: 'Точность'),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Text(
                  'Достижения',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '$unlocked из ${achievements.length}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                for (final a in achievements) _AchievementCard(achievement: a),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Модули',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final m in course.modules) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        '${m.number.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.title,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (m.lessonCount == 0
                                        ? 0
                                        : m.lessons
                                                .where((l) =>
                                                    progress.isLessonComplete(
                                                        l.id))
                                                .length /
                                            m.lessonCount)
                                    .toDouble(),
                                minHeight: 6,
                                backgroundColor: AppColors.background,
                                color: progress.isModuleComplete(m)
                                    ? AppColors.success
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${m.lessons.where((l) => progress.isLessonComplete(l.id)).length}/${m.lessonCount}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  int _accuracy() {
    final doneTotal = progress.lessons.values.fold<int>(0, (s, p) => s + p.right);
    final attemptedTotal = progress.lessons.values.fold<int>(0, (s, p) => s + p.awarded.length);
    if (attemptedTotal == 0) return 0;
    return (doneTotal / attemptedTotal * 100).round();
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;

  const _AchievementCard({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final on = achievement.unlocked;
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? null : AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(achievement.icon,
                style: TextStyle(fontSize: 24, color: on ? null : Colors.grey)),
            const SizedBox(height: 6),
            Text(
              achievement.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: on ? null : AppColors.textMuted,
              ),
            ),
            Text(
              achievement.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}