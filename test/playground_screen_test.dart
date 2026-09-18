import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/screens/playground_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpPlayground(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: PlaygroundScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> saveSnippet(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.text('Сохранить набросок'));
    await tester.tap(find.text('Сохранить набросок'));
    await tester.pumpAndSettle();

    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, name);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
  }

  testWidgets('песочница: сохранить и открыть набросок', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPlayground(tester);

    const code = 'for i in range(3):\n    print(i)';
    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump();
    await saveSnippet(tester, 'Счёт до трёх');

    expect(find.text('Набросок «Счёт до трёх» сохранён'), findsOneWidget);

    await tester.tap(find.text('Мои наброски'));
    await tester.pumpAndSettle();
    expect(find.text('Счёт до трёх'), findsOneWidget);

    await tester.tap(find.text('Счёт до трёх'));
    await tester.pumpAndSettle();

    expect(find.text('Открыт набросок «Счёт до трёх»'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.text(code),
      ),
      findsOneWidget,
    );
  });

  testWidgets('песочница: перезапись по тому же имени', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPlayground(tester);

    const code = 'print(1)';
    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump();
    await saveSnippet(tester, 'Один');

    await tester.enterText(find.byType(TextField).first, 'print(2)');
    await tester.pump();
    await saveSnippet(tester, 'Один');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Мои наброски'));
    await tester.pumpAndSettle();
    expect(find.text('Один'), findsOneWidget);
  });

  testWidgets('песочница: удалить набросок', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPlayground(tester);

    await tester.enterText(find.byType(TextField).first, 'print("привет")');
    await tester.pump();
    await saveSnippet(tester, 'Лишний');

    await tester.tap(find.text('Мои наброски'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Удалить набросок?'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.text('Набросок удалён'), findsOneWidget);

    await tester.tap(find.text('Мои наброски'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Пока пусто.'), findsOneWidget);
  });
}