import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/services/ai_service.dart';
import 'package:kodik/data/course_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiAgent', () {
    test('приветствие работает', () async {
      final agent = AiAgent(currentModule: 1, currentModuleTitle: 'Тест');
      await agent.sendMessage('Привет');
      expect(agent.messages.length, 2);
      expect(agent.messages.first.role, 'user');
      expect(agent.messages.last.role, 'ai');
      expect(agent.messages.last.text.toLowerCase(), contains('помог'));
    });

    test('ответ по переменным', () async {
      final agent = AiAgent(currentModule: 1, currentModuleTitle: 'Тест');
      await agent.sendMessage('Что такое переменные?');
      expect(agent.messages.last.text, contains('int'));
    });

    test('fallback ответ', () async {
      final agent = AiAgent(currentModule: 1, currentModuleTitle: 'Тест');
      await agent.sendMessage('qwerty12345');
      expect(agent.messages.last.text, contains('не знаю'));
    });
  });

  test('курс содержит 9 модулей', () async {
    final course = await CourseRepository.loadFromAssets();
    expect(course.moduleCount, 9);
    expect(course.totalLessons, 71);
  });
}
