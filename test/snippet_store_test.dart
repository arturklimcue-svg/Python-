import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/services/snippet_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('SnippetStore сохраняет и возвращает наброски', () async {
    SharedPreferences.setMockInitialValues({});

    final saved = SavedSnippet(
      id: 's-1',
      title: 'Таблица умножения',
      code: 'for i in range(1, 11):\n    print(i * 7)',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );

    await SnippetStore.save([saved]);
    final loaded = await SnippetStore.load();

    expect(loaded, hasLength(1));
    expect(loaded.first.id, 's-1');
    expect(loaded.first.title, 'Таблица умножения');
    expect(loaded.first.code, contains('print(i * 7)'));
  });

  test('SnippetStore сортирует самые свежие первыми', () async {
    SharedPreferences.setMockInitialValues({});

    await SnippetStore.save([
      SavedSnippet(
        id: 's-old',
        title: 'Старый',
        code: 'print(1)',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      SavedSnippet(
        id: 's-new',
        title: 'Новый',
        code: 'print(2)',
        createdAt: DateTime(2026, 1, 5),
        updatedAt: DateTime(2026, 1, 5),
      ),
    ]);

    final loaded = await SnippetStore.load();
    expect(loaded.first.title, 'Новый');
  });

  test('SnippetStore переживает битые данные', () async {
    SharedPreferences.setMockInitialValues({'snippets_v1': 'not-json'});
    expect(await SnippetStore.load(), isEmpty);

    SharedPreferences.setMockInitialValues({});
    expect(await SnippetStore.load(), isEmpty);
  });

  test('autoTitle берёт первую строку кода без комментариев', () {
    expect(SavedSnippet.autoTitle('x = 5\nprint(x)'), 'x = 5');
    expect(
      SavedSnippet.autoTitle('# игрушка\nwhile True:\n    pass'),
      'while True:',
    );
    expect(SavedSnippet.autoTitle('   '), startsWith('Набросок '));
    final long = '${'a' * 60} = 1';
    final title = SavedSnippet.autoTitle(long);
    expect(title.length, 41);
    expect(title, endsWith('…'));
  });

  test('newId уникален', () {
    expect(SnippetStore.newId(), isNot(SnippetStore.newId()));
  });
}