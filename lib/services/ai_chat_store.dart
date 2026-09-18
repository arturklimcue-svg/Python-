import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_controller.dart';

/// Сохранённый диалог с AI-ассистентом. Вместе с сообщениями хранит сессию
/// opencode, чтобы продолжить разговор, а не плодить новые сессии на сервере.
class SavedChat {
  const SavedChat({
    required this.id,
    required this.title,
    required this.agent,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.messages = const [],
  });

  final String id;

  /// Сессия opencode на сервере (может отсутствовать, если сервер не создал её
  /// из-за недоступности).
  final String? sessionId;
  final String title;
  final String agent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// Короткое название чата: первый вопрос пользователя или дата.
  static String makeTitle(List<ChatMessage> messages) {
    final users = messages.where((m) => m.role == 'user').toList();
    final first = users.isEmpty ? '' : users.first.text.trim();
    if (first.isNotEmpty) {
      return first.length > 40 ? '${first.substring(0, 40)}…' : first;
    }
    return 'Чат от ${formatDate(DateTime.now())}';
  }

  static String formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'title': title,
    'agent': agent,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  static SavedChat fromJson(Map<String, dynamic> json) {
    final raw = (json['messages'] as List?) ?? const [];
    return SavedChat(
      id: json['id'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      title: (json['title'] as String?) ?? 'Чат',
      agent: (json['agent'] as String?) ?? 'tutor',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
      messages: raw.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }
}

/// Хранилище сохранённых диалогов. Как `AiSettings` — SharedPreferences,
/// все операции безопасны и не ломают приложение при сбое.
class AiChatStore {
  AiChatStore._();

  static const String _key = 'ai_chats_v1';

  /// Все сохранённые чаты, самые свежие — первыми.
  static Future<List<SavedChat>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final chats = decoded
          .whereType<Map>()
          .map((e) => SavedChat.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return chats;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<SavedChat> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(chats.map((c) => c.toJson()).toList()),
      );
    } catch (_) {
      // Не сохранилось — чаты останутся в памяти текущей сессии.
    }
  }

  static String newId() {
    final rnd = Random().nextInt(1 << 30);
    return 'chat-${DateTime.now().microsecondsSinceEpoch}-$rnd';
  }
}