import 'package:flutter/material.dart';

import '../services/python_interpreter.dart';
import '../services/python_runtime.dart';
import '../theme.dart';
import '../widgets/python_input_bar.dart';
import '../widgets/python_output_panel.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  final _ctrl = TextEditingController(text: 'print("Привет, мир!")\n');
  final _inputCtrl = TextEditingController();
  List<String> _inputs = [];
  String? _output;
  String? _error;
  bool _ran = false;
  bool _running = false;
  bool _needsInput = false;

  static const _examples = <String, String>{
    'Привет': 'print("Привет, мир!")\n',
    'Цикл': 'for i in range(5):\n    print(i)\n',
    'Список': 'nums = [3, 1, 2]\nprint(sorted(nums))\nprint(sum(nums))\n',
    'Функция': 'def greet(name):\n    return f"Привет, {name}!"\n\nprint(greet("Аня"))\n',
    'Диалог': 'name = input("Как тебя зовут? ")\nprint(f"Привет, {name}!")\n',
  };

  @override
  void dispose() {
    _ctrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    PyRunResult result;
    try {
      result = await PythonRuntime.run(_ctrl.text, stdin: _inputs.join('\n'));
    } catch (e) {
      result = PyRunResult(false, '', 'Не удалось выполнить код: $e');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _ran = true;
      _output = result.stdout;
      _needsInput = result.ok && result.inputsMissing > 0;
      _error = result.ok ? null : result.error;
    });
  }

  void _submitInput() {
    _inputs.add(_inputCtrl.text);
    _inputCtrl.clear();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Песочница',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Пиши любой код на Python и запускай прямо здесь — вывод появится '
          'даже при ошибке. Если программа спросит данные, впиши ответ и '
          'нажми «Отправить».',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _examples.entries)
              ActionChip(
                label: Text(entry.key),
                onPressed: () => setState(() {
                  _ctrl.text = entry.value;
                  _inputs = [];
                  _inputCtrl.clear();
                  _needsInput = false;
                  _output = null;
                  _error = null;
                  _ran = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.codeBg,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _ctrl,
            maxLines: null,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.45,
              color: AppColors.codeText,
            ),
            cursorColor: AppColors.codeText,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '# напиши код на Python',
              hintStyle: TextStyle(color: Color(0xFF8887A8)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_running ? 'Выполняется…' : 'Запустить'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (_ran) ...[
          const SizedBox(height: 12),
          PythonOutputPanel(output: _output ?? '', error: _error),
        ],
        if (_ran && _needsInput && !_running) ...[
          const SizedBox(height: 10),
          PythonInputBar(
            controller: _inputCtrl,
            onSubmit: _submitInput,
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }
}
