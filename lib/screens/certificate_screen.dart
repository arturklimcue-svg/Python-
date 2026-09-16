import 'package:flutter/material.dart';

import '../services/certificate_service.dart';
import '../services/progress_service.dart';
import '../theme.dart';

class CertificateScreen extends StatefulWidget {
  final ProgressService progress;

  const CertificateScreen({super.key, required this.progress});

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  String get _name {
    final n = widget.progress.userName.trim();
    return n.isEmpty ? 'Ученик' : n;
  }

  String get _date {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сертификат')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RepaintBoundary(
            key: _boundaryKey,
            child: _CertificateCard(name: _name, date: _date),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _saveAndShare,
            icon: const Icon(Icons.save_alt),
            label: Text(_busy ? 'Подготовка…' : 'Сохранить и поделиться'),
          ),
          const SizedBox(height: 8),
          Text(
            'Скриншот сертификата сохранится во временную папку, '
            'откуда его можно отправить или сохранить.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndShare() async {
    setState(() => _busy = true);
    try {
      final png = await CertificateService.capturePng(_boundaryKey);
      final file = await CertificateService.saveToTemp(png, 'sertifikat.png');
      await CertificateService.share(
        file,
        'Мой сертификат о прохождении курса «Python-разработчик»',
      );
    } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось сохранить сертификат: $e')),
          );
        }
      } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CertificateCard extends StatelessWidget {
  final String name;
  final String date;

  const _CertificateCard({required this.name, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gold, AppColors.primary, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            const Text(
              'СЕРТИФИКАТ',
              style: TextStyle(
                fontSize: 16,
                letterSpacing: 6,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.workspace_premium, color: AppColors.gold, size: 46),
            const SizedBox(height: 12),
            const Text(
              'настоящим подтверждается, что',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'успешно освоил(а) курс',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              '«Python-разработчик»',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Text(
                        'Дата',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'КодиК',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Платформа',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}