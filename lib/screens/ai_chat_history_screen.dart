import 'package:flutter/material.dart';

import '../services/ai_chat_store.dart';
import '../theme.dart';

/// Результат выбора в истории чатов.
class ChatHistoryChoice {
  final SavedChat? open;
  final bool newChat;

  const ChatHistoryChoice._({this.open, this.newChat = false});

  /// Открыть сохранённый чат.
  const ChatHistoryChoice.open(SavedChat chat) : this._(open: chat);

  /// Начать новый диалог.
  const ChatHistoryChoice.newChat() : this._(newChat: true);
}

/// Список сохранённых диалогов: открыть или удалить (вместе с сессией на
/// AI-сервере).
class ChatHistoryScreen extends StatefulWidget {
  final String? currentChatId;

  /// Вызывается перед удалением чата из хранилища — например, чтобы удалить
  /// сессию в opencode.
  final Future<void> Function(SavedChat chat)? onDelete;

  const ChatHistoryScreen({super.key, this.currentChatId, this.onDelete});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<SavedChat> _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final chats = await AiChatStore.load();
    if (!mounted) return;
    setState(() {
      _chats = chats;
      _loading = false;
    });
  }

  Future<void> _confirmDelete(SavedChat chat) async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text(
          'Диалог будет удалён из приложения и с AI-сервера.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (accept != true || !mounted) return;

    await widget.onDelete?.call(chat);
    final rest = (await AiChatStore.load())
        .where((c) => c.id != chat.id)
        .toList();
    await AiChatStore.save(rest);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои чаты'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pop(const ChatHistoryChoice.newChat()),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Новый чат'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Здесь появятся сохранённые диалоги.\n'
                  'Начни новый чат — он сохранится автоматически.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            )
          : ListView.separated(
              itemCount: _chats.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final chat = _chats[i];
                final isCurrent = chat.id == widget.currentChatId;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.chat_bubble : Icons.forum_outlined,
                    color: isCurrent ? AppColors.primary : null,
                  ),
                  title: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${chat.messages.length} сообщ. • '
                    '${_lastTouched(chat.updatedAt)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                    onPressed: () => _confirmDelete(chat),
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(ChatHistoryChoice.open(chat)),
                );
              },
            ),
    );
  }

  String _lastTouched(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}