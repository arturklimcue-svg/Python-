import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/services/python_interpreter.dart';
import 'package:kodik/services/python_runtime.dart';

void main() {
  test('diffOutputTail возвращает только новые строки', () {
    const prev = 'Поле:\nX |  |\nХод O: ';
    const next = 'Поле:\nX |  |\nХод O: Клетка занята!\nПоле:\nX |  |\nХод X: ';
    expect(
      diffOutputTail(prev, next),
      'Клетка занята!\nПоле:\nX |  |\nХод X: ',
    );
  });

  test('diffOutputTail с пустым предыдущим отдаёт весь вывод', () {
    expect(diffOutputTail('', 'Привет\n'), 'Привет\n');
  });

  test('diffOutputTail при изменившемся начале отдаёт весь вывод', () {
    const prev = 'A\nB\n';
    const next = 'C\nB\n';
    expect(diffOutputTail(prev, next), next);
  });

  test('diffOutputTail когда вывод это уже виденный префикс — пусто', () {
    const prev = 'Ход: Принято: а\nХод: ';
    expect(diffOutputTail(prev, 'Ход: '), '');
  });

  test('диалог по шагам похож на настоящую консоль', () {
    const code = 'while True:\n'
        '    line = input("Ход: ")\n'
        '    if line == "стоп":\n'
        '        break\n'
        '    print("Принято:", line)\n';
    var shown = '';
    var lastRaw = '';

    final r1 = runPython(code);
    expect(r1.ok && r1.inputsMissing > 0, isTrue, reason: r1.error);
    lastRaw = r1.stdout;
    shown = diffOutputTail('', lastRaw);
    expect(shown, 'Ход: ');

    final r2 = runPython(code, stdin: 'а\n');
    shown += diffOutputTail(lastRaw, r2.stdout);
    lastRaw = r2.stdout;
    expect(shown, 'Ход: Принято: а\nХод: ');
    expect(r2.inputsMissing, greaterThan(0));

    final r3 = runPython(code, stdin: 'стоп\n');
    shown += diffOutputTail(lastRaw, r3.stdout);
    expect(r3.inputsMissing, 0);
    expect(shown, 'Ход: Принято: а\nХод: ');
  });
}