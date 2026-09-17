import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/exercise.dart';
import '../services/progress_service.dart';
import '../services/python_interpreter.dart';
import '../theme.dart';
import '../widgets/code_block.dart';
import '../widgets/python_input_bar.dart';

class LessonScreen extends StatefulWidget {
  final Lesson lesson;
  final ProgressService progress;

  const LessonScreen({
    super.key,
    required this.lesson,
    required this.progress,
  });

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late int _index;
  bool _submitted = false;
  bool _isCorrect = false;
  Set<int> _selected = {};
  bool? _tfAnswer;
  late TextEditingController _fillCtrl;
  late TextEditingController _editorCtrl;
  final TextEditingController _inputCtrl = TextEditingController();
  List<int> _buildOrder = [];
  List<String> _editorInput = [];
  bool _editorNeedsInput = false;
  String? _editorOutput;
  String? _editorError;
  bool _editorRan = false;
  int _rightCount = 0;
  bool _finished = false;

  Exercise get _exercise => widget.lesson.exercises[_index];

  @override
  void initState() {
    super.initState();
    final lp = widget.progress.lessonProgressOf(widget.lesson.id);
    _index = (lp?.last ?? 0)
        .clamp(0, widget.lesson.exerciseCount - 1)
        .toInt();
    _fillCtrl = TextEditingController();
    _editorCtrl = TextEditingController(
      text: widget.lesson.exercises[_index].task?.starter ?? '',
    );
    _resetEditorInput();
  }

