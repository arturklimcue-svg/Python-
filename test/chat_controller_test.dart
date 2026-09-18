import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/services/chat_controller.dart';
import 'package:kodik/services/opencode_server.dart';

void main() {
  group('parseSseBuffer', () {
    test('извлекает data-события', () {
      const buffer = 'data: {"type":"a","properties":{}}\n\n'
          'data: {"type":"b","properties":{"x":1}}\n\n'
          'event: ping\ndata: {"type":"c"}\n\n';
      final events = parseSseBuffer(buffer);
      expect(events.map((e) => e['type']), ['a', 'b', 'c']);
    });

    test('игнорирует не-JSON и пустые строки', () {
      const buffer = 'data:\n\n'
          'data: not json\n\n'
          'foo: bar\n\n'
          'data: {"type":"ok"}\n\n';
      final events = parseSseBuffer(buffer);
      expect(events.map((e) => e['type']), ['ok']);
    });
  });

  group('ChatTranscript', () {
    Map<String, dynamic> userUpdated(String id) => {
          'type': 'message.updated',
          'properties': {
            'info': {'id': id, 'role': 'user'},
          },
        };

    Map<String, dynamic> textPart(String messageId, String text) => {
          'type': 'message.part.updated',
          'properties': {
            'part': {
              'type': 'text',
              'messageID': messageId,
              'text': text,
            },
          },
        };

    test('стримит текст ответа и завершает на session.idle', () {
      final t = ChatTranscript();
      t.userMessage('Привет');
      t.begin();
      t.handleEvent(userUpdated('msg_user'));
      t.handleEvent(textPart('msg_user', 'Привет'));
      expect(t.messages.last.text, isEmpty, reason: 'эхо юзера не попадает');

      t.handleEvent(textPart('msg_assistant', 'В Python есть'));
      expect(t.isAwaiting, isTrue);
      expect(t.messages.last.text, 'В Python есть');

      t.handleEvent(textPart('msg_assistant', 'В Python есть списки!'));
      expect(t.messages.last.text, 'В Python есть списки!');

      t.handleEvent({
        'type': 'session.idle',
        'properties': {'sessionID': 's1'},
      });
      expect(t.isAwaiting, isFalse);
      expect(t.messages.length, 2);
      expect(t.messages.first.role, 'user');
      expect(t.messages.last.role, 'ai');
    });

    test('ошибка из message.updated попадает в пузырь', () {
      final t = ChatTranscript();
      t.userMessage('Что не так?');
      t.begin();
      t.handleEvent(userUpdated('msg_user'));
      t.handleEvent({
        'type': 'message.updated',
        'properties': {
          'info': {
            'id': 'msg_ai',
            'role': 'assistant',
            'error': {
              'data': {
                'statusCode': 403,
                'message': 'access denied',
              },
            },
          },
        },
      });
      expect(t.isAwaiting, isFalse);
      expect(t.messages.last.text, contains('403'));
      expect(t.messages.last.text, contains('access denied'));
    });

    test('вне ответа часть не стримится', () {
      final t = ChatTranscript();
      t.userMessage('Хай');
      t.finish();
      t.handleEvent(textPart('msg_x', 'неожиданный текст'));
      expect(t.messages.last.role, 'user');
      expect(t.messages.last.text, 'Хай');
    });
  });

  test('describeEventError форматирует данные', () {
    final msg = ChatTranscript.describeEventError({
      'data': {
        'statusCode': 429,
        'message': 'too many requests',
      },
    });
    expect(msg, contains('429'));
    expect(msg, contains('too many requests'));
  });

  test('describeSendError для SocketException дружелюбно', () {
    final msg = ChatController.describeSendError(const SocketException('test'));
    expect(msg, contains('opencode serve'));
  });
}