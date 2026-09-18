import 'package:flutter/material.dart';

import '../services/python_interpreter.dart';
import '../services/python_runtime.dart';
import '../services/snippet_store.dart';
import '../theme.dart';
import '../widgets/python_input_bar.dart';
import '../widgets/python_output_panel.dart';
import 'ai_chat_screen.dart';

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
  String _lastStdout = '';
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

  Future<void> _run({bool fresh = false}) async {
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
      _output = fresh ? result.stdout : diffOutputTail(_lastStdout, result.stdout);
      _lastStdout = result.stdout;
      _needsInput = result.ok && result.inputsMissing > 0;
      _error = result.ok ? null : result.error;
    });
  }

  void _submitInput() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputs.add(text);
    _inputCtrl.clear();
    _run();
  }

  /// Сбрасывает состояние запуска и подставляет новый код (пример/набросок).
  void _resetForCode(String code) {
    _ctrl.text = code;
    _inputs = [];
    _inputCtrl.clear();
    _needsInput = false;
    _output = null;
    _lastStdout = '';
    _error = null;
    _ran = false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveSnippet() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      _toast('Сначала напиши код');
      return;
    }
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _SaveSnippetDialog(initialTitle: SavedSnippet.autoTitle(code)),
    );
    if (title == null || !mounted) return;

    final name = title.isEmpty ? SavedSnippet.autoTitle(code) : title;
    var snippets = await SnippetStore.load();
    final i = snippets.indexWhere((s) => s.title == name);
    final now = DateTime.now();
    if (i >= 0) {
      final old = snippets[i];
      snippets[i] = SavedSnippet(
        id: old.id,
        title: old.title,
        code: code,
        createdAt: old.createdAt,
        updatedAt: now,
      );
    } else {
      snippets.add(
        SavedSnippet(
          id: SnippetStore.newId(),
          title: name,
          code: code,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    snippets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await SnippetStore.save(snippets);
    if (!mounted) return;
    _toast('Набросок «$name» сохранён');
  }

  Future<void> _openSnippets() async {
    final snippets = await SnippetStore.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: snippets.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bookmark_border, size: 40, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'Пока пусто.\nНажми «Сохранить набросок», чтобы '
                      'не потерять свой код.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Мои наброски',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final s in snippets)
                    ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        SavedSnippet.formatDate(s.updatedAt),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.danger,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _confirmDeleteSnippet(s);
                        },
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _loadSnippet(s);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _loadSnippet(SavedSnippet s) async {
    setState(() => _resetForCode(s.code));
    _toast('Открыт набросок «${s.title}»');
  }

  Future<void> _confirmDeleteSnippet(SavedSnippet s) async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить набросок?'),
        content: Text('«${s.title}» будет удалён безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (accept != true || !mounted) return;

    final rest = (await SnippetStore.load())
        .where((x) => x.id != s.id)
        .toList();
    await SnippetStore.save(rest);
    if (!mounted) return;
    _toast('Набросок удалён');
  }

  void _askAi() {
    final buffer = StringBuffer()
      ..writeln('Это свободная песочница ученика — готового задания нет.')
      ..writeln('Ученик экспериментирует с кодом. Помоги разобраться.')
      ..writeln()
      ..writeln('Код из песочницы:')
      ..writeln('```python')
      ..writeln(_ctrl.text)
      ..writeln('```');
    final out = _output ?? '';
    if (out.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Вывод программы:')
        ..writeln(out);
    }
    if (_error != null) {
      buffer
        ..writeln()
        ..writeln('Ошибка:')
        ..writeln(_error);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiChatScreen(initialContext: buffer.toString()),
      ),
    );
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
          'нажми «Отправить». Любимые наброски сохраняй — они останутся '
          'в приложении.',
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
                onPressed: () => setState(
                  () => _resetForCode(entry.value),
                ),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saveSnippet,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Сохранить набросок'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: AppColors.primary,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _openSnippets,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Мои наброски'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _running ? null : () => _run(fresh: true),
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _askAi,
          icon: const Icon(Icons.smart_toy_outlined, size: 18),
          label: const Text('Спросить AI'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppColors.primary,
          ),
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
            canSubmit: _inputCtrl.text.trim().isNotEmpty,
          ),
        ],
      ],
    );
  }
}

class _SaveSnippetDialog extends StatefulWidget {
  const _SaveSnippetDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_SaveSnippetDialog> createState() => _SaveSnippetDialogState();
}

class _SaveSnippetDialogState extends State<_SaveSnippetDialog> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сохранить набросок'),
      content: TextField(
        controller: _nameCtrl,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(
          labelText: 'Название',
          hintText: 'например: Таблица умножения',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_nameCtrl.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
