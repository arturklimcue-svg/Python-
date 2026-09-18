import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai_settings.dart';
import '../services/chat_controller.dart';
import '../services/opencode_server.dart';
import '../theme.dart';

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

  void _startChat() {
    _chat?.dispose();
    final chat = ChatController(
      server: OpenCodeServer(
        baseUrl: _settings.baseUrl,
        agent: _settings.agent,
      ),
    );
    chat.onUpdate = () {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    };
    _chat = chat;
    setState(() => _status = AiServerStatus.checking);
    chat.start();
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  _settings = _settings.copyWith(
                    baseUrl: urlCtrl.text.trim().isEmpty
                        ? OpenCodeServer.defaultBaseUrl
                        : urlCtrl.text.trim(),
                    agent: agentCtrl.text.trim().isEmpty ? 'tutor' : agentCtrl.text.trim(),
                  );
                  await _settings.save();
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
    final messages = chat?.messages ?? const <ChatMessage>[];
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
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.codeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              code.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.codeText,
                height: 1.4,
              ),
            ),
          );
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