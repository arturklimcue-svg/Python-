import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/progress_service.dart';
import '../theme.dart';
import 'certificate_screen.dart';

class ProfileTab extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const ProfileTab({super.key, required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final percent = progress.coursePercent(course);
        final certUnlocked = percent >= 1.0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Профиль',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        _initial(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progress.userName.isEmpty ? 'Ученик' : progress.userName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Уровень ${progress.level()} · ${progress.xp} XP',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Изменить имя',
                      onPressed: () => _editName(context),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.streak, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Текущий стрик',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                          Text(
                            '${progress.streak} дней подряд',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Лучший: ${progress.bestStreak}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Сертификат о прохождении курса',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      certUnlocked
                          ? 'Курс пройден на 100% — сертификат доступен!'
                          : 'Сертификат откроется при 100% курса '
                              '(${(percent * 100).round()}% сейчас).',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: certUnlocked
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CertificateScreen(
                                    progress: progress,
                                  ),
                                ),
                              )
                          : null,
                      icon: Icon(certUnlocked ? Icons.workspace_premium : Icons.lock),
                      label: Text(
                          certUnlocked ? 'Посмотреть сертификат' : 'Заблокирован'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'О приложении',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'КодиК — интерактивный курс Python-разработчика.\n'
                      'Учись 15 минут в день, зарабатывай XP и забери '
                      'сертификат по окончании курса.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _confirmReset(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Сбросить прогресс курса'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _initial() {
    final n = progress.userName.trim();
    if (n.isEmpty) return 'К';
    return n.characters.first.toUpperCase();
  }

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(text: progress.userName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Твоё имя'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Введи имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await progress.setUserName(name);
    }
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