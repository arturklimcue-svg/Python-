import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/screens/ai_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/android_intent_plus');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'resolve') return true;
      if (call.method == 'startActivity') return true;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('AI-настройки: кнопка «Открыть Termux» показывает SnackBar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiChatScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Открыть Termux'), findsOneWidget);

    await tester.ensureVisible(find.text('Открыть Termux'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Открыть Termux'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Termux'), findsWidgets);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
