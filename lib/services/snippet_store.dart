import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Сохранённый набросок из песочницы: имя и код, чтобы вернуться к нему
/// в следующий раз.
class SavedSnippet {
  const SavedSnippet({
    required this.id,
    required this.title,
    required this.code,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String code;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Автоматическое название: первая непустая строка кода (без комментариев)
  /// или «Набросок + время».
  static String autoTitle(String code) {
    for (final raw in code.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      return line.length > 40 ? '${line.substring(0, 40)}…' : line;
    }
    return 'Набросок ${formatDate(DateTime.now())}';
  }

  static String formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'code': code,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static SavedSnippet fromJson(Map<String, dynamic> json) => SavedSnippet(
    id: json['id'] as String? ?? '',
    title: (json['title'] as String?) ?? 'Набросок',
    code: (json['code'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
        DateTime.now(),
  );
}

/// Хранилище набросков песочницы. Как `AiChatStore` — SharedPreferences,
/// все операции безопасны и не ломают приложение при сбое.
class SnippetStore {
  SnippetStore._();

  static const String _key = 'snippets_v1';

  /// Все наброски, самые свежие — первыми.
  static Future<List<SavedSnippet>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final snippets = decoded
          .whereType<Map>()
          .map((e) => SavedSnippet.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      snippets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return snippets;
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedSnippet> snippets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(snippets.map((s) => s.toJson()).toList()),
      );
    } catch (_) {
      // Не сохранилось — наброски останутся в памяти текущей сессии.
    }
  }

  static String newId() {
    final rnd = Random().nextInt(1 << 30);
    return 'snippet-${DateTime.now().microsecondsSinceEpoch}-$rnd';
  }
}