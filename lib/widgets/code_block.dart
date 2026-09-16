import 'package:flutter/material.dart';

import '../theme.dart';

const _keywords = {
  'def', 'return', 'if', 'elif', 'else', 'for', 'while', 'in',
  'import', 'from', 'as', 'class', 'lambda', 'pass', 'break',
  'continue', 'with', 'try', 'except', 'finally', 'raise', 'not',
  'and', 'or', 'is', 'None', 'True', 'False', 'self', 'yield',
};

List<TextSpan> _highlightLine(String line) {
  final spans = <TextSpan>[];
  for (var i = 0; i < line.length;) {
    final ch = line[i];
    final rest = line.substring(i);

    if (rest.startsWith('#')) {
      spans.add(TextSpan(
        text: rest,
        style: TextStyle(color: const Color(0xFF8887A8), fontStyle: FontStyle.italic),
      ));
      break;
    }

    if (ch == '"' || ch == "'") {
      String escaped = ch;
      var j = i + 1;
      final triple = line.startsWith('${ch.toString() * 3}', i);
      final delim = triple ? ch.toString() * 3 : ch.toString();
      while (j < line.length) {
        escaped += line[j];
        if (line[j] == ch && !(j > i && line[j - 1] == r'\')) {
          if (triple) {
            if (line.startsWith(delim, j - 2)) {
              j++;
              break;
            }
          } else {
            j++;
            break;
          }
        }
        j++;
      }
      spans.add(TextSpan(
        text: escaped,
        style: const TextStyle(color: Color(0xFF9EE6B9)),
      ));
      i = j;
      continue;
    }

    if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
      final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').firstMatch(rest)!;
      final word = m.group(0)!;
      final isKw = _keywords.contains(word);
      spans.add(TextSpan(
        text: word,
        style: TextStyle(
          color: isKw ? const Color(0xFF8F7BFF) : null,
          fontWeight: isKw ? FontWeight.w700 : FontWeight.w400,
        ),
      ));
      i += word.length;
      continue;
    }

    if (RegExp(r'[0-9]').hasMatch(ch)) {
      final m = RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(rest)!;
      spans.add(TextSpan(
        text: m.group(0)!,
        style: const TextStyle(color: Color(0xFFFFC46B)),
      ));
      i += m.group(0)!.length;
      continue;
    }

    spans.add(TextSpan(text: ch));
    i++;
  }
  return spans;
}

List<TextSpan> highlightCode(String code) {
  final lines = code.split('\n');
  final out = <TextSpan>[];
  for (var i = 0; i < lines.length; i++) {
    out.addAll(_highlightLine(lines[i]));
    if (i < lines.length - 1) out.add(const TextSpan(text: '\n'));
  }
  return out;
}

class CodeBlock extends StatelessWidget {
  final String code;
  final bool compact;

  const CodeBlock({super.key, required this.code, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
              color: AppColors.codeText,
            ),
            children: highlightCode(code),
          ),
        ),
      ),
    );
  }
}