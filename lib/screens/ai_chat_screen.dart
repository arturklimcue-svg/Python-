import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/ai_service.dart';

class AiChatScreen extends StatefulWidget {
  final int currentModule;
  final String currentModuleTitle;

  const AiChatScreen({
    super.key,
    required this.currentModule,
    required this.currentModuleTitle,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final AiAgent _agent;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _agent = AiAgent(
      currentModule: widget.currentModule,
      currentModuleTitle: widget.currentModuleTitle,
    );
    _agent.sendMessage('привет');
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() {});
    await _agent.sendMessage(text);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 24),
            SizedBox(width: 10),
            Text('AI-ассистент'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: _agent.messages.length,
              itemBuilder: (context, index) {
                final msg = _agent.messages[index];
                final isUser = msg.role == 'user';
                return _MessageBubble(isUser: isUser, text: msg.text);
              },
            ),
          ),
          _InputBar(controller: _controller, onSend: _send),
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
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: isUser ? Colors.white : AppColors.textDark,
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                  child: text.contains('```')
                      ? _CodeMessage(text: text, isUser: isUser)
                      : SelectableText(
                          text,
                          style: TextStyle(
                            color: isUser ? Colors.white : AppColors.textDark,
                            fontSize: 14.5,
                            height: 1.45,
                          ),
                        ),
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
        if (part.trim().startsWith('python') || part.trim().startsWith('\npython')) {
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
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
