import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/screens/ai_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AI-настройки: кнопка «Открыть Termux» показывает SnackBar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiChatScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Открыть Termux'), findsOneWidget);

    await tester.ensureVisible(find.text('Открыть Termux'));
    await tester.tap(find.text('Открыть Termux'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