  /// Готовые данные для input(): берём их из задания и позволяем дополнять
  /// по шагам прямо в редакторе/Песочнице.
  void _resetEditorInput() {
    final stdin = _exercise.task?.stdin ?? '';
    final lines = stdin.isEmpty ? <String>[] : stdin.split('\n');
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    _editorInput = lines;
    _editorNeedsInput = false;
    _inputCtrl.clear();
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    _editorCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _runEditor() {
    final result = runPython(_editorCtrl.text, stdin: _editorInput.join('\n'));
    setState(() {
      _editorRan = true;
      _editorOutput = result.stdout;
      _editorError = result.ok ? null : result.error;
      _editorNeedsInput = result.ok && result.inputsMissing > 0;
    });
  }

  void _submitEditorInput() {
    _editorInput.add(_inputCtrl.text);
    _inputCtrl.clear();
    _runEditor();
  }

  void _checkAnswer() {
    if (_submitted) return;
    final task = _exercise.task;
    bool correct;
    switch (task!.type) {
      case TaskType.single:
      case TaskType.codeOutput:
        correct = task.checkAnswer(_selected.length == 1 ? _selected.first : -1);
      case TaskType.multi:
        correct = task.checkAnswer(_selected.toList());
      case TaskType.trueFalse:
        correct = task.checkAnswer(_tfAnswer);
      case TaskType.fill:
        correct = task.checkAnswer(_fillCtrl.text);
      case TaskType.codeBuild:
        correct = task.checkAnswer(List<int>.from(_buildOrder));
      case TaskType.codeEditor:
        final result = runPython(_editorCtrl.text, stdin: _editorInput.join('\n'));
        _editorRan = true;
        _editorOutput = result.stdout;
        _editorError = result.ok ? null : result.error;
        _editorNeedsInput = result.ok && result.inputsMissing > 0;
        correct = task.checkEditorCode(_editorCtrl.text);
    }
    widget.progress.recordExercise(widget.lesson.id, _index, correct);
    setState(() {
      _submitted = true;
      _isCorrect = correct;
      if (correct) _rightCount++;
    });
  }

  void _retry() {
    setState(() {
      _submitted = false;
      _isCorrect = false;
      _selected = {};
      _tfAnswer = null;
      _fillCtrl.clear();
      _buildOrder = [];
    });
  }

  bool _canCheck() {
    if (!_exercise.hasTask || _submitted) return false;
    final task = _exercise.task!;
    switch (task.type) {
      case TaskType.single:
      case TaskType.codeOutput:
        return _selected.length == 1;
      case TaskType.multi:
        return _selected.isNotEmpty;
      case TaskType.trueFalse:
        return _tfAnswer != null;
      case TaskType.fill:
        return _fillCtrl.text.trim().isNotEmpty;
      case TaskType.codeBuild:
        return _buildOrder.length == task.options.length;
      case TaskType.codeEditor:
        return _editorCtrl.text.trim().isNotEmpty;
    }
  }

  void _next() {
    if (!_exercise.hasTask) {
      widget.progress.advanceLesson(widget.lesson.id, _index);
    }
    final lastExercise = _index == widget.lesson.exerciseCount - 1;
    if (!lastExercise) {
      setState(() {
        _index++;
        _submitted = false;
        _isCorrect = false;
        _selected = {};
        _tfAnswer = null;
        _fillCtrl.clear();
        _buildOrder = [];
        _editorOutput = null;
        _editorError = null;
        _editorRan = false;
        _editorCtrl.text = _exercise.task?.starter ?? '';
        _resetEditorInput();
      });
      return;
    }
    _finish();
  }

  Future<void> _finish() async {
    if (!_finished) {
      _finished = true;
      await widget.progress
          .completeLesson(widget.lesson.id, widget.lesson.xp, 5);
    }
    if (!mounted) return;
    final title = widget.lesson.isPractice ? 'Практика завершена' : 'Урок пройден';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          'Ты ответил правильно на $_rightCount из '
          '${widget.lesson.exerciseCount} упражнений.\n'
          '+${widget.lesson.xp} XP и +5 монет в копилку!',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отлично!'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_index + 1) / widget.lesson.exerciseCount,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            color: AppColors.primary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  'Упражнение ${_index + 1} из ${widget.lesson.exerciseCount}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (widget.lesson.isPractice)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Практика',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RichText(exercise.text),
                    if (exercise.code != null) CodeBlock(code: exercise.code!),
                    if (exercise.hasTask) ...[
                      const SizedBox(height: 18),
                      const Divider(color: AppColors.background),
                      _TaskPanel(
                        task: exercise.task!,
                        submitted: _submitted,
                        isCorrect: _isCorrect,
                        selected: _selected,
                        tfAnswer: _tfAnswer,
                        fillCtrl: _fillCtrl,
                        buildOrder: _buildOrder,
                        onSelectMulti: (i) => setState(() {
                          _selected.contains(i)
                              ? _selected.remove(i)
                              : _selected.add(i);
                        }),
                        onSelectSingle: (i) => setState(() {
                          _selected = {i};
                        }),
                        onSelectTf: (v) => setState(() => _tfAnswer = v),
                        onBuildTap: (i) => setState(() {
                          if (_buildOrder.contains(i)) {
                            _buildOrder.removeAt(_buildOrder.indexOf(i));
                          } else {
                            _buildOrder.add(i);
                          }
                        }),
                        onFillChanged: () => setState(() {}),
                        editorCtrl: _editorCtrl,
                        editorOutput: _editorOutput,
                        editorError: _editorError,
                        editorRan: _editorRan,
                        editorNeedsInput: _editorNeedsInput,
                        inputCtrl: _inputCtrl,
                        onSubmitInput: _submitEditorInput,
                        onInputChanged: () => setState(() {}),
                        onRun: _runEditor,
                        onEditorChanged: () => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _BottomButtons(
                      hasTask: exercise.hasTask,
                      canCheck: _canCheck(),
                      submitted: _submitted,
                      isCorrect: _isCorrect,
                      onCheck: _checkAnswer,
                      onNext: _next,
                      onRetry: _retry,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RichText extends StatelessWidget {
  final String text;

  const _RichText(this.text);

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final paragraphs = text.split('\n\n');
    final children = <Widget>[];
    for (final p in paragraphs) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(trimmed, style: const TextStyle(fontSize: 16, height: 1.5)),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _TaskPanel extends StatelessWidget {
  final Task task;
  final bool submitted;
  final bool isCorrect;
  final Set<int> selected;
  final bool? tfAnswer;
  final TextEditingController fillCtrl;
  final List<int> buildOrder;
  final void Function(int) onSelectSingle;
  final void Function(int) onSelectMulti;
  final void Function(bool) onSelectTf;
  final void Function(int) onBuildTap;
  final VoidCallback onFillChanged;
  final TextEditingController editorCtrl;
  final String? editorOutput;
  final String? editorError;
  final bool editorRan;
  final bool editorNeedsInput;
  final TextEditingController inputCtrl;
  final VoidCallback onSubmitInput;
  final VoidCallback onInputChanged;
  final VoidCallback onRun;
  final VoidCallback onEditorChanged;

  const _TaskPanel({
    required this.task,
    required this.submitted,
    required this.isCorrect,
    required this.selected,
    required this.tfAnswer,
    required this.fillCtrl,
    required this.buildOrder,
    required this.onSelectSingle,
    required this.onSelectMulti,
    required this.onSelectTf,
    required this.onBuildTap,
    required this.onFillChanged,
    required this.editorCtrl,
    required this.editorOutput,
    required this.editorError,
    required this.editorRan,
    required this.editorNeedsInput,
    required this.inputCtrl,
    required this.onSubmitInput,
    required this.onInputChanged,
    required this.onRun,
    required this.onEditorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (task.question.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            task.question,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
    ];

    switch (task.type) {
      case TaskType.single:
      case TaskType.codeOutput:
        children.addAll(_buildOptionList(single: true));
      case TaskType.multi:
        children.addAll(_buildOptionList(single: false));
      case TaskType.trueFalse:
        children.add(_buildTrueFalse());
      case TaskType.fill:
        children.add(_buildFill());
      case TaskType.codeBuild:
        children.add(_buildCodeBuild());
      case TaskType.codeEditor:
        children.add(_buildCodeEditor());
    }

    if (submitted) {
      children.add(_FeedbackBar(task: task, correct: isCorrect));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildCodeBuild() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Нажми на строки по очереди, чтобы собрать программу.',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ),
        for (var i = 0; i < task.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BuildLineTile(
              index: i,
              line: task.options[i],
              position: buildOrder.indexOf(i),
              submitted: submitted,
              correctOrder: task.correct,
              onTap: submitted ? null : () => onBuildTap(i),
            ),
          ),
      ],
    );
  }

  Widget _buildCodeEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Напиши программу и нажми «Запустить». Вывод появится ниже — '
          'даже если в коде ошибка. Если программа спросит данные, впиши '
          'ответ и нажми «Отправить».',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.codeBg,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: editorCtrl,
            enabled: !submitted,
            maxLines: null,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => onEditorChanged(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.45,
              color: AppColors.codeText,
            ),
            cursorColor: AppColors.codeText,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '# твой код',
              hintStyle: TextStyle(color: Color(0xFF8887A8)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: submitted ? null : onRun,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Запустить'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (editorRan) ...[
          const SizedBox(height: 12),
          _OutputPanel(output: editorOutput ?? '', error: editorError),
        ],
        if (editorRan && editorNeedsInput && !submitted) ...[
          const SizedBox(height: 10),
          PythonInputBar(
            controller: inputCtrl,
            onSubmit: onSubmitInput,
            onChanged: onInputChanged,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildOptionList({required bool single}) {
    return [
      for (var i = 0; i < task.options.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionTile(
            label: task.options[i],
            selected: selected.contains(i),
            showResult: submitted,
            isRight: task.correct.contains(i),
            isWrong: selected.contains(i) && !task.correct.contains(i),
            onTap: submitted || single
                ? () => onSelectSingle(i)
                : () => onSelectMulti(i),
          ),
        ),
    ];
  }

  Widget _buildTrueFalse() {
    final buttons = <Widget>[];
    for (final v in [true, false]) {
      final label = v ? 'Правда' : 'Ложь';
      final active = tfAnswer == v;
      buttons.add(Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(
            onPressed: submitted ? null : () => onSelectTf(v),
            style: OutlinedButton.styleFrom(
              backgroundColor: active ? AppColors.primary : null,
              side: BorderSide(
                color: active ? AppColors.primary : AppColors.textMuted,
                width: 1.4,
              ),
              foregroundColor: active ? Colors.white : AppColors.textDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(label),
          ),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: buttons),
    );
  }

  Widget _buildFill() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 8,
          children: [
            if (task.fillBefore.isNotEmpty)
              Text(task.fillBefore,
                  style: const TextStyle(
                      fontSize: 16, fontFamily: 'monospace')),
            Container(
              constraints: const BoxConstraints(maxWidth: 260),
              child: TextField(
                controller: fillCtrl,
                enabled: !submitted || !isCorrect,
                onChanged: (_) => onFillChanged(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'введи ответ…',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (task.fillAfter.isNotEmpty)
              Text(task.fillAfter,
                  style: const TextStyle(
                      fontSize: 16, fontFamily: 'monospace')),
          ],
        ),
      ],
    );
  }
}

class _OutputPanel extends StatelessWidget {
  final String output;
  final String? error;

  const _OutputPanel({required this.output, this.error});

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.danger.withValues(alpha: 0.10)
            : const Color(0xFFF0F1F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.textMuted.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.terminal,
                size: 16,
                color: hasError ? AppColors.danger : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Вывод программы',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: hasError ? AppColors.danger : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (output.isNotEmpty)
            SelectableText(
              output,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
            ),
          if (hasError)
            Text(
              error!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (output.isEmpty && !hasError)
            const Text(
              '(пусто)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool showResult;
  final bool isRight;
  final bool isWrong;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.showResult,
    required this.isRight,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color? border;
    Color? fg;
    IconData? icon;

    if (showResult) {
      if (isRight) {
        bg = AppColors.success.withValues(alpha: 0.14);
        border = AppColors.success;
        fg = AppColors.success;
        icon = Icons.check_circle;
      } else if (isWrong) {
        bg = AppColors.danger.withValues(alpha: 0.12);
        border = AppColors.danger;
        fg = AppColors.danger;
        icon = Icons.cancel;
      } else {
        bg = AppColors.background;
        border = AppColors.textMuted.withValues(alpha: 0.35);
        fg = AppColors.textMuted;
        icon = Icons.remove_circle_outline;
      }
    } else {
      bg = selected ? AppColors.primary : AppColors.background;
      border = selected ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.35);
      fg = selected ? Colors.white : AppColors.textDark;
      icon = Icons.circle_outlined;
    }

    return InkWell(
      onTap: showResult ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildLineTile extends StatelessWidget {
  final int index;
  final String line;
  final int position;
  final bool submitted;
  final List<int> correctOrder;
  final VoidCallback? onTap;

  const _BuildLineTile({
    required this.index,
    required this.line,
    required this.position,
    required this.submitted,
    required this.correctOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color fg;
    Color badgeFg;

    final placed = position >= 0;
    final rightPos =
        placed && position < correctOrder.length && correctOrder[position] == index;

    if (submitted) {
      if (rightPos) {
        bg = AppColors.success.withValues(alpha: 0.14);
        border = AppColors.success;
        fg = AppColors.success;
        badgeFg = Colors.white;
      } else if (placed) {
        bg = AppColors.danger.withValues(alpha: 0.12);
        border = AppColors.danger;
        fg = AppColors.danger;
        badgeFg = Colors.white;
      } else {
        bg = AppColors.background;
        border = AppColors.textMuted.withValues(alpha: 0.35);
        fg = AppColors.textMuted;
        badgeFg = AppColors.textMuted;
      }
    } else {
      bg = placed ? AppColors.primary : AppColors.background;
      border = placed ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.35);
      fg = placed ? Colors.white : AppColors.textDark;
      badgeFg = placed ? Colors.white : AppColors.textMuted;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: placed ? badgeFg.withValues(alpha: 0.22) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: badgeFg),
              ),
              child: Text(
                placed ? '${position + 1}' : '',
                style: TextStyle(
                  color: badgeFg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                line,
                style: TextStyle(
                  color: fg,
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBar extends StatelessWidget {
  final Task task;
  final bool correct;

  const _FeedbackBar({required this.task, required this.correct});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (correct ? AppColors.success : AppColors.danger)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.thumb_up_alt : Icons.mood_bad,
                color: correct ? AppColors.success : AppColors.danger,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                correct ? 'Верно!' : 'Не совсем',
                style: TextStyle(
                  color: correct ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (task.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.explanation,
              style: const TextStyle(fontSize: 14.5, height: 1.45),
            ),
          ],
          if (!correct &&
              task.type == TaskType.codeEditor &&
              task.solution.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Пример решения:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            CodeBlock(code: task.solution),
          ],
        ],
      ),
    );
  }
}

class _BottomButtons extends StatelessWidget {
  final bool hasTask;
  final bool canCheck;
  final bool submitted;
  final bool isCorrect;
  final VoidCallback onCheck;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  const _BottomButtons({
    required this.hasTask,
    required this.canCheck,
    required this.submitted,
    required this.isCorrect,
    required this.onCheck,
    required this.onNext,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasTask) {
      return FilledButton(onPressed: onNext, child: const Text('Далее'));
    }
    if (submitted && !isCorrect) {
      return FilledButton(
        onPressed: onRetry,
        child: const Text('Попробовать ещё раз'),
      );
    }
    if (submitted) {
      return FilledButton(onPressed: onNext, child: const Text('Далее'));
    }
    return FilledButton(
      onPressed: canCheck ? onCheck : null,
      child: const Text('Проверить'),
    );
  }
}