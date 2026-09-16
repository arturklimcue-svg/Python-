import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'lesson_screen.dart';

class LessonListScreen extends StatelessWidget {
  final CourseModule module;
  final ProgressService progress;

  const LessonListScreen({
    super.key,
    required this.module,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final done = module.lessons
            .where((l) => progress.isLessonComplete(l.id))
            .length;
        final percent =
            module.lessonCount == 0 ? 0.0 : done / module.lessonCount;

        Lesson? next;
        for (final l in module.lessons) {
          if (!progress.isLessonComplete(l.id)) {
            next = l;
            break;
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Модуль ${module.number} · ${module.title}'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$done из ${module.lessonCount} уроков пройдено',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 8,
                          backgroundColor: AppColors.background,
                          color: AppColors.primary,
                        ),
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LessonScreen(
                                lesson: next!,
                                progress: progress,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Продолжить: «${next.title}»'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < module.lessons.length; i++) ...[
                _LessonTile(
                  lesson: module.lessons[i],
                  index: i,
                  progress: progress,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  final int index;
  final ProgressService progress;

  const _LessonTile({
    required this.lesson,
    required this.index,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final complete = progress.isLessonComplete(lesson.id);
    final lp = progress.lessonProgressOf(lesson.id);
    final progressText = complete ? '✓ Пройден' : '${lp?.last ?? 0} из ${lesson.exerciseCount} упражнений';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LessonScreen(lesson: lesson, progress: progress),
          )).then((_) {
            // progress notified via ListenableBuilder
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: complete
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  complete ? Icons.check : Icons.menu_book_outlined,
                  color: complete ? AppColors.success : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}. ${lesson.title}',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (lesson.isPractice)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Практика',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$progressText · +${lesson.xp} XP',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}