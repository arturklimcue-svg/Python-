import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_chat_store.dart';
import '../services/ai_settings.dart';
import '../services/chat_controller.dart';
import '../services/opencode_server.dart';
import '../services/termux_launcher.dart';
import '../theme.dart';
import 'ai_chat_history_screen.dart';

class AiChatScreen extends StatefulWidget {
  final int currentModule;
  final String currentModuleTitle;

  /// Контекст из урока: задание, код ученика, вывод/ошибка. Если задан,
  /// будет отправлен серверу автоматически.
  final String? initialContext;

  const AiChatScreen({
    super.key,
    this.currentModule = 1,
    this.currentModuleTitle = 'Python',
    this.initialContext,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late AiSettings _settings;
  ChatController? _chat;
  AiServerStatus _status = AiServerStatus.checking;
  bool _autoSent = false;

  /// id текущего сохранённого чата (null — новый, ещё не сохранён).
  String? _chatId;

  /// Сессия opencode текущего чата на сервере.
  String? _sessionId;

  Timer? _persistTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _settings = await AiSettings.load();
    if (!mounted) return;
    _startChat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Создаёт контроллер чата и подключает сохранение/обновление.
  ChatController _createChat() {
    final chat = ChatController(
      server: OpenCodeServer(
        baseUrl: _settings.baseUrl,
        agent: _settings.agent,
      ),
      initialSessionId: _sessionId,
    );
    chat.onSessionCreated = (id) {
      _sessionId = id;
      _persistCurrentChat();
    };
    chat.onSessionReplaced = () {
      _sessionId = null;
    };
    chat.onUpdate = _handleUpdate;
    return chat;
  }

  void _handleUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
      _schedulePersist();
    }
  }

