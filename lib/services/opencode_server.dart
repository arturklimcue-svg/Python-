import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Клиент HTTP-сервера opencode (`opencode serve`).
///
/// Протокол:
/// * `GET /global/health` — проверка, что сервер жив;
/// * `POST /session` — создание сессии (диалога);
/// * `POST /session/:id/prompt_async` — отправить сообщение (не ждать ответа);
/// * `GET /event` — поток серверных событий (SSE): текст ответа приходит
///   частями в `message.part.updated`, завершение — `session.idle`.
class OpenCodeServer {
  OpenCodeServer({required this.baseUrl, String agent = 'tutor'})
    : agent = agent,
      _client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);

  final String baseUrl;
  String agent;
  final HttpClient _client;

  static const String defaultBaseUrl = 'http://127.0.0.1:4096';

  /// Сервер отвечает на health-запрос.
  Future<bool> health() async {
    try {
      final req = await _client
          .getUrl(Uri.parse('$baseUrl/global/health'))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return false;
      try {
        final map = jsonDecode(body) as Map<String, dynamic>;
        return map['healthy'] == true;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Создаёт сессию и возвращает её id. Один диалог = одна сессия.
  Future<String> createSession() async {
    final req = await _client
        .postUrl(Uri.parse('$baseUrl/session'))
        .timeout(const Duration(seconds: 8));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'title': 'КодиК AI'}));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw OpenCodeException('Не удалось создать сессию (${res.statusCode})');
    }
    final map = jsonDecode(body) as Map<String, dynamic>;
    final id = map['id'];
    if (id is! String) {
      throw OpenCodeException('Сервер вернул некорректный ответ');
    }
    return id;
  }

  /// Отправляет текст в сессию без ожидания ответа (ответ придёт по SSE).
  Future<void> sendAsync(String sessionId, String text) async {
    final req = await _client
        .postUrl(Uri.parse('$baseUrl/session/$sessionId/prompt_async'))
        .timeout(const Duration(seconds: 8));
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'agent': agent,
        'parts': [
          {'type': 'text', 'text': text},
        ],
      }),
    );
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 && res.statusCode != 204) {
      String body = '';
      try {
        body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      throw OpenCodeException(
        'Сервер отверг сообщение (${res.statusCode})'
        '${body.trim().isNotEmpty ? ': ${body.trim()}' : ''}',
      );
    }
    await res.drain<void>();
  }

  /// Прерывает текущий ответ модели.
  Future<void> abort(String sessionId) async {
    try {
      final req = await _client
          .postUrl(Uri.parse('$baseUrl/session/$sessionId/abort'))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
    } catch (_) {
      // Не критично: сервер сам завершит ответ.
    }
  }

  /// Имена агентов, доступных на сервере. Пустой список — сервер недоступен
  /// или формат ответа не похож на ожидаемый.
  Future<List<String>> availableAgents() async {
    try {
      final req = await _client
          .getUrl(Uri.parse('$baseUrl/agent'))
          .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e is Map<String, dynamic> ? e['name'] : null)
          .whereType<String>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Поток событий сервера (SSE). Ошибки сокета приходят как done/error.
  Stream<Map<String, dynamic>> eventStream() async* {
    final req = await _client
        .getUrl(Uri.parse('$baseUrl/event'))
        .timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw OpenCodeException('Сервер недоступен (${res.statusCode})');
    }
    await for (final event
        in _sseLines(res.transform(utf8.decoder).transform(const LineSplitter()))) {
      if (event.isNotEmpty) yield event;
    }
  }

  void dispose() {
    try {
      _client.close(force: true);
    } catch (_) {}
  }
}

/// Разбирает строки SSE: оставляет только содержимое `data:`.
Stream<Map<String, dynamic>> _sseLines(Stream<String> lines) async* {
  await for (final line in lines) {
    final s = line.trimRight();
    if (!s.startsWith('data:')) continue;
    final payload = s.substring(5).trim();
    if (payload.isEmpty) continue;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) yield decoded;
    } catch (_) {
      // Пропускаем повреждённое событие, поток не рвём.
    }
  }
}

/// Чистая функция для тестов: весь буфер SSE -> список событий.
List<Map<String, dynamic>> parseSseBuffer(String buffer) {
  final events = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(buffer)) {
    final s = line.trimRight();
    if (!s.startsWith('data:')) continue;
    final payload = s.substring(5).trim();
    if (payload.isEmpty) continue;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        events.add(decoded);
      }
    } catch (_) {}
  }
  return events;
}

class OpenCodeException implements Exception {
  final String message;
  OpenCodeException(this.message);

  @override
  String toString() => message;
}