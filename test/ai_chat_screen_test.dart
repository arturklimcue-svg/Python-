import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/screens/ai_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/android_intent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
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

    // Termux должен и открыться, и получить команды на установку opencode.
    expect(
      calls.map((c) => c.method),
      containsAll(<String>['launch', 'sendService']),
    );
    final runCommand = calls.firstWhere((c) => c.method == 'sendService');
    final args = Map<Object?, Object?>.from(runCommand.arguments as Map);
    expect(args['action'], 'com.termux.RUN_COMMAND');
    expect(args['componentName'], 'com.termux.app.RunCommandService');
    final extras = Map<Object?, Object?>.from(args['arguments'] as Map);
    expect(extras['com.termux.RUN_COMMAND_STDIN'],
        contains('npm install -g opencode-ai'));
    expect(extras['com.termux.RUN_COMMAND_BACKGROUND'], isFalse);

    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
  });
}