  void _startChat() {
    _chat?.dispose();
    final chat = _createChat();
    _chat = chat;
    setState(() => _status = AiServerStatus.checking);
    chat.resolveAgents();
    _refreshStatus();
    if (widget.initialContext != null && !_autoSent) {
      _autoSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          chat.send(_contextMessage(widget.initialContext!));
        }
      });
    }
  }

  /// Открывает сохранённый диалог: восстанавливаем сообщения и сессию,
  /// чтобы продолжить разговор на сервере (а не заводить новый).
  void _loadChat(SavedChat saved) {
    _autoSent = true;
    _chatId = saved.id;
    _sessionId = saved.sessionId;
    final chat = _createChat();
    chat.transcript.messages.addAll(
      saved.messages.map(
        (m) => ChatMessage(role: m.role, text: m.text, timestamp: m.timestamp),
      ),
    );
    _chat?.dispose();
    _chat = chat;
    setState(() => _status = AiServerStatus.checking);
    chat.resolveAgents();
    _refreshStatus();
  }

  void _newChat() {
    _chatId = null;
    _sessionId = null;
    _autoSent = false;
    _startChat();
  }

  /// Сохраняет текущий диалог в хранилище (создаёт или обновляет).
  Future<void> _persistCurrentChat() async {
    final chat = _chat;
    if (chat == null || chat.transcript.messages.isEmpty) return;
    final existing = await AiChatStore.load();
    final id = _chatId ?? AiChatStore.newId();
    _chatId = id;
    final prev = existing.where((c) => c.id == id).toList();
    final saved = SavedChat(
      id: id,
      sessionId: chat.sessionId,
      title: SavedChat.makeTitle(chat.transcript.messages),
      agent: _settings.agent,
      createdAt: prev.isEmpty ? DateTime.now() : prev.first.createdAt,
      updatedAt: DateTime.now(),
      messages: chat.transcript.messages
          .map(
            (m) =>
                ChatMessage(role: m.role, text: m.text, timestamp: m.timestamp),
          )
          .toList(),
    );
    final rest = existing.where((c) => c.id != id).toList()..add(saved);
    await AiChatStore.save(rest);
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _persistCurrentChat();
    });
  }

  /// Удаляет сессию в opencode перед удалением чата из хранилища.
  Future<void> _deleteChat(SavedChat chat) async {
    final chatChat = _chat;
    if (chat.id == _chatId && chatChat != null) {
      await chatChat.removeSession();
      return;
    }
    final sid = chat.sessionId;
    if (sid == null) return;
    final server = OpenCodeServer(baseUrl: _settings.baseUrl, agent: chat.agent);
    try {
      await server.deleteSession(sid);
    } finally {
      server.dispose();
    }
  }

  Future<void> _openHistory() async {
    await _persistCurrentChat();
    if (!mounted) return;
    final choice = await Navigator.of(context).push<ChatHistoryChoice>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryScreen(
          currentChatId: _chatId,
          onDelete: _deleteChat,
        ),
      ),
    );
    if (!mounted) return;
    if (choice != null) {
      if (choice.newChat) {
        _newChat();
      } else if (choice.open != null) {
        _loadChat(choice.open!);
      }
    } else {
      // Вернулись назад. Если текущий чат удалили из истории — начинаем новый.
      final currentId = _chatId;
      if (currentId != null) {
        final exists = (await AiChatStore.load()).any((c) => c.id == currentId);
        if (!exists) _newChat();
      }
    }
  }

  String _contextMessage(String context) {
    return 'Помоги разобраться с этим заданием. Не давай готовое решение '
        'целиком.\n\n$context';
  }

  Future<void> _refreshStatus() async {
    final status = await checkServer(_settings.baseUrl);
    if (mounted) setState(() => _status = status);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final chat = _chat;
    if (chat == null) return;
    if (!chat.isAwaiting) {
      await chat.send(text);
    }
  }

  void _openSettings() {
    final urlCtrl = TextEditingController(text: _settings.baseUrl);
    final agentCtrl = TextEditingController(text: _settings.agent);
    String? checkResult;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Подключение к AI-серверу',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Сервер — это opencode serve, запущенный в Termux на этом '
                'телефоне. Пока сервер не запущен, AI будет недоступен.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Адрес сервера',
                  hintText: 'http://127.0.0.1:4096',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: agentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Агент',
                  hintText: 'tutor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await OpenCodeServer(
                        baseUrl: urlCtrl.text.trim(),
                      ).health();
                      setSheetState(() {
                        checkResult = ok
                            ? 'Соединение есть'
                            : 'Сервер не отвечает';
                      });
                    },
                    child: const Text('Проверить соединение'),
                  ),
                  const SizedBox(width: 12),
                  if (checkResult != null)
                    Text(
                      checkResult!,
                      style: TextStyle(
                        color: checkResult == 'Соединение есть'
                            ? AppColors.success
                            : AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final res = await TermuxLauncher.open();
                    final message = res.status == 'ok'
                        ? 'Termux открыт.\nЕсли сервер ещё не запущен — уже '
                            'после установки он стартует сам (Termux:Boot). '
                            'Если не стартует: запусти в Termux:\n'
                            '  opencode serve'
                        : res.message;
                    final color = res.status == 'ok'
                        ? AppColors.success
                        : AppColors.warning;
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: color,
                          ),
                        );
                    }
                  },
                  icon: const Icon(Icons.terminal, size: 18),
                  label: const Text('Открыть Termux'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final oldBaseUrl = _settings.baseUrl;
                  _settings = _settings.copyWith(
                    baseUrl: urlCtrl.text.trim().isEmpty
                        ? OpenCodeServer.defaultBaseUrl
                        : urlCtrl.text.trim(),
                    agent: agentCtrl.text.trim().isEmpty ? 'tutor' : agentCtrl.text.trim(),
                  );
                  await _settings.save();
                  await _persistCurrentChat();
                  if (oldBaseUrl != _settings.baseUrl) {
                    // Сервер сменился — старая сессия больше не нужна.
                    final oldChat = _chat;
                    _sessionId = null;
                    await oldChat?.removeSession();
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _startChat();
                },
                child: const Text('Сохранить и подключить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistCurrentChat();
    _chat?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final messages = chat?.transcript.messages ?? const <ChatMessage>[];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 24),
            SizedBox(width: 10),
            Text('AI-ассистент'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'Мои чаты',
              onPressed: _openHistory,
              icon: const Icon(Icons.history),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'Настройки сервера',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_status != AiServerStatus.online) _buildStatusBanner(),
          if (chat?.agentNote != null)
            Container(
              width: double.infinity,
              color: AppColors.accent.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chat!.agentNote!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: chat == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg.role == 'user';
                      return _MessageBubble(isUser: isUser, text: msg.text);
                    },
                  ),
          ),
          _InputBar(
            controller: _controller,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final online = _status == AiServerStatus.online;
    final checking = _status == AiServerStatus.checking;
    return Container(
      width: double.infinity,
      color: checking ? AppColors.background : AppColors.danger.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            checking ? Icons.sync : Icons.cloud_off,
            size: 16,
            color: checking ? AppColors.textMuted : AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              checking
                  ? 'Проверяем соединение…'
                  : online
                  ? 'AI-сервер подключён'
                  : 'AI-сервер не запущен. Запусти opencode serve в Termux.',
              style: TextStyle(
                fontSize: 13,
                color: checking ? AppColors.textMuted : AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!checking && !online)
            TextButton(
              onPressed: _refreshStatus,
              child: const Text('Проверить'),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;

  const _MessageBubble({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser)
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
              ),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.primary : AppColors.background,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: text.isEmpty
                    ? const _TypingDots()
                    : DefaultTextStyle(
                        style: TextStyle(
                          color: isUser ? Colors.white : AppColors.textDark,
                          fontSize: 14.5,
                          height: 1.45,
                        ),
                        child: text.contains('```')
                            ? _CodeMessage(text: text, isUser: isUser)
                            : SelectableText(text),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const _CodeMessage({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final parts = text.split('```');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts.map((part) {
        if (part.trim().startsWith('python')) {
          final code = part.replaceFirst(RegExp(r'^python\s*\n?'), '');
          return _CodeBlock(code: code.trim());
        }
        if (part.trim().isNotEmpty) {
          return SelectableText(
            part.trim(),
            style: TextStyle(
              color: isUser ? Colors.white : AppColors.textDark,
              fontSize: 14.5,
              height: 1.45,
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;

  const _CodeBlock({required this.code});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Код скопирован'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _copied
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.check, size: 16, color: AppColors.success),
                  )
                : IconButton(
                    tooltip: 'Скопировать',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    onPressed: _copy,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.codeText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  int _dot = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) setState(() => _dot = (_dot + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: i < _dot ? 1 : 0.35,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Задай вопрос по Python...',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}