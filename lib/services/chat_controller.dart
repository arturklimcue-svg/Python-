import 'dart:async';
import 'dart:io';

import 'opencode_server.dart';

/// Сообщение в чате. Текст мутируемый: ответ модели стримится по частям.
class ChatMessage {
  final String role;
  String text;
  final DateTime timestamp;

  ChatMessage({required this.role, required this.text, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

/// Режим соединения с AI-сервером.
enum AiServerStatus { checking, online, offline }

/// Системный промпт наставника: модель отвечает текстом и не трогает
/// инструменты, доступные ей на serve-сервере.
const String kTutorSystemPrompt =
    'Ты — доброжелательный наставник по Python для детей (курс «КодиК»). '
    'Отвечай по-русски, коротко и понятно. Никогда не используй инструменты '
    'и не выполняй команды — только текст. Не давай готовое решение задачи '
    'целиком: лучше подведи к нему вопросами и подсказками. Если дан код '
    'ученика и его ошибка — объясни, что не так, и подскажи, как исправить. '
    'Примеры кода оформляй тройными обратными кавычками python.';

/// Проверка статуса соединения с сервером.
Future<AiServerStatus> checkServer(String baseUrl) async {
  final ok = await OpenCodeServer(baseUrl: baseUrl).health();
  return ok ? AiServerStatus.online : AiServerStatus.offline;
}

/// Чистая машина состояний диалога: превращает SSE-события в сообщения.
/// Не зависима от сети — удобно тестировать.
class ChatTranscript {
  ChatTranscript();

  final List<ChatMessage> messages = [];
  bool _awaiting = false;
  String _draft = '';
  String? _lastUserMessageId;

  /// Вызывается при любом изменении (новое сообщение, прирост текста).
  void Function()? onUpdate;

  bool get isAwaiting => _awaiting;
  String get draftText => _draft;

  ChatMessage get _assistantBubble => messages.last;

  void userMessage(String text) {
    messages.add(ChatMessage(role: 'user', text: text));
    onUpdate?.call();
  }

  /// Ответ модели пошёл.
  void begin() {
    _awaiting = true;
    _draft = '';
    messages.add(ChatMessage(role: 'ai', text: ''));
    onUpdate?.call();
  }

  /// Ответ завершился.
  void finish() {
    if (!_awaiting) return;
    _awaiting = false;
    onUpdate?.call();
  }

  /// Ответ провалился: ставим понятное сообщение в пузырь ответа.
  void fail(String error) {
    if (!_awaiting) return;
    _awaiting = false;
    if (error.isNotEmpty && _assistantBubble.text.isEmpty) {
      _assistantBubble.text = error;
    }
    onUpdate?.call();
  }

  void appendText(String text) {
    if (!_awaiting) return;
    _draft = text;
    _assistantBubble.text = text;
    onUpdate?.call();
  }

  void setUserMessageId(String? id) {
    _lastUserMessageId = id;
  }

  /// Обрабатывает событие сервера.
  void handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message.updated':
        final info = (event['properties'] as Map<String, dynamic>?)?['info'];
        if (info is Map<String, dynamic>) {
          final role = info['role'];
          final id = info['id'];
          if (role == 'user' && id is String) {
            _lastUserMessageId = id;
          }
          if (role == 'assistant' && _awaiting) {
            final error = info['error'];
            if (error != null) {
              fail(describeEventError(error));
            }
          }
        }
        break;
      case 'message.part.updated':
        final part = (event['properties'] as Map<String, dynamic>?)?['part'];
        if (part is Map<String, dynamic> && part['type'] == 'text' && _awaiting) {
          final msgId = part['messageID'];
          if (_lastUserMessageId != null &&
              msgId is String &&
              msgId != _lastUserMessageId) {
            final text = part['text'];
            if (text is String) appendText(text);
          }
        }
        break;
      case 'session.idle':
        finish();
        break;
      case 'session.status':
        final status =
            (event['properties'] as Map<String, dynamic>?)?['status'];
        if (status is Map<String, dynamic> && status['type'] == 'idle') {
          finish();
        }
        break;
      case 'session.error':
        final err = (event['properties'] as Map<String, dynamic>?)?['error'];
        fail(
          err != null
              ? describeEventError(err)
              : 'Ошибка на стороне AI-сервера.',
        );
        break;
    }
  }

  /// Форматирует ошибку сервера в понятное сообщение и добавляет подсказку
  /// по частым причинам.
  static String describeEventError(dynamic error) {
    final map = error is Map<String, dynamic>
        ? error
        : <String, dynamic>{};
    final data = map['data'] is Map<String, dynamic>
        ? map['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final status = data['statusCode'] ?? map['statusCode'];
    final message = data['message'] ?? map['message'] ?? map['name'];

    final head = status != null
        ? 'Ошибка AI-сервера, код $status'
        : 'Ошибка AI-сервера';
    final detail = message is String && message.trim().isNotEmpty
        ? ': ${message.trim()}'
        : '';

    final lower = message is String ? message.toLowerCase() : '';
    var hint = '';
    if (lower.contains('free tier') ||
        (lower.contains('free') && lower.contains('opencode'))) {
      hint =
          '\nБесплатный тариф opencode работает только внутри терминала. '
          'Подключи ключ провайдера в Termux: opencode auth login';
    } else if (lower.contains('agent') || lower.contains('not found')) {
      hint =
          '\nПохоже, агент не найден. Убедись, что агент "tutor" задан в '
          'конфиге opencode (docs/termux-server.md) или укажи другого агента '
          'в настройках приложения.';
    } else if (status == 401 || status == 403) {
      hint =
          '\nДля запросов к модели нужны права провайдера. Проверь доступ: '
          'opencode auth login';
    }
    return '$head$detail$hint';
  }
}

/// Обвязка диалога сетью: сессия, SSE-подписка, таймаут.
class ChatController {
  ChatController({required OpenCodeServer server})
    : _server = server,
      transcript = ChatTranscript();

  final OpenCodeServer _server;
  final ChatTranscript transcript;

  String get baseUrl => _server.baseUrl;

  bool _listening = false;
  String? _sessionId;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timeout;
  bool _agentsResolved = false;
  String? _agentNote;

  bool get isAwaiting => transcript.isAwaiting;

  /// Заметка о том, что агент из настроек не найден и использован другой.
  String? get agentNote => _agentNote;

  /// Выбирает агента: настроенный, если он есть на сервере; иначе `general`;
  /// иначе первый доступный; иначе оставляет настроенного.
  static String chooseFallbackAgent(
    String configured,
    List<String> available,
  ) {
    if (available.contains(configured)) return configured;
    if (available.contains('general')) return 'general';
    return available.isNotEmpty ? available.first : configured;
  }

  /// Проверяет, что агент существует на сервере; при отсутствии переключается
  /// на доступный. Вызывать можно без ожидания, безопасно.
  Future<void> resolveAgents() => _ensureAgent();

  Future<String> _ensureAgent() async {
    if (_agentsResolved) return _server.agent;
    _agentsResolved = true;
    final configured = _server.agent;
    final chosen = chooseFallbackAgent(configured, await _server.availableAgents());
    if (chosen != configured) {
      _agentNote = 'Агент «$configured» не найден на сервере, '
          'использую «$chosen».';
      _server.agent = chosen;
    }
    return chosen;
  }

  void Function()? get onUpdate => transcript.onUpdate;
  set onUpdate(void Function()? f) => transcript.onUpdate = f;

  Future<void>? _starting;

  /// Начинает слушать SSE-поток и создаёт сессию. Повторные вызовы во время
  /// запуска ждут тот же старт (защита от гонки с автоотправкой первого
  /// сообщения из урока/песочницы).
  Future<void> start() {
    final inFlight = _starting;
    if (inFlight != null) return inFlight;
    final done = _doStart().whenComplete(() => _starting = null);
    _starting = done;
    return done;
  }

  Future<void> _doStart() async {
    if (_listening) return;
    _listening = true;
    try {
      _sessionId ??= await _server.createSession();
    } catch (_) {
      _sessionId = null;
    }
    _sub = _server.eventStream().listen(
      transcript.handleEvent,
      onError: (_) => _onStreamClosed(),
      onDone: _onStreamClosed,
    );
  }

  void _onStreamClosed() {
    _listening = false;
    transcript.fail(
      'Соединение с AI-сервером прервано. '
      'Проверь, что opencode serve ещё запущен.',
    );
  }

  /// Отправляет сообщение ученика.
  Future<void> send(String text) async {
    if (transcript.isAwaiting) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    transcript.userMessage(trimmed);
    transcript.begin();
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 60), () {
      transcript.fail(
        'Сервер долго не отвечает. Попробуй ещё раз или проверь соединение.',
      );
    });

    try {
      if (_sessionId == null) {
        await start();
      }
      if (_sessionId == null) {
        throw OpenCodeException('Сервер не создал сессию');
      }
      await _ensureAgent();
      transcript.setUserMessageId(null);
      await _server.sendAsync(_sessionId!, '$kTutorSystemPrompt\n\n$trimmed');
    } catch (e) {
      _timeout?.cancel();
      transcript.fail(describeSendError(e));
    }
  }

  void cancelResponse() {
    final sessionId = _sessionId;
    if (sessionId != null) {
      _server.abort(sessionId);
    }
    _timeout?.cancel();
    transcript.finish();
  }

  static String describeSendError(Object e) {
    if (e is OpenCodeException) {
      if (e.message.startsWith('Сервер отверг сообщение')) {
        return 'AI-сервер отверг сообщение:\n${e.message}';
      }
      if (e.message.startsWith('Сервер недоступен')) {
        return 'AI-сервер недоступен. Проверь, что opencode serve запущен.';
      }
      return 'Не удалось связаться с AI-сервером. Убедись, что в Termux '
          'запущен сервер: opencode serve.';
    }
    if (e is SocketException || e is HttpException) {
      return 'Не удалось связаться с AI-сервером. '
          'Убедись, что в Termux запущен сервер: opencode serve.';
    }
    return 'Ошибка отправки: $e';
  }

  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    _server.dispose();
  }
}