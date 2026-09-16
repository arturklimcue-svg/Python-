import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'lesson_list_screen.dart';

class CourseTab extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const CourseTab({super.key, required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _GreetingHeader(progress: progress),
              const SizedBox(height: 16),
              _CourseOverview(course: course, progress: progress),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Text(
                    'Модули курса',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${progress.completedModules(course)} из '
                    '${course.moduleCount}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < course.modules.length; i++) ...[
                _ModuleCard(
                  module: course.modules[i],
                  index: i,
                  course: course,
                  progress: progress,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final ProgressService progress;

  const _GreetingHeader({required this.progress});

  @override
  Widget build(BuildContext context) {
    final name =
        progress.userName.isEmpty ? 'друг' : progress.userName.split(' ').first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Привет, $name!',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Уровень ${progress.level()} · Продолжай учиться',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        _StatChip(icon: Icons.stars, label: '${progress.xp} XP'),
        const SizedBox(width: 8),
        _StatChip(icon: Icons.monetization_on, label: '${progress.coins}'),
        const SizedBox(width: 8),
        _StatChip(
          icon: Icons.local_fire_department,
          label: '${progress.streak}',
          color: AppColors.streak,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _StatChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AppColors.gold),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CourseOverview extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const _CourseOverview({required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    final percent = progress.coursePercent(course);
    final completed = progress.completedModules(course);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.code, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Python-разработчик',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Курс завершён на ${(percent * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$completed из ${course.moduleCount} модулей завершено',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                  ),
                  onPressed: () => _continueLearning(context),
                  child: const Text('Продолжить обучение'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Сбросить прогресс курса',
                onPressed: () => _confirmReset(context),
                icon: const Icon(Icons.refresh, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _continueLearning(BuildContext context) {
    for (final m in course.modules) {
      if (progress.isModuleComplete(m)) continue;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            LessonListScreen(module: m, progress: progress),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Курс полностью пройден! Получи сертификат.')),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить прогресс курса?'),
        content: const Text(
            'Весь прогресс, монеты и достижения будут удалены. Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await progress.resetCourse();
    }
  }
}

class _ModuleCard extends StatelessWidget {
  final CourseModule module;
  final int index;
  final Course course;
  final ProgressService progress;

  const _ModuleCard({
    required this.module,
    required this.index,
    required this.course,
    required this.progress,
  });

  bool get _unlocked {
    if (index == 0) return true;
    return progress.isModuleComplete(course.modules[index - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final complete = progress.isModuleComplete(module);
    final done = module.lessons
        .where((l) => progress.isLessonComplete(l.id))
        .length;
    final percent = module.lessonCount == 0 ? 0.0 : done / module.lessonCount;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!_unlocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Сначала заверши модуль «${course.modules[index - 1].title}»',
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LessonListScreen(module: module, progress: progress),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _unlocked
                      ? (complete
                          ? AppColors.success
                          : AppColors.primary)
                      : AppColors.textMuted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(
                    _unlocked
                        ? (complete ? Icons.check : _iconFor(index))
                        : Icons.lock,
                    color: _unlocked ? Colors.white : AppColors.textMuted,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Модуль ${module.number.toString().padLeft(2, '0')} · '
                      '${module.title}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_unlocked)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 6,
                          backgroundColor: AppColors.background,
                          color: complete
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      _unlocked
                          ? complete
                              ? 'Модуль завершён'
                              : '$done из ${module.lessonCount} уроков · '
                                  '${(percent * 100).round()}%'
                          : 'Заблокирован',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: _unlocked ? AppColors.textMuted : AppColors.textMuted.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(int i) {
    const icons = [
      Icons.rocket_launch,
      Icons.route,
      Icons.view_list,
      Icons.functions,
      Icons.extension,
      Icons.api,
      Icons.data_object,
      Icons.category,
      Icons.key,
    ];
    return icons[i % icons.length];
  }
}