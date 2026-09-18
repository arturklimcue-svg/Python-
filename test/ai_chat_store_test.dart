import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/services/ai_chat_store.dart';
import 'package:kodik/services/chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AiChatStore сохраняет и возвращает чаты', () async {
    SharedPreferences.setMockInitialValues({});

    final saved = SavedChat(
      id: 'chat-1',
      sessionId: 'ses_1',
      title: 'Привет',
      agent: 'tutor',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      messages: [
        ChatMessage(
          role: 'user',
          text: 'Привет',
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          role: 'ai',
          text: 'Привет! Чем помочь?',
          timestamp: DateTime(2026, 1, 1),
        ),
      ],
    );

    await AiChatStore.save([saved]);
    final loaded = await AiChatStore.load();

    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'chat-1');
    expect(loaded.first.sessionId, 'ses_1');
    expect(loaded.first.title, 'Привет');
    expect(loaded.first.messages, hasLength(2));
    expect(loaded.first.messages.first.role, 'user');
    expect(loaded.first.messages.last.text, 'Привет! Чем помочь?');
  });

  test('AiChatStore переживает битые данные', () async {
    SharedPreferences.setMockInitialValues({'ai_chats_v1': 'not-json'});
    expect(await AiChatStore.load(), isEmpty);

    SharedPreferences.setMockInitialValues({});
    expect(await AiChatStore.load(), isEmpty);
  });

  test('makeTitle берёт первый вопрос пользователя', () {
    final title = SavedChat.makeTitle([
      ChatMessage(
        role: 'ai',
        text: 'Здравствуй!',
        timestamp: DateTime(2026, 1, 1),
      ),
      ChatMessage(
        role: 'user',
        text: 'Как работает print?',
        timestamp: DateTime(2026, 1, 1),
      ),
    ]);
    expect(title, 'Как работает print?');

    final fallback = SavedChat.makeTitle([
      ChatMessage(
        role: 'ai',
        text: 'Привет',
        timestamp: DateTime(2026, 1, 1),
      ),
    ]);
    expect(fallback, startsWith('Чат от '));
  });
}